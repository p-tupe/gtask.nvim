---@class GtaskApi
---Google Tasks API client with automatic token refresh
local M = {}

local config = require("gtask.config")
local store = require("gtask.store")
local utils = require("gtask.utils")
local Job = require("plenary.job")

--- Get proxy backend URL from config (dynamically to respect setup() changes)
---@return string The proxy base URL
local function get_proxy_url()
	return config.proxy.base_url
end

--- Refresh OAuth access token using refresh token
--- Called automatically when API returns 401 unauthorized
---@param refresh_token string The refresh token to use
---@param callback function Callback called with new tokens or nil on error
local function refresh_tokens(refresh_token, callback)
	if not refresh_token or refresh_token == "" then
		utils.notify("No refresh token available", vim.log.levels.ERROR)
		if callback then
			callback(nil, "No refresh token")
		end
		return
	end

	utils.notify("Access token expired. Refreshing via proxy...")

	-- Prepare request body for proxy
	local request_body = vim.fn.json_encode({
		refresh_token = refresh_token,
	})

	Job:new({
		command = "curl",
		args = {
			"-s",
			"-X",
			"POST",
			"-H",
			"Content-Type: application/json",
			"-d",
			request_body,
			get_proxy_url() .. "/auth/refresh",
		},
		on_exit = function(j, return_val)
			vim.schedule(function()
				if return_val == 0 then
					local response = table.concat(j:result())
					local success, new_tokens = pcall(vim.fn.json_decode, response)

					if not success or not new_tokens or not new_tokens.access_token then
						utils.notify("Invalid response from token refresh", vim.log.levels.ERROR)
						if callback then
							callback(nil, "Invalid refresh response")
						end
						return
					end

					-- Google doesn't always return a new refresh token, preserve the old one
					if not new_tokens.refresh_token then
						new_tokens.refresh_token = refresh_token
					end

					store.save_tokens(new_tokens)
					utils.notify("Tokens refreshed successfully.")
					if callback then
						callback(new_tokens)
					end
				else
					local error_msg = table.concat(j:stderr_result())
					utils.notify("Error refreshing tokens: " .. error_msg, vim.log.levels.ERROR)
					if callback then
						callback(nil, error_msg)
					end
				end
			end)
		end,
	}):start()
end

--- Make an authenticated request to the Google Tasks API
--- Handles token refresh automatically on 401 responses
---@param opts table Request options (url, method, body)
---@param callback function Callback called with response data or error
local function request(opts, callback)
	if not opts or not opts.url then
		utils.notify("Invalid request options", vim.log.levels.ERROR)
		if callback then
			callback(nil, "Invalid request options")
		end
		return
	end

	local tokens = store.load_tokens()
	if not tokens or not tokens.access_token then
		vim.schedule(function()
			utils.notify("Not authenticated. Please run :GtaskAuth", vim.log.levels.ERROR)
		end)
		if callback then
			callback(nil, "Not authenticated")
		end
		return
	end

	local function make_request(access_token)
		if not access_token or access_token == "" then
			if callback then
				callback(nil, "Invalid access token")
			end
			return
		end

		local curl_args = {
			"-s", -- Silent
			"-X",
			opts.method or "GET",
			"-H",
			"Authorization: Bearer " .. access_token,
			"-H",
			"Content-Type: application/json",
		}

		if opts.body then
			local success, encoded_body = pcall(vim.fn.json_encode, opts.body)
			if not success then
				if callback then
					callback(nil, "Failed to encode request body")
				end
				return
			end
			table.insert(curl_args, "-d")
			table.insert(curl_args, encoded_body)
		end

		table.insert(curl_args, opts.url)

		Job:new({
			command = "curl",
			args = curl_args,
			on_exit = function(j, return_val)
				vim.schedule(function()
					local result = table.concat(j:result())

					if return_val == 0 and result ~= "" then
						local success, decoded_result = pcall(vim.fn.json_decode, result)

						if not success then
							callback(nil, "Invalid JSON response: " .. result)
							return
						end

						-- Check for API errors
						if decoded_result and decoded_result.error then
							if decoded_result.error.code == 401 then
								-- Token expired, try to refresh
								if tokens.refresh_token then
									refresh_tokens(tokens.refresh_token, function(new_tokens)
										if new_tokens then
											make_request(new_tokens.access_token) -- Retry with new token
										else
											callback(nil, "Failed to refresh token")
										end
									end)
								else
									callback(nil, "Unauthorized: No refresh token available")
								end
								return
							else
								callback(nil, "API Error: " .. (decoded_result.error.message or "Unknown error"))
								return
							end
						end

						callback(decoded_result)
					elseif return_val == 0 then
						-- Empty response but successful
						callback({})
					else
						local error_msg = table.concat(j:stderr_result())
						callback(nil, "Request failed: " .. (error_msg ~= "" and error_msg or result))
					end
				end)
			end,
		}):start()
	end

	make_request(tokens.access_token)
end

--- Get all task lists for the authenticated user (with pagination)
--- Retrieves all task lists from Google Tasks API, automatically handling pagination
---@param callback function Callback called with task lists array or error
function M.get_task_lists(callback)
	local all_lists = {}

	-- Recursive function to fetch all pages
	local function fetch_page(page_token)
		local url = "https://tasks.googleapis.com/tasks/v1/users/@me/lists?maxResults=100"

		if page_token then
			url = url .. "&pageToken=" .. page_token
		end

		request({
			url = url,
		}, function(response, err)
			if err then
				callback(nil, err)
				return
			end

			-- Add lists from this page
			local page_lists = response.items or {}
			for _, list in ipairs(page_lists) do
				table.insert(all_lists, list)
			end

			-- Check if there are more pages
			if response.nextPageToken then
				utils.notify(
					string.format("Fetching next page of task lists (fetched %d so far)...", #all_lists),
					vim.log.levels.INFO
				)
				fetch_page(response.nextPageToken)
			else
				-- No more pages, return all lists
				callback({ items = all_lists })
			end
		end)
	end

	-- Start fetching from the first page
	fetch_page(nil)
end

--- Get all tasks from a specific task list (with pagination)
--- Retrieves all tasks from the specified task list, automatically handling pagination
---@param task_list_id string The ID of the task list to retrieve tasks from
---@param callback function Callback called with tasks array or error
function M.get_tasks(task_list_id, callback)
	if not task_list_id or task_list_id == "" then
		utils.notify("Task list ID is required", vim.log.levels.ERROR)
		if callback then
			callback(nil, "Task list ID is required")
		end
		return
	end

	local all_tasks = {}

	-- Recursive function to fetch all pages
	local function fetch_page(page_token)
		local url = string.format(
			"https://tasks.googleapis.com/tasks/v1/lists/%s/tasks?showCompleted=true&showHidden=true&maxResults=100",
			task_list_id
		)

		if page_token then
			url = url .. "&pageToken=" .. page_token
		end

		request({
			url = url,
		}, function(response, err)
			if err then
				callback(nil, err)
				return
			end

			-- Add tasks from this page
			local page_tasks = response.items or {}
			for _, task in ipairs(page_tasks) do
				table.insert(all_tasks, task)
			end

			-- Check if there are more pages
			if response.nextPageToken then
				utils.notify(
					string.format("Fetching next page of tasks (fetched %d so far)...", #all_tasks),
					vim.log.levels.INFO
				)
				fetch_page(response.nextPageToken)
			else
				-- No more pages, return all tasks
				callback({ items = all_tasks })
			end
		end)
	end

	-- Start fetching from the first page
	fetch_page(nil)
end

--- Create a new task in the specified task list
--- Creates a new task with the provided data
---@param task_list_id string The ID of the task list to create the task in
---@param task_data table Task data (title, notes, status, etc.)
---@param callback function Callback called with created task or error
function M.create_task(task_list_id, task_data, callback)
	if not task_list_id or task_list_id == "" then
		utils.notify("Task list ID is required", vim.log.levels.ERROR)
		if callback then
			callback(nil, "Task list ID is required")
		end
		return
	end

	if not task_data or not task_data.title then
		utils.notify("Task data with title is required", vim.log.levels.ERROR)
		if callback then
			callback(nil, "Task data with title is required")
		end
		return
	end

	request({
		method = "POST",
		url = string.format("https://tasks.googleapis.com/tasks/v1/lists/%s/tasks", task_list_id),
		body = task_data,
	}, callback)
end

--- Update an existing task
--- Updates the specified task with new data
---@param task_list_id string The ID of the task list containing the task
---@param task_id string The ID of the task to update
---@param task_data table Updated task data
---@param callback function Callback called with updated task or error
function M.update_task(task_list_id, task_id, task_data, callback)
	if not task_list_id or task_list_id == "" then
		utils.notify("Task list ID is required", vim.log.levels.ERROR)
		if callback then
			callback(nil, "Task list ID is required")
		end
		return
	end

	if not task_id or task_id == "" then
		utils.notify("Task ID is required", vim.log.levels.ERROR)
		if callback then
			callback(nil, "Task ID is required")
		end
		return
	end

	if not task_data then
		utils.notify("Task data is required", vim.log.levels.ERROR)
		if callback then
			callback(nil, "Task data is required")
		end
		return
	end

	request({
		method = "PATCH",
		url = string.format("https://tasks.googleapis.com/tasks/v1/lists/%s/tasks/%s", task_list_id, task_id),
		body = task_data,
	}, callback)
end

--- Find a task list by name
---@param list_name string The name of the task list to find
---@param callback function Callback called with list object or nil if not found
function M.find_list_by_name(list_name, callback)
	M.get_task_lists(function(response, err)
		if err then
			callback(nil, err)
			return
		end

		local lists = response.items or {}

		-- Debug: Log all available list names
		local list_names = {}
		for _, list in ipairs(lists) do
			table.insert(list_names, string.format("'%s'", list.title))
			if list.title == list_name then
				utils.notify(string.format("Found existing list: %s", list_name), vim.log.levels.INFO)
				callback(list)
				return
			end
		end

		-- List not found - log available lists for debugging
		utils.notify(
			string.format("List '%s' not found. Available lists: %s", list_name, table.concat(list_names, ", ")),
			vim.log.levels.INFO
		)
		callback(nil)
	end)
end

--- Create a new task list
---@param list_name string The name of the new task list
---@param callback function Callback called with created list or error
function M.create_task_list(list_name, callback)
	if not list_name or list_name == "" then
		utils.notify("List name is required", vim.log.levels.ERROR)
		if callback then
			callback(nil, "List name is required")
		end
		return
	end

	request({
		method = "POST",
		url = "https://tasks.googleapis.com/tasks/v1/users/@me/lists",
		body = { title = list_name },
	}, function(response, err)
		if err then
			utils.notify(string.format("Failed to create list '%s': %s", list_name, err), vim.log.levels.ERROR)
			callback(nil, err)
		else
			utils.notify(
				string.format("Successfully created list '%s' with ID: %s", list_name, response.id or "unknown"),
				vim.log.levels.INFO
			)
			callback(response, nil)
		end
	end)
end

--- Get or create a task list by name
--- Finds an existing list by name, or creates it if it doesn't exist
---@param list_name string The name of the task list
---@param callback function Callback called with list object
function M.get_or_create_list(list_name, callback)
	if not list_name or list_name == "" then
		utils.notify("List name is required", vim.log.levels.ERROR)
		if callback then
			callback(nil, "List name is required")
		end
		return
	end

	-- First, try to find existing list
	M.find_list_by_name(list_name, function(list, err)
		if err then
			callback(nil, err)
			return
		end

		if list then
			-- List exists, return it
			callback(list)
		else
			-- List doesn't exist, create it
			utils.notify(string.format("Creating new task list: %s", list_name))
			M.create_task_list(list_name, callback)
		end
	end)
end

--- Create a task with optional parent and positioning
--- Supports creating subtasks by specifying a parent task ID
---@param task_list_id string The ID of the task list to create the task in
---@param task_data table Task data (title, notes, status, due)
---@param parent_id string|nil Parent task ID (nil for top-level tasks)
---@param previous_id string|nil Previous sibling task ID for ordering (optional)
---@param callback function Callback called with created task or error
function M.create_task_with_parent(task_list_id, task_data, parent_id, previous_id, callback)
	if not task_list_id or task_list_id == "" then
		utils.notify("Task list ID is required", vim.log.levels.ERROR)
		if callback then
			callback(nil, "Task list ID is required")
		end
		return
	end

	if not task_data or not task_data.title then
		utils.notify("Task data with title is required", vim.log.levels.ERROR)
		if callback then
			callback(nil, "Task data with title is required")
		end
		return
	end

	local url = string.format("https://tasks.googleapis.com/tasks/v1/lists/%s/tasks", task_list_id)

	-- Build query parameters for parent and ordering
	local query_params = {}
	if parent_id and parent_id ~= "" then
		table.insert(query_params, "parent=" .. parent_id)
	end
	if previous_id and previous_id ~= "" then
		table.insert(query_params, "previous=" .. previous_id)
	end

	if #query_params > 0 then
		url = url .. "?" .. table.concat(query_params, "&")
	end

	request({
		method = "POST",
		url = url,
		body = task_data,
	}, callback)
end

--- Delete a task
--- Permanently deletes a task from Google Tasks
---@param task_list_id string The ID of the task list containing the task
---@param task_id string The ID of the task to delete
---@param callback function Callback called with success or error
function M.delete_task(task_list_id, task_id, callback)
	if not task_list_id or task_list_id == "" then
		utils.notify("Task list ID is required", vim.log.levels.ERROR)
		if callback then
			callback(nil, "Task list ID is required")
		end
		return
	end

	if not task_id or task_id == "" then
		utils.notify("Task ID is required", vim.log.levels.ERROR)
		if callback then
			callback(nil, "Task ID is required")
		end
		return
	end

	request({
		method = "DELETE",
		url = string.format("https://tasks.googleapis.com/tasks/v1/lists/%s/tasks/%s", task_list_id, task_id),
	}, callback)
end

return M
