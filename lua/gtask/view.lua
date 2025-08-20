---@class GtaskView
---Task rendering module for displaying Google Tasks in hierarchical format
local M = {}

--- Build a hierarchical tree from a flat list of tasks
--- Organizes tasks into parent-child relationships based on task.parent field
---@param tasks table[] The flat list of tasks from the Google Tasks API
---@return table<string, table[]> tasks_by_parent A map of parent_id -> list of child tasks
---@return table[] top_level_tasks A list of tasks that have no parent
local function build_task_tree(tasks)
	if not tasks or type(tasks) ~= "table" then
		return {}, {}
	end

	local tasks_by_id = {}
	for _, task in ipairs(tasks) do
		if task and task.id then
			tasks_by_id[task.id] = task
		end
	end

	local tasks_by_parent = {}
	local top_level_tasks = {}

	for _, task in ipairs(tasks) do
		if not task or not task.id then
			goto continue -- Skip invalid tasks
		end

		if task.parent and tasks_by_id[task.parent] then
			-- This is a subtask
			if not tasks_by_parent[task.parent] then
				tasks_by_parent[task.parent] = {}
			end
			table.insert(tasks_by_parent[task.parent], task)
		else
			-- This is a top-level task
			table.insert(top_level_tasks, task)
		end

		::continue::
	end

	return tasks_by_parent, top_level_tasks
end

--- Sort tasks by due date, with tasks without due dates appearing last
--- Tasks with earlier due dates appear first in the list
---@param tasks table[] Array of tasks to sort in-place
local function sort_tasks(tasks)
	if not tasks or type(tasks) ~= "table" then
		return
	end

	table.sort(tasks, function(a, b)
		-- Safety checks
		if not a or not b then
			return false
		end

		-- Tasks without a due date are considered "later" than tasks with one
		if not a.due or a.due == "" then
			return false
		end
		if not b.due or b.due == "" then
			return true
		end

		-- Compare due dates lexicographically (ISO format sorts naturally)
		return a.due < b.due
	end)
end

--- Render tasks to an array of formatted strings
--- Creates markdown-style task list with proper indentation and hierarchy
---@param tasks_by_parent table<string, table[]> Map of parent tasks to their children
---@param top_level_tasks table[] Array of top-level tasks
---@return string[] Array of formatted task lines
local function render_to_lines(tasks_by_parent, top_level_tasks)
	local lines = {}
	--- Render a single task and its subtasks recursively
	--- Formats the task with proper indentation, checkbox, and description
	---@param task table The task to render
	---@param indent_level integer The indentation level (0 = top level)
	local function render_task(task, indent_level)
		if not task or not task.title then
			return -- Skip invalid tasks
		end

		local indent = string.rep("  ", indent_level)
		local checkbox = (task.status == "completed") and "[x]" or "[ ]"

		-- Format the main task line
		local task_line = string.format("%s- %s %s", indent, checkbox, task.title)

		-- Add due date if present
		if task.due and task.due ~= "" then
			-- Extract just the date part from ISO timestamp
			local date_part = task.due:match("(%d%d%d%d%-%d%d%-%d%d)")
			if date_part then
				task_line = task_line .. " (due: " .. date_part .. ")"
			end
		end
		table.insert(lines, task_line)

		-- Add task description/notes if present
		if task.notes and task.notes ~= "" then
			local notes_indent = string.rep("  ", indent_level + 1)
			-- Split notes by newlines and add each non-empty line
			for note_line in task.notes:gmatch("([^\n]*)") do
				if note_line and #note_line > 0 then
					table.insert(lines, notes_indent .. note_line)
				end
			end
		end

		-- Render subtasks recursively
		if tasks_by_parent[task.id] then
			local subtasks = tasks_by_parent[task.id]
			sort_tasks(subtasks)
			for _, subtask in ipairs(subtasks) do
				render_task(subtask, indent_level + 1)
			end
		end
	end

	sort_tasks(top_level_tasks)
	for _, task in ipairs(top_level_tasks) do
		render_task(task, 0)
	end

	return lines
end

--- Process a flat list of tasks and render them into a sorted, hierarchical view
--- This is the main entry point for rendering Google Tasks in the plugin's format
---@param tasks table[]|nil The flat list of tasks from the Google Tasks API
---@return string[] Array of formatted lines ready for display in a buffer
function M.render_task_view(tasks)
	if not tasks or type(tasks) ~= "table" or #tasks == 0 then
		return { "No tasks found." }
	end

	local tasks_by_parent, top_level_tasks = build_task_tree(tasks)
	return render_to_lines(tasks_by_parent, top_level_tasks)
end

return M
