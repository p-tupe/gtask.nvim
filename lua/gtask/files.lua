---@class GtaskFiles
---Markdown file discovery and management
local M = {}

local config = require("gtask.config")

--- Get the configured markdown directory
---@return string|nil Directory path or nil if not configured
function M.get_markdown_dir()
	return config.markdown.dir
end

--- Check if markdown directory is configured and exists
---@return boolean, string|nil success, error_message
function M.validate_markdown_dir()
	local dir = M.get_markdown_dir()

	if not dir then
		return false, "Markdown directory not configured. Please set markdown_dir in setup()."
	end

	-- Check if directory exists
	local stat = vim.loop.fs_stat(dir)
	if not stat then
		return false, "Markdown directory does not exist: " .. dir
	end

	if stat.type ~= "directory" then
		return false, "Path is not a directory: " .. dir
	end

	return true, nil
end

--- Find all markdown files in the configured directory (recursively)
---@return string[] Array of absolute file paths
function M.find_markdown_files()
	local dir = M.get_markdown_dir()
	if not dir then
		vim.notify("Markdown directory not configured", vim.log.levels.ERROR)
		return {}
	end

	local files = {}

	--- Recursively scan directory for .md files
	---@param path string Directory path to scan
	local function scan_dir(path)
		local handle = vim.loop.fs_scandir(path)
		if not handle then
			return
		end

		while true do
			local name, type = vim.loop.fs_scandir_next(handle)
			if not name then
				break
			end

			local full_path = path .. "/" .. name

			if type == "directory" then
				-- Recursively scan subdirectories
				scan_dir(full_path)
			elseif type == "file" and name:match("%.md$") then
				-- Add markdown files
				table.insert(files, full_path)
			end
		end
	end

	scan_dir(dir)
	return files
end

--- Read a markdown file and return its lines
---@param file_path string Path to the markdown file
---@return string[]|nil, string|nil lines, error_message
function M.read_markdown_file(file_path)
	local file = io.open(file_path, "r")
	if not file then
		return nil, "Could not open file: " .. file_path
	end

	local lines = {}
	for line in file:lines() do
		table.insert(lines, line)
	end

	file:close()
	return lines, nil
end

--- Parse tasks from a markdown file
---@param file_path string Path to the markdown file
---@return table|nil tasks_with_metadata Table containing tasks, list name, and file metadata, or nil on error
function M.parse_markdown_file(file_path)
	local lines, err = M.read_markdown_file(file_path)
	if not lines then
		return nil, err
	end

	local parser = require("gtask.parser")
	local tasks = parser.parse_tasks(lines)
	local list_name = parser.extract_list_name(lines)

	-- Return tasks with file metadata
	return {
		file_path = file_path,
		file_name = vim.fn.fnamemodify(file_path, ":t"),
		list_name = list_name,  -- H1 heading used as task list name
		tasks = tasks,
	}
end

--- Parse tasks from all markdown files in the configured directory
---@return table[] Array of file task data (each containing file_path, file_name, and tasks)
function M.parse_all_markdown_files()
	local valid, err = M.validate_markdown_dir()
	if not valid then
		vim.notify(err, vim.log.levels.ERROR)
		return {}
	end

	local files = M.find_markdown_files()
	local all_data = {}

	for _, file_path in ipairs(files) do
		local data, parse_err = M.parse_markdown_file(file_path)
		if data and #data.tasks > 0 then
			table.insert(all_data, data)
		elseif parse_err then
			vim.notify("Error parsing " .. file_path .. ": " .. parse_err, vim.log.levels.WARN)
		end
	end

	return all_data
end

return M
