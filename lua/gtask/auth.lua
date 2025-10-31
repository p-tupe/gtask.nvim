---@class GtaskAuth
---OAuth 2.0 authentication module for Google Tasks API
local M = {}

local config = require("gtask.config")
local store = require("gtask.store")
local Job = require("plenary.job")

--- Get proxy backend URL from config (dynamically to respect setup() changes)
---@return string The proxy base URL
local function get_proxy_url()
	return config.proxy.base_url
end

-- OAuth state storage for proxy backend
local oauth_state = {}

--- Poll the backend for OAuth completion
---@param state string The OAuth state to poll for
---@param callback? function Optional callback called when complete
local function poll_for_completion(state, callback)
	if not state then
		vim.notify("No OAuth state to poll for", vim.log.levels.ERROR)
		return
	end

	local poll_count = 0
	local max_polls = 60 -- Poll for up to 5 minutes (60 * 5 seconds)
	
	local function do_poll()
		poll_count = poll_count + 1
		
		if poll_count > max_polls then
			vim.notify("Authentication timed out. Please try again.", vim.log.levels.ERROR)
			oauth_state.state = nil
			if callback then
				callback(nil, "Authentication timeout")
			end
			return
		end

		Job:new({
			command = "curl",
			args = {
				"-s",
				get_proxy_url() .. "/auth/poll/" .. state
			},
			on_exit = function(j, return_val)
				vim.schedule(function()
					if return_val == 0 then
						local response = table.concat(j:result())
						local success, data = pcall(vim.fn.json_decode, response)
						
						if success and data then
							if data.completed then
								-- Authentication completed!
								vim.notify("Authentication successful! Tokens received via proxy.")
								store.save_tokens(data.tokens)
								oauth_state.state = nil
								if callback then
									callback(data.tokens)
								end
							else
								-- Not completed yet, continue polling
								vim.defer_fn(do_poll, 5000) -- Poll every 5 seconds
							end
						else
							vim.notify("Error parsing poll response: " .. response, vim.log.levels.ERROR)
							vim.defer_fn(do_poll, 5000) -- Continue polling despite error
						end
					else
						local error_msg = table.concat(j:stderr_result())
						vim.notify("Error polling for auth completion: " .. error_msg, vim.log.levels.ERROR)
						vim.defer_fn(do_poll, 5000) -- Continue polling despite error
					end
				end)
			end,
		}):start()
	end
	
	-- Start polling
	do_poll()
end

--- Generate the OAuth 2.0 authorization URL via proxy backend
--- Calls the proxy backend to get a secure authorization URL
---@param callback function Optional callback called with auth URL or error
function M.get_authorization_url(callback)
	-- Call proxy backend to generate auth URL
	Job:new({
		command = "curl",
		args = {
			"-s",
			"-X", "POST",
			"-H", "Content-Type: application/json",
			"-d", "{}",
			get_proxy_url() .. "/auth/start"
		},
		on_exit = function(j, return_val)
			vim.schedule(function()
				if return_val == 0 then
					local response = table.concat(j:result())
					local success, data = pcall(vim.fn.json_decode, response)
					
					if success and data and data.authUrl and data.state then
						-- Store state for token exchange
						oauth_state.state = data.state
						vim.notify("DEBUG: Generated auth URL via proxy", vim.log.levels.DEBUG)
						
						if callback then
							callback(data.authUrl, nil)
						end
					else
						local error_msg = "Invalid response from auth proxy: " .. response
						vim.notify(error_msg, vim.log.levels.ERROR)
						if callback then
							callback(nil, error_msg)
						end
					end
				else
					local error_msg = "Failed to contact auth proxy: " .. table.concat(j:stderr_result())
					vim.notify(error_msg, vim.log.levels.ERROR)
					if callback then
						callback(nil, error_msg)
					end
				end
			end)
		end,
	}):start()
end


--- Start the OAuth 2.0 authentication flow
--- Clears previous authentication and forces new authorization
---@param callback? function Optional callback called when authentication completes
function M.authenticate(callback)
	-- Clear any existing tokens to force re-authentication
	if store.has_tokens() then
		vim.notify("Clearing previous authentication...")
		store.clear_tokens()
	end

	-- Get authorization URL from proxy backend
	M.get_authorization_url(function(auth_url, err)
		if err then
			vim.notify("Failed to get authorization URL: " .. err, vim.log.levels.ERROR)
			return
		end

		vim.notify("Please visit the following URL in your browser to authorize the application:")
		print(auth_url)

		-- Copy to clipboard if available
		local clipboard_success = pcall(vim.fn.setreg, "+", auth_url)
		if clipboard_success then
			vim.notify("(URL has been copied to your clipboard)")
		end

		-- Start polling for completion
		vim.notify("Waiting for authorization... (check your browser)")
		poll_for_completion(oauth_state.state, callback)
	end)
end

--- Clear stored authentication tokens
--- Forces re-authentication on next API call
---@return boolean # True if tokens were cleared successfully
function M.clear_auth()
	return store.clear_tokens()
end

--- Check if user is currently authenticated
---@return boolean # True if valid tokens are stored
function M.is_authenticated()
	return store.has_tokens()
end

return M
