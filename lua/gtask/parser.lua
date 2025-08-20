local M = {}

---@class Task
---@field title string The task title
---@field completed boolean Whether the task is completed
---@field description string|nil The task description (from following indented lines)
---@field line_number integer The line number where this task appears
---@field indent_level integer The indentation level (0 for top-level tasks)
---@field parent_index integer|nil Index of parent task if this is a subtask

---Parses markdown lines to extract tasks with hierarchy and descriptions
---@param lines string[] Array of markdown lines
---@return Task[] Array of parsed tasks
function M.parse_tasks(lines)
	local tasks = {}
	local i = 1

	while i <= #lines do
		local line = lines[i]
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

	return tasks
end

---Parses a single task starting at the given line index
---@param lines string[] Array of markdown lines
---@param start_index integer Line index to start parsing from
---@return Task|nil, integer Task object and number of lines consumed
function M.parse_single_task(lines, start_index)
	local line = lines[start_index]
	local indent, checkbox, title = M.parse_task_line(line)

	if not title then
		return nil, 0
	end

	local task = {
		title = title,
		completed = checkbox == "x",
		line_number = start_index,
		indent_level = indent,
		description = nil,
		parent_index = nil,
	}

	-- Look for description lines (indented lines that are not tasks)
	local consumed_lines = 1
	local description_parts = {}

	for j = start_index + 1, #lines do
		local desc_line = lines[j]

		-- Skip empty lines
		if desc_line:match("^%s*$") then
			break
		end

		-- Check if this is another task - if so, stop looking for description
		local desc_indent, desc_checkbox, desc_title = M.parse_task_line(desc_line)
		if desc_title then
			break
		end

		-- Check if this is a description line (indented more than the task)
		local line_indent = M.get_line_indent(desc_line)
		if line_indent > indent then
			-- Extract the content after the indentation
			local content = desc_line:match("^%s*(.+)$")
			if content then
				table.insert(description_parts, content)
				consumed_lines = consumed_lines + 1
			else
				break
			end
		else
			break
		end
	end

	if #description_parts > 0 then
		task.description = table.concat(description_parts, "\n")
	end

	return task, consumed_lines
end

---Parses a task line to extract indentation, checkbox state, and title
---@param line string The line to parse
---@return integer, string|nil, string|nil indent_level, checkbox_state, title
function M.parse_task_line(line)
	-- Match pattern: optional whitespace, -, space, [checkbox], space, title
	local indent_str, checkbox, title = line:match("^(%s*)%-%s*%[([%sx]?)%]%s*(.+)$")

	if not title then
		return 0, nil, nil
	end

	-- Calculate indentation level (assuming 2 spaces per level)
	local indent_level = math.floor(#indent_str / 2)

	return indent_level, checkbox, title
end

---Gets the indentation level of a line
---@param line string The line to analyze
---@return integer The indentation level
function M.get_line_indent(line)
	local indent_str = line:match("^(%s*)")
	return math.floor(#indent_str / 2)
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

---Converts tasks back to markdown format
---@param tasks Task[] Array of tasks to convert
---@return string[] Array of markdown lines
function M.tasks_to_markdown(tasks)
	local lines = {}

	for _, task in ipairs(tasks) do
		-- Create task line
		local indent = string.rep("  ", task.indent_level)
		local checkbox = task.completed and "x" or " "
		local task_line = string.format("%s- [%s] %s", indent, checkbox, task.title)
		table.insert(lines, task_line)

		-- Add description lines if present
		if task.description then
			local desc_indent = string.rep("  ", task.indent_level + 1)
			for desc_line in task.description:gmatch("[^\n]+") do
				table.insert(lines, desc_indent .. desc_line)
			end
		end
	end

	return lines
end

return M
