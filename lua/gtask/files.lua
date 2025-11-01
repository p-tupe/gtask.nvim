---@class GtaskFiles
---Markdown file discovery and management
local M = {}

local config = require("gtask.config")

--- Get the configured markdown directory
---@return string|nil Directory path or nil if not configured
function M.get_markdown_dir()
	return config.markdown.dir
end

--- Check if markdown directory is configured and exists, creating it if necessary
---@return boolean success True if valid, false otherwise
---@return string|nil error_message Error message if validation failed
function M.validate_markdown_dir()
	local dir = M.get_markdown_dir()

	if not dir then
		return false, "Markdown directory not configured. Please set markdown_dir in setup()."
	end

	-- Check if directory exists
	local stat = vim.loop.fs_stat(dir)
	if not stat then
		-- Directory doesn't exist, try to create it
		local success, err = pcall(vim.fn.mkdir, dir, "p")
		if not success then
			return false, "Failed to create markdown directory: " .. dir .. " (" .. tostring(err) .. ")"
		end

		vim.notify("Created markdown directory: " .. dir, vim.log.levels.INFO)
		return true, nil
	end

	if stat.type ~= "directory" then
		return false, "Path exists but is not a directory: " .. dir
	end

	return true, nil
end

--- Check if a path should be ignored based on ignore patterns
---@param name string The file or directory name (not full path)
---@param is_directory boolean Whether this is a directory
---@return boolean True if should be ignored
local function should_ignore(name, is_directory)
	local ignore_patterns = config.markdown.ignore_patterns or {}

	for _, pattern in ipairs(ignore_patterns) do
		if is_directory then
			-- For directories, match against directory names
			if name == pattern then
				return true
			end
		else
			-- For files, only match .md files against the pattern
			if name:match("%.md$") and name == pattern then
				return true
			end
		end
	end

	return false
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

			-- Check if this should be ignored
			if should_ignore(name, type == "directory") then
				goto continue
			end

			local full_path = path .. "/" .. name

			if type == "directory" then
				-- Recursively scan subdirectories
				scan_dir(full_path)
			elseif type == "file" and name:match("%.md$") then
				-- Add markdown files (only .md files)
				table.insert(files, full_path)
			end

			::continue::
		end
	end

	scan_dir(dir)
	return files
end

--- Read a markdown file and return its lines
---@param file_path string Path to the markdown file
---@return string[]|nil lines Array of lines from the file, or nil on error
---@return string|nil error_message Error message if read failed
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
---@return string|nil error_message Error message if parsing failed
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
		list_name = list_name, -- H1 heading used as task list name
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
