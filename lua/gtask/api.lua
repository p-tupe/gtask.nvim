local M = {}

local config = require("gtask.config")
local store = require("gtask.store")
local Job = require("plenary.job")

local function refresh_tokens(refresh_token, callback)
	vim.notify("Access token expired. Refreshing...")

	local params = {
		client_id = config.credentials.client_id,
		client_secret = config.credentials.client_secret,
		refresh_token = refresh_token,
		grant_type = "refresh_token",
	}

	Job:new({
		command = "curl",
		args = {
			"-X",
			"POST",
			"https://oauth2.googleapis.com/token",
			"-d",
			"client_id=" .. params.client_id,
			"-d",
			"client_secret=" .. params.client_secret,
			"-d",
			"refresh_token=" .. params.refresh_token,
			"-d",
			"grant_type=" .. params.grant_type,
		},
		on_exit = function(j, return_val)
			vim.schedule(function()
				if return_val == 0 then
					local response = table.concat(j:result())
					local new_tokens = vim.fn.json_decode(response)
					-- Google doesn't always return a new refresh token, so we keep the old one.
					new_tokens.refresh_token = refresh_token
					store.save_tokens(new_tokens)
					vim.notify("Tokens refreshed successfully.")
					if callback then
						callback(new_tokens)
					end
				else
					vim.notify("Error refreshing tokens:", vim.log.levels.ERROR)
					vim.notify(table.concat(j:stderr_result()), vim.log.levels.ERROR)
					if callback then
						callback(nil)
					end
				end
			end)
		end,
	}):start()
end

local function request(opts, callback)
	local tokens = store.load_tokens()
	if not tokens or not tokens.access_token then
		vim.schedule(function()
			vim.notify("Not authenticated. Please run :GtaskAuth", vim.log.levels.ERROR)
		end)
		return
	end

	local function make_request(access_token)
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
			table.insert(curl_args, "-d")
			table.insert(curl_args, vim.fn.json_encode(opts.body))
		end
		table.insert(curl_args, opts.url)

		Job:new({
			command = "curl",
			args = curl_args,
			on_exit = function(j, return_val)
				vim.schedule(function()
					local result = table.concat(j:result())
					local decoded_result = vim.fn.json_decode(result)

					if
						return_val ~= 0
						and decoded_result
						and decoded_result.error
						and decoded_result.error.code == 401
					then
						-- Token expired, try to refresh
						refresh_tokens(tokens.refresh_token, function(new_tokens)
							if new_tokens then
								make_request(new_tokens.access_token) -- Retry with new token
							else
								callback(nil, "Failed to refresh token")
							end
						end)
					elseif return_val == 0 then
						callback(decoded_result)
					else
						callback(nil, result)
					end
				end)
			end,
		}):start()
	end

	make_request(tokens.access_token)
end

function M.get_task_lists(callback)
	request({
		url = "https://tasks.googleapis.com/tasks/v1/users/@me/lists",
	}, callback)
end

function M.get_tasks(task_list_id, callback)
	request({
		url = string.format("https://tasks.googleapis.com/tasks/v1/lists/%s/tasks", task_list_id),
	}, callback)
end

return M
