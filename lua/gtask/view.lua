local M = {}

---Builds a hierarchical tree from a flat list of tasks.
---@param tasks table The flat list of tasks from the API.
---@return table tasks_by_parent A map of parent_id -> list of child tasks.
---@return table top_level_tasks A list of tasks that have no parent.
local function build_task_tree(tasks)
	local tasks_by_id = {}
	for _, task in ipairs(tasks) do
		tasks_by_id[task.id] = task
	end

	local tasks_by_parent = {}
	local top_level_tasks = {}

	for _, task in ipairs(tasks) do
		if task.parent and tasks_by_id[task.parent] then
			if not tasks_by_parent[task.parent] then
				tasks_by_parent[task.parent] = {}
			end
			table.insert(tasks_by_parent[task.parent], task)
		else
			table.insert(top_level_tasks, task)
		end
	end

	return tasks_by_parent, top_level_tasks
end

local function sort_tasks(tasks)
	table.sort(tasks, function(a, b)
		-- Tasks without a due date are considered "later" than tasks with one.
		if not a.due then
			return false
		end
		if not b.due then
			return true
		end
		return a.due < b.due
	end)
end

local function render_to_lines(tasks_by_parent, top_level_tasks)
	local lines = {}
	local function render_task(task, indent_level)
		local indent = string.rep("  ", indent_level)
		local checkbox = task.status == "completed" and "[x]" or "[ ]"

		local task_line = string.format("%s- %s %s", indent, checkbox, task.title)
		if task.due then
			-- The due date is a timestamp, so we'll just take the date part.
			task_line = task_line .. " (due: " .. string.sub(task.due, 1, 10) .. ")"
		end
		table.insert(lines, task_line)

		if task.notes then
			-- Add the description indented under the task.
			local notes_indent = string.rep("  ", indent_level + 1)
			for s in string.gmatch(task.notes, "([^\n]*)") do
				-- Don't print empty lines from the description
				if s and #s > 0 then
					table.insert(lines, notes_indent .. "> " .. s)
				end
			end
		end

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

---Processes a flat list of tasks and renders them into a sorted, hierarchical view.
---@param tasks table The flat list of tasks from the API.
---@return table A list of strings, where each string is a line in the final view.
function M.render_task_view(tasks)
	if not tasks or #tasks == 0 then
		return { "No tasks found." }
	end
	local tasks_by_parent, top_level_tasks = build_task_tree(tasks)
	return render_to_lines(tasks_by_parent, top_level_tasks)
end

return M
