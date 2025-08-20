---@class GtaskAuth
---OAuth 2.0 authentication module for Google Tasks API
local M = {}

local config = require("gtask.config")
local store = require("gtask.store")
local Job = require("plenary.job")

-- Get proxy backend URL from config
local PROXY_BASE_URL = config.proxy.base_url

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
				PROXY_BASE_URL .. "/auth/poll/" .. state
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
			PROXY_BASE_URL .. "/auth/start"
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

--- Exchange authorization code for tokens via proxy backend
---@param code string The authorization code from OAuth flow
---@param callback? function Optional callback function called with tokens or error
local function exchange_code_for_tokens(code, callback)
	if not code or code == "" then
		vim.notify("Invalid authorization code", vim.log.levels.ERROR)
		return
	end

	if not oauth_state.state then
		vim.notify("No OAuth state found. Please restart the authentication flow.", vim.log.levels.ERROR)
		return
	end

	vim.notify("Exchanging code for tokens via proxy...", vim.log.levels.DEBUG)

	-- Prepare request body
	local request_body = vim.fn.json_encode({
		code = code,
		state = oauth_state.state
	})

	-- Call proxy backend to exchange code for tokens
	Job:new({
		command = "curl",
		args = {
			"-s",
			"-X", "POST",
			"-H", "Content-Type: application/json",
			"-d", request_body,
			PROXY_BASE_URL .. "/auth/token"
		},
		on_exit = function(j, return_val)
			vim.schedule(function()
				if return_val == 0 then
					local response = table.concat(j:result())
					vim.notify("Proxy token response: " .. response, vim.log.levels.DEBUG)

					local success, tokens = pcall(vim.fn.json_decode, response)

					if not success then
						vim.notify("Failed to parse proxy response: " .. response, vim.log.levels.ERROR)
						if callback then
							callback(nil, "JSON parse error")
						end
						return
					end

					if not tokens then
						vim.notify("No tokens in proxy response: " .. response, vim.log.levels.ERROR)
						if callback then
							callback(nil, "No tokens in response")
						end
						return
					end

					if tokens.error then
						vim.notify(
							"Proxy OAuth error: " .. tokens.error .. " - " .. (tokens.error_description or ""),
							vim.log.levels.ERROR
						)
						if callback then
							callback(nil, tokens.error)
						end
						return
					end

					if not tokens.access_token then
						vim.notify("No access token in proxy response: " .. response, vim.log.levels.ERROR)
						if callback then
							callback(nil, "No access token")
						end
						return
					end

					vim.notify("Authentication successful! Tokens received via proxy.")
					store.save_tokens(tokens)
					-- Clear OAuth state after successful token exchange
					oauth_state.state = nil
					if callback then
						callback(tokens)
					end
				else
					local error_msg = table.concat(j:stderr_result())
					vim.notify("Error contacting proxy for token exchange: " .. error_msg, vim.log.levels.ERROR)
					if callback then
						callback(nil, error_msg)
					end
				end
			end)
		end,
	}):start()
end

--- Start a local HTTP server to receive the OAuth callback
--- Creates a temporary server on localhost to capture the authorization code
---@param callback function Function called with the authorization code
local function start_local_server(callback)
	local port = config.oauth_port
	if not port or port <= 0 or port > 65535 then
		vim.schedule(function()
			vim.notify("Invalid port configuration: " .. tostring(port), vim.log.levels.ERROR)
		end)
		return
	end

	local server = vim.loop.new_tcp()
	if not server then
		vim.schedule(function()
			vim.notify("Failed to create TCP server", vim.log.levels.ERROR)
		end)
		return
	end

	local bind_success, bind_err = server:bind("127.0.0.1", port)
	if not bind_success then
		vim.schedule(function()
			vim.notify("Failed to bind to port " .. port .. ": " .. (bind_err or "unknown error"), vim.log.levels.ERROR)
		end)
		server:close()
		return
	end

	local listen_success, listen_err = server:listen(1, function(err)
		if err then
			vim.schedule(function()
				vim.notify("Server listen error: " .. err, vim.log.levels.ERROR)
			end)
			return
		end

		local client = vim.loop.new_tcp()
		if not client then
			vim.schedule(function()
				vim.notify("Failed to create client TCP handle", vim.log.levels.ERROR)
			end)
			server:close()
			return
		end

		local accept_err = server:accept(client)
		if accept_err ~= 0 then
			vim.schedule(function()
				vim.notify("Server accept error: " .. accept_err, vim.log.levels.ERROR)
			end)
			client:close()
			server:close()
			return
		end

		client:read_start(function(read_err, data)
			if read_err then
				vim.schedule(function()
					vim.notify("Client read error: " .. read_err, vim.log.levels.ERROR)
				end)
				client:close()
				server:close()
				return
			end

			if data then
				-- Extract authorization code from the request
				local code = data:match("GET /%?code=([^%s&]+)")
				if code then
					local response_body = "Authentication successful! You can close this page."
					local response = "HTTP/1.1 200 OK\r\n"
						.. "Content-Type: text/html\r\n"
						.. "Content-Length: "
						.. #response_body
						.. "\r\n"
						.. "Connection: close\r\n\r\n"
						.. response_body

					client:write(response, function(write_err)
						if write_err then
							vim.schedule(function()
								vim.notify("Client write error: " .. write_err, vim.log.levels.ERROR)
							end)
						end
						client:close()
						server:close()
					end)

					if callback then
						vim.schedule(function()
							callback(code)
						end)
					end
				end
			end
		end)
	end)

	if not listen_success then
		vim.schedule(function()
			vim.notify("Failed to start server: " .. (listen_err or "unknown error"), vim.log.levels.ERROR)
		end)
		server:close()
		return
	end

	vim.schedule(function()
		vim.notify("Local server started on port " .. port .. ". Waiting for authorization code...")
	end)
end

--- Start the OAuth 2.0 authentication flow
--- Opens authorization URL and starts local server to receive callback
---@param callback? function Optional callback called when authentication completes
function M.authenticate(callback)
	-- Check if already authenticated
	if store.has_tokens() then
		vim.notify("Already authenticated. Use :GtaskClearAuth to re-authenticate.", vim.log.levels.INFO)
		if callback then
			callback(true)
		end
		return
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

--- Mock function for testing token exchange
---@param code string Authorization code
---@param callback? function Callback function
local function exchange_code_for_tokens_mock(code, callback)
	vim.schedule(function()
		vim.notify("TEST: Mock token exchange successful! Received code: " .. code)
		if callback then
			callback({ access_token = "test_access_token", refresh_token = "test_refresh_token" })
		end
	end)
end

--- Test the authentication server functionality
--- This is a development/testing function that simulates the OAuth flow
function M.authenticate_test()
	vim.notify("Starting server test...")
	start_local_server(function(code)
		exchange_code_for_tokens_mock(code)
	end)

	-- Give the server a moment to start, then send a test request
	vim.defer_fn(function()
		local url = string.format("http://127.0.0.1:%s/?code=test_code_12345", config.oauth_port)
		Job:new({
			command = "curl",
			args = { "-s", "-o", "/dev/null", url },
			on_exit = function(j, return_val)
				vim.schedule(function()
					if return_val == 0 then
						vim.notify("TEST: curl request sent successfully.")
					else
						vim.notify("TEST: curl request failed.", vim.log.levels.WARN)
					end
				end)
			end,
		}):start()
	end, 100) -- 100ms delay to ensure server is ready
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
