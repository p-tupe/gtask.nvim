---Mock plenary for testing
local M = {}

-- Mock plenary.job
M.job = {
  new = function(opts)
    return {
      start = function() end,
      wait = function() end,
      sync = function()
        -- Return mock response
        if opts.on_exit then
          opts.on_exit(nil, 0)
        end
      end,
    }
  end,
}

-- Mock plenary.curl (if needed)
M.curl = {
  post = function(url, opts)
    -- Return mock response
    return {
      status = 200,
      body = '{"access_token":"mock_token"}',
    }
  end,
  get = function(url, opts)
    return {
      status = 200,
      body = '{}',
    }
  end,
}

-- Setup mocks
function M.setup()
  package.loaded["plenary.job"] = M.job
  package.loaded["plenary.curl"] = M.curl
end

return M
