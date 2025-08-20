---@class GtaskApi
---Google Tasks API client with automatic token refresh
local M = {}

local config = require("gtask.config")
local store = require("gtask.store")
local Job = require("plenary.job")

-- Get proxy backend URL from config
local PROXY_BASE_URL = config.proxy.base_url

--- Refresh OAuth access token using refresh token
--- Called automatically when API returns 401 unauthorized
---@param refresh_token string The refresh token to use
---@param callback function Callback called with new tokens or nil on error
local function refresh_tokens(refresh_token, callback)
	if not refresh_token or refresh_token == "" then
		vim.notify("No refresh token available", vim.log.levels.ERROR)
		if callback then
			callback(nil, "No refresh token")
		end
		return
	end

	vim.notify("Access token expired. Refreshing via proxy...")

	-- Prepare request body for proxy
	local request_body = vim.fn.json_encode({
		refresh_token = refresh_token
	})

	Job:new({
		command = "curl",
		args = {
			"-s",
			"-X", "POST",
			"-H", "Content-Type: application/json",
			"-d", request_body,
			PROXY_BASE_URL .. "/auth/refresh"
		},
		on_exit = function(j, return_val)
			vim.schedule(function()
				if return_val == 0 then
					local response = table.concat(j:result())
					local success, new_tokens = pcall(vim.fn.json_decode, response)

					if not success or not new_tokens or not new_tokens.access_token then
						vim.notify("Invalid response from token refresh", vim.log.levels.ERROR)
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
					vim.notify("Tokens refreshed successfully.")
					if callback then
						callback(new_tokens)
					end
				else
					local error_msg = table.concat(j:stderr_result())
					vim.notify("Error refreshing tokens: " .. error_msg, vim.log.levels.ERROR)
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
		vim.notify("Invalid request options", vim.log.levels.ERROR)
		if callback then
			callback(nil, "Invalid request options")
		end
		return
	end

	local tokens = store.load_tokens()
	if not tokens or not tokens.access_token then
		vim.schedule(function()
			vim.notify("Not authenticated. Please run :GtaskAuth", vim.log.levels.ERROR)
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

--- Get all task lists for the authenticated user
--- Retrieves all task lists from Google Tasks API
---@param callback function Callback called with task lists array or error
function M.get_task_lists(callback)
	request({
		url = "https://tasks.googleapis.com/tasks/v1/users/@me/lists",
	}, callback)
end

--- Get all tasks from a specific task list
--- Retrieves all tasks from the specified task list
---@param task_list_id string The ID of the task list to retrieve tasks from
---@param callback function Callback called with tasks array or error
function M.get_tasks(task_list_id, callback)
	if not task_list_id or task_list_id == "" then
		vim.notify("Task list ID is required", vim.log.levels.ERROR)
		if callback then
			callback(nil, "Task list ID is required")
		end
		return
	end

	request({
		url = string.format("https://tasks.googleapis.com/tasks/v1/lists/%s/tasks", task_list_id),
	}, callback)
end

--- Create a new task in the specified task list
--- Creates a new task with the provided data
---@param task_list_id string The ID of the task list to create the task in
---@param task_data table Task data (title, notes, status, etc.)
---@param callback function Callback called with created task or error
function M.create_task(task_list_id, task_data, callback)
	if not task_list_id or task_list_id == "" then
		vim.notify("Task list ID is required", vim.log.levels.ERROR)
		if callback then
			callback(nil, "Task list ID is required")
		end
		return
	end

	if not task_data or not task_data.title then
		vim.notify("Task data with title is required", vim.log.levels.ERROR)
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
		vim.notify("Task list ID is required", vim.log.levels.ERROR)
		if callback then
			callback(nil, "Task list ID is required")
		end
		return
	end

	if not task_id or task_id == "" then
		vim.notify("Task ID is required", vim.log.levels.ERROR)
		if callback then
			callback(nil, "Task ID is required")
		end
		return
	end

	if not task_data then
		vim.notify("Task data is required", vim.log.levels.ERROR)
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

return M
