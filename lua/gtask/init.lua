local M = {}

--- Setup function to configure gtask.nvim
--- Call this in your Neovim config to customize the plugin behavior
---@param opts table|nil Configuration options
---   - proxy_url: string|nil - Custom URL for the OAuth proxy backend (default: "https://app.priteshtupe.com/gtask")
---   - markdown_dir: string|nil - Absolute path to markdown directory (default: "~/gtask.nvim")
---                                Must start with / or ~ (no relative paths)
---   - ignore_patterns: string[]|nil - List of directory names or .md file names to ignore
---                                     Directory names will skip entire subdirectories
---                                     File names will skip specific markdown files
---                                     (default: {})
---
--- Example:
---   require('gtask').setup({
---     proxy_url = "https://my-gtask-proxy.example.com",
---     markdown_dir = "~/notes",
---     ignore_patterns = { "archive", "draft.md" },
---   })
function M.setup(opts)
	require("gtask.config").setup(opts)
end

return M
