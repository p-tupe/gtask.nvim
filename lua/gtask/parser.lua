local M = {}

---Extracts the H1 heading from markdown lines (used as task list name)
---@param lines string[] Array of markdown lines
---@return string|nil The H1 heading text or nil if not found
function M.extract_list_name(lines)
	for _, line in ipairs(lines) do
		-- Match H1 heading: # Text
		local heading = line:match("^#%s+(.+)$")
		if heading then
			return heading
		end
	end
	return nil
end

---@class Task
---@field title string The task title
---@field completed boolean Whether the task is completed
---@field description string|nil The task description (from following indented lines)
---@field due_date string|nil The due date in RFC3339 format (parsed from markdown)
---@field line_number integer The line number where this task appears
---@field indent_level integer The indentation level (0 for top-level tasks)
---@field parent_index integer|nil Index of parent task if this is a subtask
---@field position_path string|nil Tree position path like "[0]" or "[0].[1]"

---Parses markdown lines to extract tasks with hierarchy and descriptions
---@param lines string[] Array of markdown lines
---@return Task[] Array of parsed tasks
function M.parse_tasks(lines)
	local tasks = {}
	local i = 1

	while i <= #lines do
		local task, consumed_lines = M.parse_single_task(lines, i)

		if task then
			table.insert(tasks, task)
			i = i + consumed_lines
		else
			i = i + 1
		end
	end

	-- Build parent-child relationships
	M.build_hierarchy(tasks)

	-- Build position paths for stable task identification
	M.build_position_paths(tasks)

	return tasks
end

---Parses a single task starting at the given line index
---@param lines string[] Array of markdown lines
---@param start_index integer Line index to start parsing from
---@return Task|nil, integer Task object and number of lines consumed
function M.parse_single_task(lines, start_index)
	local line = lines[start_index]
	local indent, checkbox, title, due_date = M.parse_task_line(line)

	if not title then
		return nil, 0
	end

	-- Calculate the minimum indentation required for description (same as task)
	local task_indent_chars = indent * 2

	local task = {
		title = title,
		completed = checkbox == "x",
		due_date = due_date,
		line_number = start_index,
		indent_level = indent,
		description = nil,
		parent_index = nil,
	}

	-- Look for description lines (non-task, non-empty lines at least as indented as the task)
	-- Allow one empty line between task and description
	local consumed_lines = 1
	local description_parts = {}
	local skipped_initial_empty = false

	for j = start_index + 1, #lines do
		local desc_line = lines[j]

		-- Check if this is another task - if so, stop looking for description
		local _, _, desc_title, _ = M.parse_task_line(desc_line)
		if desc_title then
			break
		end

		-- Handle empty lines
		if desc_line:match("^%s*$") then
			-- Allow one empty line before description starts
			if #description_parts == 0 and not skipped_initial_empty then
				skipped_initial_empty = true
				consumed_lines = consumed_lines + 1
			else
				-- Empty line after description has started - stop here
				break
			end
		else
			-- Check if line is indented at least as much as the task
			local line_indent = desc_line:match("^(%s*)")
			if #line_indent >= task_indent_chars then
				-- Line is properly indented, include it in description
				local content = desc_line:match("^%s*(.+)%s*$")
				if content then
					table.insert(description_parts, content)
					consumed_lines = consumed_lines + 1
				end
			else
				-- Line is not indented enough, stop here
				break
			end
		end
	end

	if #description_parts > 0 then
		task.description = table.concat(description_parts, "\n")
	end

	return task, consumed_lines
end

---Parses a task line to extract indentation, checkbox state, title, and due date
---@param line string The line to parse
---@return integer, string|nil, string|nil, string|nil indent_level, checkbox_state, title, due_date
function M.parse_task_line(line)
	-- Match pattern: optional whitespace, -, space, [checkbox], space, title [| due_date]
	local indent_str, checkbox, content = line:match("^(%s*)%-%s*%[([%sx]?)%]%s*(.+)$")

	if not content then
		return 0, nil, nil, nil
	end

	-- Extract title and optional due date (format: "Title | YYYY-MM-DD" or "Title | YYYY-MM-DD HH:MM")
	local title, due_date_str, time_str = content:match("^(.-)%s*|%s*(%d%d%d%d%-%d%d%-%d%d)%s*(%d%d:%d%d)%s*$")
	if not title then
		-- Try without time
		title, due_date_str = content:match("^(.-)%s*|%s*(%d%d%d%d%-%d%d%-%d%d)%s*$")
	end
	if not title then
		-- No due date, entire content is title
		title = content
		due_date_str = nil
		time_str = nil
	end

	-- Calculate indentation level (assuming 2 spaces per level)
	local indent_level = math.floor(#indent_str / 2)

	-- Convert due date to RFC3339 format if present (Google Tasks format)
	local due_date = nil
	if due_date_str then
		-- Google Tasks expects RFC3339 format: "YYYY-MM-DDTHH:MM:SS.sssZ"
		if time_str then
			-- With time: use provided time in UTC
			due_date = due_date_str .. "T" .. time_str .. ":00.000Z"
		else
			-- Date-only: use midnight UTC
			due_date = due_date_str .. "T00:00:00.000Z"
		end
	end

	return indent_level, checkbox, title, due_date
end

---Builds parent-child relationships for tasks based on indentation
---@param tasks Task[] Array of tasks to process
function M.build_hierarchy(tasks)
	local parent_stack = {} -- Stack of potential parents at each indent level

	for i, task in ipairs(tasks) do
		-- Clear stack of parents that are at same or deeper level
		while #parent_stack > 0 and parent_stack[#parent_stack].indent_level >= task.indent_level do
			table.remove(parent_stack)
		end

		-- If we have a potential parent, link to it
		if #parent_stack > 0 then
			task.parent_index = parent_stack[#parent_stack].index
		end

		-- Add this task to the stack as a potential parent
		table.insert(parent_stack, { indent_level = task.indent_level, index = i })
	end
end

---Builds tree position paths for all tasks based on parent_index relationships
---Converts hierarchical parent-child relationships into stable position strings
---like "[0]", "[0].[1]", "[0].[1].[2]" that are resilient to line number changes
---@param tasks Task[] Array of tasks with parent_index set
function M.build_position_paths(tasks)
	-- Track child counts per parent to assign positions
	local child_counts = {} -- Maps parent_index (or "top") to next child position

	for i, task in ipairs(tasks) do
		if task.parent_index then
			-- This is a child task
			local parent = tasks[task.parent_index]
			if not parent or not parent.position_path then
				-- Parent should have been processed first (array order guarantees this)
				error("Parent task position not set for task: " .. task.title)
			end

			-- Get child position (how many children this parent already has)
			local child_pos = child_counts[task.parent_index] or 0
			child_counts[task.parent_index] = child_pos + 1

			-- Build position path: parent's path + "." + child position
			task.position_path = parent.position_path .. ".[" .. child_pos .. "]"
		else
			-- Top-level task
			local top_level_pos = child_counts["top"] or 0
			child_counts["top"] = top_level_pos + 1

			task.position_path = "[" .. top_level_pos .. "]"
		end
	end
end

return M
