---@class GtaskConfig
---Configuration module for Google Tasks API settings
local M = {}

--- Default configuration
local defaults = {
	--- OAuth 2.0 scopes required for Google Tasks API access
	--- These scopes are used by the proxy backend service for authentication
	---@type string[]
	scopes = {
		"https://www.googleapis.com/auth/tasks",
	},

	--- Proxy backend configuration
	--- The backend service handles all OAuth credentials securely
	proxy = {
		--- Base URL for the OAuth proxy service
		--- Points to the deployed gtask auth proxy service
		--- Can be overridden via setup() function
		---@type string
		base_url = "https://app.priteshtupe.com/gtask",
	},

	--- Token storage configuration
	storage = {
		--- Filename for storing OAuth tokens in Neovim's data directory
		---@type string
		token_file = "gtask_tokens.json",
	},

	--- Markdown directory configuration
	--- Directory containing markdown files to parse for tasks
	markdown = {
		--- Directory path (must be absolute path or use ~)
		--- Default: ~/gtask.nvim if not configured
		---@type string
		dir = vim.fn.expand("~/gtask.nvim"),

		--- Patterns to ignore when scanning for markdown files
		--- Can be directory names (e.g., "archive") or specific .md file names (e.g., "draft.md")
		---@type string[]
		ignore_patterns = {},
	},

	--- Sync behavior configuration
	sync = {
		--- Keep completed tasks in markdown even after deleting from Google Tasks
		--- When true: completed tasks remain in markdown as historical records
		--- When false: completed tasks are deleted from markdown when deleted from Google
		---@type boolean
		keep_completed_in_markdown = true,
	},

	--- Logging verbosity level
	--- Controls which log messages are shown
	--- "error" (default): Only show errors
	--- "warn": Show warnings and errors
	--- "info": Show all messages including info, warnings, and errors
	---@type string
	verbosity = "error",
}

--- Current configuration
local config = vim.deepcopy(defaults)

--- Update configuration with user-provided options
---@param opts table|nil User configuration options
function M.setup(opts)
	opts = opts or {}

	-- Merge user config with defaults
	if opts.proxy_url then
		config.proxy.base_url = opts.proxy_url
	end

	if opts.markdown_dir then
		local path = opts.markdown_dir

		-- Validate that path is absolute (starts with / or ~)
		if not (path:match("^/") or path:match("^~")) then
			error("markdown_dir must be an absolute path (start with / or ~). Got: " .. path)
		end

		-- Expand ~ if present
		local expanded_path = vim.fn.expand(path)

		-- Ensure it's absolute after expansion
		if not expanded_path:match("^/") then
			error("markdown_dir must resolve to an absolute path. Got: " .. expanded_path)
		end

		-- Remove trailing slash for consistency
		config.markdown.dir = expanded_path:gsub("/$", "")
	end

	if opts.ignore_patterns then
		if type(opts.ignore_patterns) ~= "table" then
			error("ignore_patterns must be an array of strings")
		end
		config.markdown.ignore_patterns = opts.ignore_patterns
	end

	if opts.keep_completed_in_markdown ~= nil then
		if type(opts.keep_completed_in_markdown) ~= "boolean" then
			error("keep_completed_in_markdown must be a boolean")
		end
		config.sync.keep_completed_in_markdown = opts.keep_completed_in_markdown
	end

	if opts.verbosity then
		if type(opts.verbosity) ~= "string" then
			error("verbosity must be a string")
		end
		local valid_levels = { error = true, warn = true, info = true }
		if not valid_levels[opts.verbosity] then
			error("verbosity must be one of: 'error', 'warn', 'info'. Got: " .. opts.verbosity)
		end
		config.verbosity = opts.verbosity
	end
end

--- Get current configuration
---@return table Current configuration
function M.get()
	return config
end

--- Reset configuration to defaults (useful for testing)
function M.reset()
	config = vim.deepcopy(defaults)
end

-- Expose configuration fields for backward compatibility
M.scopes = config.scopes
M.proxy = config.proxy
M.storage = config.storage
M.markdown = config.markdown
M.sync = config.sync
M.verbosity = config.verbosity

return M
