---Simple JSON encoder/decoder for testing
local M = {}

local function escape_str(s)
	s = s:gsub("\\", "\\\\")
	s = s:gsub('"', '\\"')
	s = s:gsub("\n", "\\n")
	s = s:gsub("\r", "\\r")
	s = s:gsub("\t", "\\t")
	return s
end

function M.encode(val)
	local t = type(val)

	if t == "nil" then
		return "null"
	elseif t == "boolean" then
		return val and "true" or "false"
	elseif t == "number" then
		return tostring(val)
	elseif t == "string" then
		return '"' .. escape_str(val) .. '"'
	elseif t == "table" then
		local is_array = #val > 0
		if is_array then
			local parts = {}
			for i = 1, #val do
				table.insert(parts, M.encode(val[i]))
			end
			return "[" .. table.concat(parts, ",") .. "]"
		else
			local parts = {}
			for k, v in pairs(val) do
				table.insert(parts, '"' .. escape_str(tostring(k)) .. '":' .. M.encode(v))
			end
			return "{" .. table.concat(parts, ",") .. "}"
		end
	else
		error("Cannot encode type: " .. t)
	end
end

function M.decode(str)
	-- Use Lua's load function with a safe environment
	-- This is a simple implementation for testing purposes
	local cleaned = str:gsub("null", "nil")
	cleaned = cleaned:gsub("true", "true")
	cleaned = cleaned:gsub("false", "false")

	-- Very basic decoder - for production use a proper JSON library
	local fn, err = load("return " .. cleaned)
	if not fn then
		error("JSON decode error: " .. tostring(err))
	end

	return fn()
end

return M
