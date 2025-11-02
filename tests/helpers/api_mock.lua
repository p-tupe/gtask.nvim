---Mock API for testing
local M = {}

-- In-memory store for mock API data
M.store = {
	lists = {},
	tasks = {},
	next_list_id = 1,
	next_task_id = 1,
}

function M.reset()
	M.store = {
		lists = {},
		tasks = {},
		next_list_id = 1,
		next_task_id = 1,
	}
end

-- Mock API functions
function M.get_tasklists(callback)
	local lists = {}
	for _, list in pairs(M.store.lists) do
		table.insert(lists, list)
	end
	callback({ items = lists }, nil)
end

function M.find_list_by_name(name, callback)
	for _, list in pairs(M.store.lists) do
		if list.title == name then
			callback(list, nil)
			return
		end
	end
	callback(nil, nil)
end

function M.create_task_list(list_data, callback)
	local list_id = "list_" .. M.store.next_list_id
	M.store.next_list_id = M.store.next_list_id + 1

	local list = {
		id = list_id,
		title = list_data.title,
	}
	M.store.lists[list_id] = list
	callback(list, nil)
end

function M.get_or_create_list(name, callback)
	M.find_list_by_name(name, function(list, err)
		if list then
			callback(list, nil)
		else
			M.create_task_list({ title = name }, callback)
		end
	end)
end

function M.get_tasks(list_id, callback)
	local tasks = {}
	for _, task in pairs(M.store.tasks) do
		if task.list_id == list_id then
			table.insert(tasks, task)
		end
	end
	callback({ items = tasks }, nil)
end

function M.create_task(list_id, task_data, callback)
	local task_id = "task_" .. M.store.next_task_id
	M.store.next_task_id = M.store.next_task_id + 1

	local task = {
		id = task_id,
		list_id = list_id,
		title = task_data.title,
		notes = task_data.notes,
		status = task_data.status or "needsAction",
		due = task_data.due,
		parent = task_data.parent,
	}
	M.store.tasks[task_id] = task
	callback(task, nil)
end

function M.create_task_with_parent(list_id, task_data, parent_id, previous_id, callback)
	local task_id = "task_" .. M.store.next_task_id
	M.store.next_task_id = M.store.next_task_id + 1

	local task = {
		id = task_id,
		list_id = list_id,
		title = task_data.title,
		notes = task_data.notes,
		status = task_data.status or "needsAction",
		due = task_data.due,
		parent = parent_id,
	}
	M.store.tasks[task_id] = task
	callback(task, nil)
end

function M.update_task(list_id, task_id, task_data, callback)
	local task = M.store.tasks[task_id]
	if not task then
		callback(nil, "Task not found")
		return
	end

	task.title = task_data.title or task.title
	task.notes = task_data.notes
	task.status = task_data.status or task.status
	task.due = task_data.due

	callback(task, nil)
end

function M.delete_task(list_id, task_id, callback)
	M.store.tasks[task_id] = nil
	callback(true, nil)
end

-- Helper to seed data for testing
function M.seed_list(name)
	local list_id = "list_" .. M.store.next_list_id
	M.store.next_list_id = M.store.next_list_id + 1

	local list = {
		id = list_id,
		title = name,
	}
	M.store.lists[list_id] = list
	return list
end

function M.seed_task(list_id, title, options)
	options = options or {}
	local task_id = "task_" .. M.store.next_task_id
	M.store.next_task_id = M.store.next_task_id + 1

	local task = {
		id = task_id,
		list_id = list_id,
		title = title,
		notes = options.notes,
		status = options.status or "needsAction",
		due = options.due,
		parent = options.parent,
	}
	M.store.tasks[task_id] = task
	return task
end

return M
