---@class GtaskAuth
---OAuth 2.0 authentication module for Google Tasks API
local M = {}

local config = require("gtask.config")
local store = require("gtask.store")
local utils = require("gtask.utils")

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
		utils.notify("No OAuth state to poll for", vim.log.levels.ERROR)
		return
	end

	local poll_count = 0
	local max_polls = 60 -- Poll for up to 5 minutes (60 * 5 seconds)

	local function do_poll()
		poll_count = poll_count + 1

		if poll_count > max_polls then
			utils.notify("Authentication timed out. Please try again.", vim.log.levels.ERROR)
			oauth_state.state = nil
			if callback then
				callback(nil, "Authentication timeout")
			end
			return
		end

		vim.system({
			"curl",
			"-s",
			get_proxy_url() .. "/auth/poll/" .. state,
		}, { text = true }, function(obj)
			vim.schedule(function()
				if obj.code == 0 then
					local response = obj.stdout or ""
					local success, data = pcall(vim.fn.json_decode, response)

					if success and data then
						if data.completed then
							-- Authentication completed!
							utils.notify("Authentication successful! Tokens received via proxy.")
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
						utils.notify("Error parsing poll response: " .. response, vim.log.levels.ERROR)
						vim.defer_fn(do_poll, 5000) -- Continue polling despite error
					end
				else
					local error_msg = obj.stderr or ""
					utils.notify("Error polling for auth completion: " .. error_msg, vim.log.levels.ERROR)
					vim.defer_fn(do_poll, 5000) -- Continue polling despite error
				end
			end)
		end)
	end

	-- Start polling
	do_poll()
end

--- Generate the OAuth 2.0 authorization URL via proxy backend
--- Calls the proxy backend to get a secure authorization URL
---@param callback function Optional callback called with auth URL or error
function M.get_authorization_url(callback)
	-- Call proxy backend to generate auth URL
	vim.system({
		"curl",
		"-s",
		"-X",
		"POST",
		"-H",
		"Content-Type: application/json",
		"-d",
		"{}",
		get_proxy_url() .. "/auth/start",
	}, { text = true }, function(obj)
		vim.schedule(function()
			if obj.code == 0 then
				local response = obj.stdout or ""
				local success, data = pcall(vim.fn.json_decode, response)

				if success and data and data.authUrl and data.state then
					-- Store state for token exchange
					oauth_state.state = data.state
					utils.notify("DEBUG: Generated auth URL via proxy", vim.log.levels.DEBUG)

					if callback then
						callback(data.authUrl, nil)
					end
				else
					local error_msg = "Invalid response from auth proxy: " .. response
					utils.notify(error_msg, vim.log.levels.ERROR)
					if callback then
						callback(nil, error_msg)
					end
				end
			else
				local error_msg = "Failed to contact auth proxy: " .. (obj.stderr or "")
				utils.notify(error_msg, vim.log.levels.ERROR)
				if callback then
					callback(nil, error_msg)
				end
			end
		end)
	end)
end

--- Start the OAuth 2.0 authentication flow
--- Clears previous authentication and forces new authorization
---@param callback? function Optional callback called when authentication completes
function M.authenticate(callback)
	-- Clear any existing tokens to force re-authentication
	if store.has_tokens() then
		utils.notify("Clearing previous authentication...")
		store.clear_tokens()
	end

	-- Get authorization URL from proxy backend
	M.get_authorization_url(function(auth_url, err)
		if err then
			utils.notify("Failed to get authorization URL: " .. err, vim.log.levels.ERROR)
			return
		end

		-- Copy to clipboard if available
		local clipboard_success = pcall(vim.fn.setreg, "+", auth_url)

		-- Display the URL prominently
		utils.notify("Please visit this URL to authorize:", vim.log.levels.INFO)
		utils.notify(auth_url, vim.log.levels.WARN)

		if clipboard_success then
			utils.notify("(URL copied to clipboard)", vim.log.levels.INFO)
		end

		-- Also echo the URL to command line to ensure it's visible
		vim.schedule(function()
			vim.cmd("echohl WarningMsg")
			vim.cmd('echo "Auth URL: ' .. auth_url:gsub('"', '\\"') .. '"')
			vim.cmd("echohl None")
		end)

		-- Start polling for completion
		utils.notify("Waiting for authorization... (check your browser)", vim.log.levels.INFO)
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
