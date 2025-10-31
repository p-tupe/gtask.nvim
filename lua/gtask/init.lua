local M = {}

--- Setup function to configure gtask.nvim
--- Call this in your Neovim config to customize the plugin behavior
---@param opts table|nil Configuration options
---   - proxy_url: string|nil - Custom URL for the OAuth proxy backend (default: "http://localhost:3000")
---   - token_file: string|nil - Custom filename for storing tokens (default: "gtask_tokens.json")
---   - markdown_dir: string|nil - Absolute path to markdown directory (default: "~/.gtask")
---                                Must start with / or ~ (no relative paths)
---
--- Example:
---   require('gtask').setup({
---     proxy_url = "https://my-gtask-proxy.example.com",
---     markdown_dir = "~/notes",  -- Must be absolute path
---   })
function M.setup(opts)
	require("gtask.config").setup(opts)
end

return M
