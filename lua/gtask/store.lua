---@class GtaskStore
---Token storage module for persisting OAuth tokens to disk
local M = {}

local config = require("gtask.config")

--- Get the path where tokens are stored
--- Uses Neovim's data directory for cross-platform compatibility
---@return string # Absolute path to the token file
local function get_token_path()
	return vim.fn.stdpath("data") .. "/" .. config.storage.token_file
end

--- Save OAuth tokens to persistent storage
--- Stores tokens as JSON in Neovim's data directory
---@param tokens table Token object containing access_token, refresh_token, etc.
---@return boolean # True if save was successful, false otherwise
function M.save_tokens(tokens)
	if not tokens then
		vim.notify("Cannot save nil tokens", vim.log.levels.ERROR)
		return false
	end

	local path = get_token_path()
	local file = io.open(path, "w")
	if not file then
		vim.notify("Failed to open token file for writing: " .. path, vim.log.levels.ERROR)
		return false
	end

	local success, encoded = pcall(vim.fn.json_encode, tokens)
	if not success then
		vim.notify("Failed to encode tokens as JSON", vim.log.levels.ERROR)
		file:close()
		return false
	end

	file:write(encoded)
	file:close()
	return true
end

--- Load OAuth tokens from persistent storage
--- Returns nil if no tokens are found (not an error condition)
---@return table|nil # Token object or nil if no tokens found
function M.load_tokens()
	local path = get_token_path()
	local file = io.open(path, "r")
	if not file then
		return nil -- No tokens found, not an error
	end

	local content = file:read("*a")
	file:close()

	if not content or content == "" then
		return nil
	end

	local success, tokens = pcall(vim.fn.json_decode, content)
	if not success then
		vim.notify("Failed to decode stored tokens", vim.log.levels.WARN)
		return nil
	end

	return tokens
end

--- Check if tokens exist in storage
---@return boolean # True if tokens are stored, false otherwise
function M.has_tokens()
	return M.load_tokens() ~= nil
end

--- Clear stored tokens
--- Removes the token file from disk
---@return boolean # True if successful, false otherwise
function M.clear_tokens()
	local path = get_token_path()
	local success, err = os.remove(path)
	if not success then
		vim.notify("Failed to clear tokens: " .. (err or "unknown error"), vim.log.levels.WARN)
		return false
	end
	return true
end

return M
