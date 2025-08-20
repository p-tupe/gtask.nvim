local M = {}

local api = require("gtask.api")
local parser = require("gtask.parser")

---@class SyncState
---@field markdown_tasks Task[] Tasks parsed from markdown
---@field google_tasks table[] Tasks from Google Tasks API
---@field task_list_id string Google Tasks list ID to sync with

---Syncs markdown tasks from current buffer with Google Tasks
---@param task_list_id string Google Tasks list ID
---@param callback function Callback function called when sync is complete
function M.sync_buffer_with_google(task_list_id, callback)
	-- Get current buffer content
	local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
	local markdown_tasks = parser.parse_tasks(lines)

	-- Fetch current Google Tasks
	api.get_tasks(task_list_id, function(google_response, err)
		if err then
			vim.notify("Error fetching Google Tasks: " .. err, vim.log.levels.ERROR)
			if callback then
				callback(false)
			end
			return
		end

		local google_tasks = google_response.items or {}

		-- Perform the sync
		local sync_state = {
			markdown_tasks = markdown_tasks,
			google_tasks = google_tasks,
			task_list_id = task_list_id,
		}

		M.perform_sync(sync_state, callback)
	end)
end

---Performs the actual sync operation
---@param sync_state SyncState State containing tasks to sync
---@param callback function Callback when sync is complete
function M.perform_sync(sync_state, callback)
	-- For now, implement a simple one-way sync: markdown -> Google Tasks
	-- This pushes new markdown tasks to Google and updates existing ones

	local operations = M.plan_sync_operations(sync_state)
	M.execute_sync_operations(operations, sync_state.task_list_id, callback)
end

---Plans what sync operations need to be performed
---@param sync_state SyncState State containing tasks to sync
---@return table[] Array of sync operations to execute
function M.plan_sync_operations(sync_state)
	local operations = {}
	local google_tasks_by_title = {}

	-- Index Google tasks by title for quick lookup
	for _, gtask in ipairs(sync_state.google_tasks) do
		google_tasks_by_title[gtask.title] = gtask
	end

	-- Process markdown tasks
	for _, mdtask in ipairs(sync_state.markdown_tasks) do
		local existing_gtask = google_tasks_by_title[mdtask.title]

		if existing_gtask then
			-- Task exists - check if update is needed
			if M.task_needs_update(mdtask, existing_gtask) then
				table.insert(operations, {
					type = "update",
					markdown_task = mdtask,
					google_task = existing_gtask,
				})
			end
		else
			-- New task - needs to be created
			table.insert(operations, {
				type = "create",
				markdown_task = mdtask,
			})
		end
	end

	return operations
end

---Checks if a Google task needs to be updated based on markdown task
---@param mdtask Task Markdown task
---@param gtask table Google task
---@return boolean True if update is needed
function M.task_needs_update(mdtask, gtask)
	-- Check completion status
	local md_completed = mdtask.completed
	local g_completed = gtask.status == "completed"
	if md_completed ~= g_completed then
		return true
	end

	-- Check description
	local md_desc = mdtask.description or ""
	local g_desc = gtask.notes or ""
	if md_desc ~= g_desc then
		return true
	end

	return false
end

---Executes the planned sync operations
---@param operations table[] Operations to execute
---@param task_list_id string Google Tasks list ID
---@param callback function Callback when all operations complete
function M.execute_sync_operations(operations, task_list_id, callback)
	local completed_operations = 0
	local total_operations = #operations
	local errors = {}

	if total_operations == 0 then
		vim.notify("No sync operations needed")
		if callback then
			callback(true)
		end
		return
	end

	local function operation_complete(success, error_msg)
		completed_operations = completed_operations + 1

		if not success and error_msg then
			table.insert(errors, error_msg)
		end

		if completed_operations >= total_operations then
			-- All operations complete
			if #errors > 0 then
				vim.notify("Sync completed with errors: " .. table.concat(errors, ", "), vim.log.levels.WARN)
				if callback then
					callback(false)
				end
			else
				vim.notify("Sync completed successfully")
				if callback then
					callback(true)
				end
			end
		end
	end

	-- Execute each operation
	for _, operation in ipairs(operations) do
		if operation.type == "create" then
			M.create_google_task(operation.markdown_task, task_list_id, operation_complete)
		elseif operation.type == "update" then
			M.update_google_task(operation.markdown_task, operation.google_task, task_list_id, operation_complete)
		end
	end
end

---Creates a new Google task from a markdown task
---@param mdtask Task Markdown task to create
---@param task_list_id string Google Tasks list ID
---@param callback function Callback when operation completes
function M.create_google_task(mdtask, task_list_id, callback)
	local google_task = {
		title = mdtask.title,
		status = mdtask.completed and "completed" or "needsAction",
	}

	if mdtask.description then
		google_task.notes = mdtask.description
	end

	-- TODO: Handle parent-child relationships
	-- For now, create all tasks as top-level

	api.create_task(task_list_id, google_task, function(response, err)
		if err then
			callback(false, "Failed to create task: " .. mdtask.title)
		else
			callback(true)
		end
	end)
end

---Updates an existing Google task from a markdown task
---@param mdtask Task Markdown task with new data
---@param gtask table Existing Google task to update
---@param task_list_id string Google Tasks list ID
---@param callback function Callback when operation completes
function M.update_google_task(mdtask, gtask, task_list_id, callback)
	local updated_task = {
		title = mdtask.title,
		status = mdtask.completed and "completed" or "needsAction",
	}

	if mdtask.description then
		updated_task.notes = mdtask.description
	end

	api.update_task(task_list_id, gtask.id, updated_task, function(response, err)
		if err then
			callback(false, "Failed to update task: " .. mdtask.title)
		else
			callback(true)
		end
	end)
end

return M
