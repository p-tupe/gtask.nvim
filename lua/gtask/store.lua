local M = {}

local function get_token_path()
	return vim.fn.stdpath("data") .. "/gtask_tokens.json"
end

---@param tokens table
function M.save_tokens(tokens)
	local path = get_token_path()
	local file = io.open(path, "w")
	if not file then
		vim.notify("Failed to open token file for writing: " .. path, vim.log.levels.ERROR)
		return
	end
	file:write(vim.fn.json_encode(tokens))
	file:close()
end

---@return table|nil
function M.load_tokens()
	local path = get_token_path()
	local file = io.open(path, "r")
	if not file then
		return nil -- No tokens found, not an error
	end
	local content = file:read("*a")
	file:close()
	return vim.fn.json_decode(content)
end

return M
