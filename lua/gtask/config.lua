---@class GtaskConfig
---Configuration module for Google Tasks API settings
local M = {}

--- OAuth 2.0 scopes required for Google Tasks API access
--- These scopes are used by the proxy backend service for authentication
---@type string[]
M.scopes = {
	"https://www.googleapis.com/auth/tasks",
}

--- Proxy backend configuration
--- The backend service handles all OAuth credentials securely
M.proxy = {
	--- Base URL for the OAuth proxy service
	--- Points to the deployed gtask auth proxy service
	---@type string
	base_url = "http://localhost:3000",
}

--- Token storage configuration
M.storage = {
	--- Filename for storing OAuth tokens in Neovim's data directory
	---@type string
	token_file = "gtask_tokens.json",
}

return M
