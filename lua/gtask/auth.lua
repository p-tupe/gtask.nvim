local M = {}

local config = require("gtask.config")
local store = require("gtask.store")
local Job = require("plenary.job")

--@return string
function M.get_authorization_url()
	local base_url = "https://accounts.google.com/o/oauth2/v2/auth"
	local params = {
		client_id = config.credentials.client_id,
		redirect_uri = config.credentials.redirect_uri,
		response_type = "code",
		scope = table.concat(config.scopes, " "),
		access_type = "offline", -- Required to get a refresh token
		prompt = "consent",
	}

	local query_string = ""
	for key, value in pairs(params) do
		-- URL encode values
		local encoded_value = vim.fn.escape(value, " !'()*;")
		query_string = query_string .. key .. "=" .. encoded_value .. "&"
	end
	query_string = query_string:sub(1, -2) -- Remove trailing ampersand

	return base_url .. "?" .. query_string
end

local function exchange_code_for_tokens(code, callback)
  local params = {
    client_id = config.credentials.client_id,
    client_secret = config.credentials.client_secret,
    code = code,
    redirect_uri = config.credentials.redirect_uri,
    grant_type = "authorization_code",
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
      "code=" .. code,
      "-d",
      "redirect_uri=" .. params.redirect_uri,
      "-d",
      "grant_type=" .. params.grant_type,
    },
    on_exit = function(j, return_val)
      vim.schedule(function()
        if return_val == 0 then
          local response = table.concat(j:result())
          local tokens = vim.fn.json_decode(response)
          vim.notify("Authentication successful! Tokens received.")
          store.save_tokens(tokens)
          if callback then
            callback(tokens)
          end
        else
          vim.notify("Error exchanging code for tokens:", vim.log.levels.ERROR)
          vim.notify(table.concat(j:stderr_result()), vim.log.levels.ERROR)
        end
      end)
    end,
  }):start()
end

local function start_local_server(callback)
  local port = tonumber(config.credentials.redirect_uri:match(":(%d+)"))
  if not port then
    vim.schedule(function()
      vim.notify("Invalid redirect_uri in config", vim.log.levels.ERROR)
    end)
    return
  end

  local server = vim.loop.new_tcp()

  server:bind("127.0.0.1", port)
  server:listen(1, function(err)
    if err then
      vim.schedule(function()
        vim.notify("Server listen error: " .. err, vim.log.levels.ERROR)
      end)
      return
    end

    local client = vim.loop.new_tcp()
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
        local code = data:match("GET /%?code=([^%s]+)")
        if code then
          local response_body = "Authentication successful! You can close this page."
          local response = "HTTP/1.1 200 OK\r\n"
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
  vim.schedule(function()
    vim.notify("Local server started on port " .. port .. ". Waiting for authorization code...")
  end)
end



function M.authenticate()
	local auth_url = M.get_authorization_url()
	print("Please visit the following URL in your browser to authorize the application:")
	print(auth_url)
	vim.fn.setreg("+", auth_url)
	print("(URL has been copied to your clipboard)")

	start_local_server(function(code)
		print("Authorization code received. Exchanging for tokens...")
		exchange_code_for_tokens(code)
	end)
end

local function exchange_code_for_tokens_mock(code, callback)
  vim.schedule(function()
    vim.notify("TEST: Mock token exchange successful! Received code: " .. code)
    if callback then
      callback({ access_token = "test_access_token", refresh_token = "test_refresh_token" })
    end
  end)
end

function M.authenticate_test()
  vim.notify("Starting server test...")
  start_local_server(function(code)
    exchange_code_for_tokens_mock(code)
  end)

  -- Give the server a moment to start, then send a test request
  vim.defer_fn(function()
    local port = config.credentials.redirect_uri:match(":(%d+)")
    local url = string.format("http://127.0.0.1:%s/?code=test_code_12345", port)
    Job:new({
      command = "curl",
      args = { "-s", "-o", "/dev/null", url },
      on_exit = function()
        vim.schedule(function()
          vim.notify("TEST: curl request sent.")
        end)
      end,
    }):start()
  end, 100) -- 100ms delay
end

return M
