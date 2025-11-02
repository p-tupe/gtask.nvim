---@class GtaskUtils
---Utility functions for gtask.nvim
local M = {}

--- Notify user with message, respecting verbosity settings
---@param msg string The message to display
---@param level number The vim.log.levels level (DEBUG, INFO, WARN, ERROR)
function M.notify(msg, level)
	local config = require("gtask.config")
	-- Use get() to access current config value, not the cached field
	local verbosity = config.get().verbosity

	-- Map verbosity level to minimum required log level
	local min_level = vim.log.levels.ERROR  -- Default: only errors

	if verbosity == "warn" then
		min_level = vim.log.levels.WARN
	elseif verbosity == "info" then
		min_level = vim.log.levels.INFO
	end

	-- Only show message if its level is >= minimum level
	if level >= min_level then
		vim.notify(msg, level)
	end
end

return M
