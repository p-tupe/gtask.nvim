---Mock vim API for testing
local M = {}

-- Helper function for deep copy
local function deepcopy(orig)
	local orig_type = type(orig)
	local copy
	if orig_type == "table" then
		copy = {}
		for orig_key, orig_value in next, orig, nil do
			copy[deepcopy(orig_key)] = deepcopy(orig_value)
		end
		setmetatable(copy, deepcopy(getmetatable(orig)))
	else -- number, string, boolean, etc
		copy = orig
	end
	return copy
end

-- Mock vim global
_G.vim = {
	deepcopy = deepcopy,
	fn = {
		stdpath = function(what)
			if what == "data" then
				return "/tmp/gtask_test_data"
			end
			return "/tmp/gtask_test"
		end,
		json_encode = function(data)
			-- Simple JSON encoder for testing
			return require("tests.helpers.json").encode(data)
		end,
		json_decode = function(str)
			-- Simple JSON decoder for testing
			return require("tests.helpers.json").decode(str)
		end,
		expand = function(path)
			-- Simple path expansion
			if path:match("^~") then
				return path:gsub("^~", os.getenv("HOME") or "/home/user")
			end
			return path
		end,
	},
	log = {
		levels = {
			DEBUG = 0,
			INFO = 1,
			WARN = 2,
			ERROR = 3,
		},
	},
	notify = function(msg, level)
		-- Store notifications for testing
		M.notifications = M.notifications or {}
		table.insert(M.notifications, { msg = msg, level = level })
	end,
	loop = {
		fs_scandir = function(path)
			-- Mock filesystem scanner
			return nil, "ENOENT"
		end,
		fs_scandir_next = function()
			return nil
		end,
	},
}

-- Helper to reset mocks
function M.reset()
	M.notifications = {}
	-- Reset stdpath to default
	_G.vim.fn.stdpath = function(what)
		if what == "data" then
			return "/tmp/gtask_test_data"
		end
		return "/tmp/gtask_test"
	end
end

-- Helper to get notifications
function M.get_notifications()
	return M.notifications or {}
end

-- Helper to clear notifications
function M.clear_notifications()
	M.notifications = {}
end

-- Helper to find notification by pattern
function M.find_notification(pattern)
	for _, notif in ipairs(M.notifications or {}) do
		if notif.msg:match(pattern) then
			return notif
		end
	end
	return nil
end

return M
