local M = {}

local api = require("gtask.api")
local parser = require("gtask.parser")
local files = require("gtask.files")

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

	if mdtask.due_date then
		google_task.due = mdtask.due_date
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

	if mdtask.due_date then
		updated_task.due = mdtask.due_date
	end

	api.update_task(task_list_id, gtask.id, updated_task, function(response, err)
		if err then
			callback(false, "Failed to update task: " .. mdtask.title)
		else
			callback(true)
		end
	end)
end

---Performs 2-way sync between markdown and Google Tasks
---@param sync_state table State containing tasks and configuration
---@param callback function Callback when sync is complete
function M.perform_twoway_sync(sync_state, callback)
	local markdown_tasks = sync_state.markdown_tasks
	local google_tasks = sync_state.google_tasks
	local task_list_id = sync_state.task_list_id
	local markdown_dir = sync_state.markdown_dir
	local list_name = sync_state.list_name

	-- Index tasks by title for comparison
	local md_by_title = {}
	for _, task in ipairs(markdown_tasks) do
		md_by_title[task.title] = task
	end

	local google_by_title = {}
	for _, task in ipairs(google_tasks) do
		google_by_title[task.title] = task
	end

	local operations = {
		to_google = {},  -- Tasks to create/update in Google
		to_markdown = {}, -- Tasks to create in markdown
	}

	-- Find tasks only in markdown or needing update in Google
	for _, mdtask in ipairs(markdown_tasks) do
		local gtask = google_by_title[mdtask.title]
		if not gtask then
			-- Task only in markdown -> create in Google
			table.insert(operations.to_google, { type = "create", markdown_task = mdtask })
		elseif M.task_needs_update(mdtask, gtask) then
			-- Task exists but needs update in Google
			table.insert(operations.to_google, { type = "update", markdown_task = mdtask, google_task = gtask })
		end
	end

	-- Find tasks only in Google (need to be added to markdown)
	for _, gtask in ipairs(google_tasks) do
		if not md_by_title[gtask.title] then
			-- Task only in Google -> create in markdown
			table.insert(operations.to_markdown, gtask)
		end
	end

	-- Report sync plan
	vim.notify(string.format(
		"Sync plan: %d to Google, %d to markdown",
		#operations.to_google,
		#operations.to_markdown
	))

	-- Execute sync operations
	M.execute_twoway_sync(operations, task_list_id, markdown_dir, list_name, callback)
end

---Executes 2-way sync operations
---@param operations table Operations to perform
---@param task_list_id string Google Tasks list ID
---@param markdown_dir string Markdown directory path
---@param list_name string Name of the task list
---@param callback function Callback when complete
function M.execute_twoway_sync(operations, task_list_id, markdown_dir, list_name, callback)
	-- Count total operations: one per Google operation + one for markdown write (if any)
	local total_ops = #operations.to_google
	if #operations.to_markdown > 0 then
		total_ops = total_ops + 1
	end

	if total_ops == 0 then
		vim.notify("All tasks are in sync!")
		if callback then
			callback(true)
		end
		return
	end

	local completed = 0
	local errors = {}

	local function op_complete(success, err_msg)
		completed = completed + 1
		if not success and err_msg then
			table.insert(errors, err_msg)
		end

		if completed >= total_ops then
			if #errors > 0 then
				vim.notify("Sync completed with errors: " .. table.concat(errors, ", "), vim.log.levels.WARN)
				if callback then
					callback(false)
				end
			else
				vim.notify("2-way sync completed successfully!")
				if callback then
					callback(true)
				end
			end
		end
	end

	-- Sync to Google
	for _, op in ipairs(operations.to_google) do
		if op.type == "create" then
			M.create_google_task(op.markdown_task, task_list_id, op_complete)
		elseif op.type == "update" then
			M.update_google_task(op.markdown_task, op.google_task, task_list_id, op_complete)
		end
	end

	-- Sync to markdown (single operation for all tasks)
	if #operations.to_markdown > 0 then
		M.write_google_tasks_to_markdown(operations.to_markdown, markdown_dir, list_name, function(success)
			op_complete(success, success and nil or "Failed to write tasks to markdown")
		end)
	end
end

---Writes Google Tasks to markdown file
---@param tasks table[] Array of Google Tasks to write
---@param markdown_dir string Directory to write to
---@param list_name string Name of the task list
---@param callback function Callback when complete
function M.write_google_tasks_to_markdown(tasks, markdown_dir, list_name, callback)
	local filename = markdown_dir .. "/" .. list_name .. ".md"

	-- Read existing file if it exists
	local existing_lines = {}
	local file = io.open(filename, "r")
	if file then
		for line in file:lines() do
			table.insert(existing_lines, line)
		end
		file:close()
	end

	-- Parse existing tasks
	local existing_tasks = parser.parse_tasks(existing_lines)
	local existing_by_title = {}
	for _, task in ipairs(existing_tasks) do
		existing_by_title[task.title] = true
	end

	-- Convert new Google Tasks to markdown format
	local new_task_lines = {}
	local new_task_count = 0
	for _, gtask in ipairs(tasks) do
		-- Skip if already exists in file
		if not existing_by_title[gtask.title] then
			local checkbox = gtask.status == "completed" and "x" or " "
			table.insert(new_task_lines, string.format("- [%s] %s", checkbox, gtask.title))
			new_task_count = new_task_count + 1

			-- Add description/notes if present
			if gtask.notes and gtask.notes ~= "" then
				for line in gtask.notes:gmatch("[^\n]+") do
					table.insert(new_task_lines, "    " .. line)
				end
			end
		end
	end

	if new_task_count == 0 then
		-- No new tasks to write
		if callback then
			callback(true)
		end
		return
	end

	-- Prepare content to write
	local content_lines = {}

	-- Add header if file doesn't exist
	if #existing_lines == 0 then
		table.insert(content_lines, "# " .. list_name)
		table.insert(content_lines, "")
	else
		-- Keep existing content
		for _, line in ipairs(existing_lines) do
			table.insert(content_lines, line)
		end
		table.insert(content_lines, "")
	end

	-- Add new tasks
	for _, line in ipairs(new_task_lines) do
		table.insert(content_lines, line)
	end

	-- Write to file
	file = io.open(filename, "w")
	if not file then
		vim.notify("Failed to write to " .. filename, vim.log.levels.ERROR)
		if callback then
			callback(false)
		end
		return
	end

	for _, line in ipairs(content_lines) do
		file:write(line .. "\n")
	end
	file:close()

	vim.notify(string.format("Wrote %d new task(s) to %s", new_task_count, filename))
	if callback then
		callback(true)
	end
end

---Syncs all markdown files from the configured directory with Google Tasks (2-way sync)
---Task list name is determined by the H1 heading in each markdown file
---Also pulls down tasks from all Google Task lists
---@param callback function Callback function called when sync is complete
function M.sync_directory_with_google(callback)
	-- Validate directory configuration
	local valid, err = files.validate_markdown_dir()
	if not valid then
		vim.notify(err, vim.log.levels.ERROR)
		if callback then
			callback(false)
		end
		return
	end

	vim.notify("Starting 2-way sync: scanning markdown directory and fetching Google Tasks...")

	-- First, fetch all Google Task lists
	api.get_task_lists(function(response, api_err)
		if api_err then
			vim.notify("Failed to fetch Google Task lists: " .. api_err, vim.log.levels.ERROR)
			if callback then
				callback(false)
			end
			return
		end

		local google_lists = response.items or {}

		-- Parse all markdown files
		local all_file_data = files.parse_all_markdown_files()

		-- Group markdown tasks by list name (H1 heading)
		local lists_data = {}
		local total_markdown_tasks = 0

		for _, file_data in ipairs(all_file_data) do
			if file_data.list_name and #file_data.tasks > 0 then
				if not lists_data[file_data.list_name] then
					lists_data[file_data.list_name] = {
						tasks = {},
						files = {},
					}
				end

				-- Add file metadata to tasks
				for _, task in ipairs(file_data.tasks) do
					task.source_file = file_data.file_name
					task.source_file_path = file_data.file_path
					table.insert(lists_data[file_data.list_name].tasks, task)
				end

				table.insert(lists_data[file_data.list_name].files, file_data.file_name)
				total_markdown_tasks = total_markdown_tasks + #file_data.tasks
			end
		end

		-- Add all Google Task lists to the sync (even if no local markdown exists)
		for _, google_list in ipairs(google_lists) do
			if not lists_data[google_list.title] then
				-- List exists in Google but not locally - initialize empty
				lists_data[google_list.title] = {
					tasks = {},
					files = {},
				}
			end
		end

		local list_count = 0
		for _ in pairs(lists_data) do
			list_count = list_count + 1
		end

		vim.notify(string.format(
			"Found %d markdown task(s) in %d file(s), %d Google list(s), syncing %d total list(s)",
			total_markdown_tasks,
			#all_file_data,
			#google_lists,
			list_count
		))

		-- Sync each list
		M.sync_multiple_lists(lists_data, files.get_markdown_dir(), callback)
	end)
end

---Syncs multiple task lists
---@param lists_data table Map of list_name => {tasks, files}
---@param markdown_dir string Markdown directory path
---@param callback function Callback when all lists are synced
function M.sync_multiple_lists(lists_data, markdown_dir, callback)
	local list_names = {}
	for list_name in pairs(lists_data) do
		table.insert(list_names, list_name)
	end

	if #list_names == 0 then
		vim.notify("No task lists to sync")
		if callback then
			callback(true)
		end
		return
	end

	local completed_lists = 0
	local total_lists = #list_names
	local errors = {}

	local function list_complete(success, err_msg)
		completed_lists = completed_lists + 1

		if not success and err_msg then
			table.insert(errors, err_msg)
		end

		if completed_lists >= total_lists then
			if #errors > 0 then
				vim.notify(
					string.format("Sync completed with errors: %s", table.concat(errors, ", ")),
					vim.log.levels.WARN
				)
				if callback then
					callback(false)
				end
			else
				vim.notify(string.format("Successfully synced %d task list(s)!", total_lists))
				if callback then
					callback(true)
				end
			end
		end
	end

	-- Sync each list
	for _, list_name in ipairs(list_names) do
		M.sync_single_list(list_name, lists_data[list_name], markdown_dir, list_complete)
	end
end

---Syncs a single task list
---@param list_name string Name of the task list
---@param list_data table {tasks, files}
---@param markdown_dir string Markdown directory path
---@param callback function Callback when list is synced
function M.sync_single_list(list_name, list_data, markdown_dir, callback)
	vim.notify(string.format("Syncing list: %s", list_name))

	-- Get or create the list in Google Tasks
	api.get_or_create_list(list_name, function(list, err)
		if err then
			callback(false, string.format("Failed to get/create list '%s': %s", list_name, err))
			return
		end

		if not list or not list.id then
			callback(false, string.format("Invalid list object for '%s'", list_name))
			return
		end

		local task_list_id = list.id

		-- Fetch current tasks from this list
		api.get_tasks(task_list_id, function(google_response, api_err)
			if api_err then
				callback(false, string.format("Failed to fetch tasks for '%s': %s", list_name, api_err))
				return
			end

			local google_tasks = google_response.items or {}
			vim.notify(string.format("List '%s': %d markdown tasks, %d Google tasks", list_name, #list_data.tasks, #google_tasks))

			-- Perform 2-way sync for this list
			M.perform_twoway_sync({
				markdown_tasks = list_data.tasks,
				google_tasks = google_tasks,
				task_list_id = task_list_id,
				markdown_dir = markdown_dir,
				list_name = list_name,
			}, function(success)
				if success then
					callback(true)
				else
					callback(false, string.format("Sync failed for list '%s'", list_name))
				end
			end)
		end)
	end)
end

return M
