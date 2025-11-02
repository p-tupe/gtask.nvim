local M = {}

local api = require("gtask.api")
local parser = require("gtask.parser")
local files = require("gtask.files")
local mapping = require("gtask.mapping")
local utils = require("gtask.utils")

---Normalize a list name to a safe filename
---@param list_name string The list name to normalize
---@return string Normalized filename (without .md extension)
local function normalize_filename(list_name)
	if not list_name or list_name == "" then
		return "untitled"
	end

	-- Convert to lowercase
	local normalized = list_name:lower()

	-- Remove or replace problematic characters
	-- Replace spaces and common separators with hyphens
	normalized = normalized:gsub("[%s_]+", "-")

	-- Remove characters that are problematic in filenames
	normalized = normalized:gsub('[/:*?"<>|\\]', "")

	-- Remove leading/trailing hyphens
	normalized = normalized:gsub("^%-+", "")
	normalized = normalized:gsub("%-+$", "")

	-- Collapse multiple hyphens
	normalized = normalized:gsub("%-+", "-")

	-- If empty after normalization, use fallback
	if normalized == "" then
		return "untitled"
	end

	return normalized
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

	-- Check due date
	local md_due = mdtask.due_date or ""
	local g_due = gtask.due or ""
	if md_due ~= g_due then
		return true
	end

	return false
end

---Creates a new Google task from a markdown task with optional parent
---@param mdtask Task Markdown task to create
---@param task_list_id string Google Tasks list ID
---@param parent_id string|nil Parent task ID (nil for top-level)
---@param callback function Callback when operation completes (success, err_msg, created_task)
function M.create_google_task(mdtask, task_list_id, parent_id, callback)
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

	-- Use create_task_with_parent which handles both top-level and subtasks
	api.create_task_with_parent(task_list_id, google_task, parent_id, nil, function(response, err)
		if err then
			callback(false, "Failed to create task: " .. mdtask.title, nil)
		else
			-- Return success, no error, and the full task response (includes id and updated timestamp)
			callback(true, nil, response)
		end
	end)
end

---Updates an existing Google task from a markdown task
---@param mdtask Task Markdown task with new data
---@param gtask table Existing Google task to update
---@param task_list_id string Google Tasks list ID
---@param callback function Callback when operation completes (success, err_msg, updated_task)
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
			callback(false, "Failed to update task: " .. mdtask.title, nil)
		else
			-- Return the full response (includes updated timestamp)
			callback(true, nil, response)
		end
	end)
end

---Performs 2-way sync between markdown and Google Tasks (position-based with recovery)
---@param sync_state table State containing tasks and configuration
---@param callback function Callback when sync is complete
function M.perform_twoway_sync(sync_state, callback)
	local markdown_tasks = sync_state.markdown_tasks
	local google_tasks = sync_state.google_tasks
	local task_list_id = sync_state.task_list_id
	local markdown_dir = sync_state.markdown_dir
	local list_name = sync_state.list_name

	-- Use shared mapping data (to prevent race conditions across multiple list syncs)
	local map = sync_state.shared_map or mapping.load()

	-- Index Google tasks by ID for quick lookup
	local google_by_id = {}
	for _, gtask in ipairs(google_tasks) do
		google_by_id[gtask.id] = gtask
	end

	-- Build task keys with exact position matching only
	local md_task_keys = {}
	local md_task_keys_set = {}
	local all_md_tasks_with_keys = {}

	for i, mdtask in ipairs(markdown_tasks) do
		-- Task already has position_path from parser
		local file_path = mdtask.source_file_path or ""

		-- Generate tree-position-based key using position_path
		local task_key = mapping.generate_task_key(list_name, file_path, mdtask.position_path)

		-- Get mapping data for this task
		local mapping_data = map.tasks[task_key]
		local google_id = mapping_data and mapping_data.google_id or nil
		local matched_gtask = nil

		-- Skip if task was deleted from Google (don't recreate)
		if mapping_data and mapping_data.deleted_from_google then
			-- Task was deleted from Google, don't sync
			goto continue
		end

		if google_id and google_by_id[google_id] then
			-- Found exact match at this position
			matched_gtask = google_by_id[google_id]
		end

		table.insert(md_task_keys, task_key)
		md_task_keys_set[task_key] = true
		table.insert(all_md_tasks_with_keys, {
			task = mdtask,
			key = task_key,
			task_index = i, -- Store array index for parent-child mapping
			google_id = google_id,
			matched_gtask = matched_gtask,
			mapping_data = mapping_data,
		})

		::continue::
	end

	-- Detect tasks deleted from markdown (exist in mapping but not in current markdown)
	local deleted_from_markdown = {}
	for task_key, mapping_data in pairs(map.tasks) do
		if
			mapping_data.list_name == list_name
			and not md_task_keys_set[task_key]
			and not mapping_data.deleted_from_google
		then
			-- Task was in mapping but not in current markdown
			table.insert(deleted_from_markdown, {
				key = task_key,
				google_id = mapping_data.google_id,
				mapping_data = mapping_data,
			})
		end
	end

	-- Build operations based on exact matching results
	local operations = {
		to_google = {},
		to_markdown = {},
		delete_from_google = {},
		delete_from_markdown = {},
	}
	local seen_google_ids = {}

	for _, item in ipairs(all_md_tasks_with_keys) do
		-- Determine parent_key if this is a subtask
		local parent_key = nil
		if item.task.parent_index and all_md_tasks_with_keys[item.task.parent_index] then
			parent_key = all_md_tasks_with_keys[item.task.parent_index].key
		end

		if item.google_id then
			seen_google_ids[item.google_id] = true

			if item.matched_gtask then
				-- Task exists in both locations
				local needs_update = false
				local update_direction = nil -- "to_google" or "to_markdown"

				-- Check completion status conflict
				local md_completed = item.task.completed
				local g_completed = (item.matched_gtask.status == "completed")

				if md_completed ~= g_completed then
					-- Completion status conflict - use timestamps to resolve
					local google_updated = item.matched_gtask.updated
					local mapping_google_updated = item.mapping_data and item.mapping_data.google_updated

					if google_updated and mapping_google_updated and google_updated > mapping_google_updated then
						-- Google was modified since last sync - Google wins
						update_direction = "to_markdown"
						needs_update = true
					else
						-- Markdown is newer or timestamps equal - Markdown wins
						update_direction = "to_google"
						needs_update = true
					end
				elseif M.task_needs_update(item.task, item.matched_gtask) then
					-- Other changes (description, due date, title)
					update_direction = "to_google"
					needs_update = true
				end

				if needs_update then
					if update_direction == "to_google" then
						table.insert(operations.to_google, {
							type = "update",
							markdown_task = item.task,
							google_task = item.matched_gtask,
							task_key = item.key,
							task_index = item.task_index,
							parent_key = parent_key,
						})
					else -- to_markdown
						table.insert(operations.to_markdown, {
							type = "update_completion",
							google_task = item.matched_gtask,
							task_key = item.key,
							file_path = item.task.source_file_path,
							line_number = item.task.line_number,
						})
					end
				end
			else
				-- Task was deleted from Google
				local config = require("gtask.config")
				if item.task.completed then
					-- Completed task deleted from Google
					if config.sync.keep_completed_in_markdown then
						-- Mark as deleted, keep in markdown
						mapping.mark_deleted_from_google(map, item.key)
						utils.notify(
							string.format("Completed task deleted from Google (kept in markdown): %s", item.task.title),
							vim.log.levels.INFO
						)
					else
						-- Delete from markdown too
						table.insert(operations.delete_from_markdown, {
							task_key = item.key,
							file_path = item.task.source_file_path,
							line_number = item.task.line_number,
							title = item.task.title,
						})
					end
				else
					-- Incomplete task deleted from Google - delete from markdown
					table.insert(operations.delete_from_markdown, {
						task_key = item.key,
						file_path = item.task.source_file_path,
						line_number = item.task.line_number,
						title = item.task.title,
					})
				end
			end
		else
			-- No mapping at this position - new task
			table.insert(operations.to_google, {
				type = "create",
				markdown_task = item.task,
				task_key = item.key,
				task_index = item.task_index,
				parent_key = parent_key,
			})
		end
	end

	-- Find Google tasks not in markdown (write them to markdown)
	for _, gtask in ipairs(google_tasks) do
		if not seen_google_ids[gtask.id] then
			table.insert(operations.to_markdown, gtask)
		end
	end

	-- Add delete operations for tasks deleted from markdown
	for _, deleted_item in ipairs(deleted_from_markdown) do
		table.insert(operations.delete_from_google, {
			google_id = deleted_item.google_id,
			task_key = deleted_item.key,
		})
	end

	-- Report sync plan
	local new_to_google = #vim.tbl_filter(function(op)
		return op.type == "create"
	end, operations.to_google)
	local updates_to_google = #vim.tbl_filter(function(op)
		return op.type == "update"
	end, operations.to_google)
	local new_to_markdown = #vim.tbl_filter(function(op)
		return type(op) == "table" and not op.type
	end, operations.to_markdown)
	local updates_to_markdown = #vim.tbl_filter(function(op)
		return type(op) == "table" and op.type == "update_completion"
	end, operations.to_markdown)

	utils.notify(
		string.format(
			"Sync plan: %d→Google (%d new, %d update), %d→markdown (%d new, %d update), %d deletions from Google, %d deletions from markdown",
			new_to_google + updates_to_google,
			new_to_google,
			updates_to_google,
			new_to_markdown + updates_to_markdown,
			new_to_markdown,
			updates_to_markdown,
			#operations.delete_from_markdown,
			#operations.delete_from_google
		)
	)

	-- Execute sync operations with mapping
	M.execute_twoway_sync(operations, task_list_id, markdown_dir, list_name, map, md_task_keys, callback)
end

---Executes 2-way sync operations with two-pass creation for parent-child relationships
---@param operations table Operations to perform
---@param task_list_id string Google Tasks list ID
---@param markdown_dir string Markdown directory path
---@param list_name string Name of the task list
---@param map table Mapping data
---@param md_task_keys table Array of current markdown task keys
---@param callback function Callback when complete
function M.execute_twoway_sync(operations, task_list_id, markdown_dir, list_name, map, md_task_keys, callback)
	-- Separate creates into updates, top-level creates, and subtask creates
	local updates = {}
	local creates_toplevel = {}
	local creates_subtasks = {}

	for _, op in ipairs(operations.to_google) do
		if op.type == "update" then
			table.insert(updates, op)
		elseif op.type == "create" then
			if op.markdown_task.parent_index then
				table.insert(creates_subtasks, op)
			else
				table.insert(creates_toplevel, op)
			end
		end
	end

	-- Count total operations
	local total_ops = #updates
		+ #creates_toplevel
		+ #creates_subtasks
		+ #operations.delete_from_google
		+ #operations.delete_from_markdown
	if #operations.to_markdown > 0 then
		total_ops = total_ops + 1
	end

	if total_ops == 0 then
		utils.notify("All tasks are in sync!")
		if callback then
			callback(true)
		end
		return
	end

	local completed = 0
	local errors = {}
	local task_id_map = {} -- Maps markdown task index to Google task ID

	local function op_complete(success, err_msg)
		completed = completed + 1
		if not success and err_msg then
			table.insert(errors, err_msg)
		end

		if completed >= total_ops then
			-- Clean up orphaned tasks (mapping will be saved at the top level after all lists sync)
			local removed_count = mapping.cleanup_orphaned_tasks(map, list_name, md_task_keys)
			if removed_count > 0 then
				utils.notify(
					string.format("Cleaned up %d orphaned task mapping(s)", removed_count),
					vim.log.levels.INFO
				)
			end
			-- Note: mapping.save() is now called in sync_multiple_lists after all lists complete

			if #errors > 0 then
				utils.notify("Sync completed with errors: " .. table.concat(errors, ", "), vim.log.levels.WARN)
				if callback then
					callback(false)
				end
			else
				utils.notify("2-way sync completed successfully!")
				if callback then
					callback(true)
				end
			end
		end
	end

	-- Phase 1: Update existing tasks
	for _, op in ipairs(updates) do
		M.update_google_task(op.markdown_task, op.google_task, task_list_id, function(success, err_msg, updated_task)
			if success then
				-- Update mapping with current information and new timestamp
				local file_path = op.markdown_task.source_file_path or ""
				local google_updated = (updated_task and updated_task.updated)
					or op.google_task.updated
					or os.date("!%Y-%m-%dT%H:%M:%SZ")
				mapping.register_task(
					map,
					op.task_key,
					op.google_task.id,
					list_name,
					file_path,
					op.markdown_task.position_path,
					op.parent_key,
					google_updated
				)
			end
			op_complete(success, err_msg)
		end)
	end

	-- Phase 1.5: Delete from Google (tasks deleted from markdown)
	for _, del_op in ipairs(operations.delete_from_google) do
		api.delete_task(task_list_id, del_op.google_id, function(success, err)
			if success then
				-- Remove from mapping
				mapping.remove_task(map, del_op.task_key)
				utils.notify(string.format("Deleted task from Google: %s", del_op.task_key), vim.log.levels.INFO)
			end
			op_complete(success, err and ("Failed to delete from Google: " .. err) or nil)
		end)
	end

	-- Phase 1.6: Delete from markdown (tasks deleted from Google)
	for _, del_op in ipairs(operations.delete_from_markdown) do
		M.delete_task_from_markdown(del_op.file_path, del_op.line_number, function(success, err_msg)
			if success then
				-- Remove from mapping
				mapping.remove_task(map, del_op.task_key)
				utils.notify(string.format("Deleted task from markdown: %s", del_op.title), vim.log.levels.INFO)
			end
			op_complete(success, err_msg)
		end)
	end

	-- Phase 2: Create top-level tasks
	local toplevel_completed = 0
	local toplevel_total = #creates_toplevel

	if toplevel_total > 0 then
		for _, op in ipairs(creates_toplevel) do
			M.create_google_task(op.markdown_task, task_list_id, nil, function(success, err_msg, created_task)
				if success and created_task then
					task_id_map[op.task_index] = created_task.id

					-- Register in mapping with google_updated timestamp
					local file_path = op.markdown_task.source_file_path or ""
					mapping.register_task(
						map,
						op.task_key,
						created_task.id,
						list_name,
						file_path,
						op.markdown_task.position_path,
						nil, -- parent_key is nil for top-level tasks
						created_task.updated
					)
				end
				toplevel_completed = toplevel_completed + 1

				-- When all top-level tasks are done, create subtasks
				if toplevel_completed >= toplevel_total then
					-- Phase 3: Create subtasks with parent references
					for _, subop in ipairs(creates_subtasks) do
						local parent_id = task_id_map[subop.markdown_task.parent_index]
						M.create_google_task(
							subop.markdown_task,
							task_list_id,
							parent_id,
							function(sub_success, sub_err_msg, sub_created_task)
								if sub_success and sub_created_task then
									-- Register subtask in mapping with google_updated timestamp
									local sub_file_path = subop.markdown_task.source_file_path or ""
									mapping.register_task(
										map,
										subop.task_key,
										sub_created_task.id,
										list_name,
										sub_file_path,
										subop.markdown_task.position_path,
										subop.parent_key,
										sub_created_task.updated
									)
								end
								op_complete(sub_success, sub_err_msg)
							end
						)
					end
				end

				op_complete(success, err_msg)
			end)
		end
	else
		-- No top-level tasks, go directly to subtasks
		for _, subop in ipairs(creates_subtasks) do
			local parent_id = task_id_map[subop.markdown_task.parent_index]
			M.create_google_task(
				subop.markdown_task,
				task_list_id,
				parent_id,
				function(sub_success, sub_err_msg, sub_created_task)
					if sub_success and sub_created_task then
						-- Register subtask in mapping with google_updated timestamp
						local sub_file_path = subop.markdown_task.source_file_path or ""
						mapping.register_task(
							map,
							subop.task_key,
							sub_created_task.id,
							list_name,
							sub_file_path,
							subop.markdown_task.position_path,
							subop.parent_key,
							sub_created_task.updated
						)
					end
					op_complete(sub_success, sub_err_msg)
				end
			)
		end
	end

	-- Phase 4: Sync to markdown
	-- Separate new tasks from completion updates
	local new_tasks_to_markdown = {}
	local completion_updates = {}

	for _, op in ipairs(operations.to_markdown) do
		if type(op) == "table" and op.type == "update_completion" then
			table.insert(completion_updates, op)
		else
			table.insert(new_tasks_to_markdown, op)
		end
	end

	-- Phase 4a: Write new tasks to markdown (single operation for all new tasks)
	if #new_tasks_to_markdown > 0 then
		M.write_google_tasks_to_markdown(new_tasks_to_markdown, markdown_dir, list_name, function(success)
			op_complete(success, success and nil or "Failed to write tasks to markdown")
		end)
	end

	-- Phase 4b: Update completion status in markdown (individual operations)
	for _, update_op in ipairs(completion_updates) do
		local is_completed = (update_op.google_task.status == "completed")
		M.update_task_completion_in_markdown(
			update_op.file_path,
			update_op.line_number,
			is_completed,
			function(success, err_msg)
				if success then
					-- Update mapping with new Google timestamp
					local mapping_data = map.tasks[update_op.task_key]
					if mapping_data then
						mapping_data.google_updated = update_op.google_task.updated or os.date("!%Y-%m-%dT%H:%M:%SZ")
						mapping_data.last_synced = os.date("!%Y-%m-%dT%H:%M:%SZ")
					end
					utils.notify(
						string.format("Updated completion status in markdown: %s", update_op.google_task.title),
						vim.log.levels.INFO
					)
				end
				op_complete(success, err_msg)
			end
		)
	end
end

---Writes Google Tasks to markdown file
---@param tasks table[] Array of Google Tasks to write
---@param markdown_dir string Directory to write to
---@param list_name string Name of the task list
---@param callback function Callback when complete
function M.write_google_tasks_to_markdown(tasks, markdown_dir, list_name, callback)
	local normalized_name = normalize_filename(list_name)
	local filename = markdown_dir .. "/" .. normalized_name .. ".md"

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
		-- Skip if already exists in file (check by title for now)
		if not existing_by_title[gtask.title] then
			local checkbox = gtask.status == "completed" and "x" or " "
			local task_line = string.format("- [%s] %s", checkbox, gtask.title)

			-- Add due date if present (convert from RFC3339 to YYYY-MM-DD HH:MM or YYYY-MM-DD)
			if gtask.due and gtask.due ~= "" then
				-- RFC3339 format: "2025-01-15T14:30:00.000Z"
				local date_part, time_part = gtask.due:match("(%d%d%d%d%-%d%d%-%d%d)T(%d%d:%d%d)")
				if date_part then
					task_line = task_line .. " | " .. date_part
					-- Only add time if it's not midnight (00:00)
					if time_part and time_part ~= "00:00" then
						task_line = task_line .. " " .. time_part
					end
				end
			end

			table.insert(new_task_lines, task_line)
			new_task_count = new_task_count + 1

			-- Add description/notes if present (indented to same level as task)
			if gtask.notes and gtask.notes ~= "" then
				for line in gtask.notes:gmatch("[^\n]+") do
					table.insert(new_task_lines, "  " .. line)
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
		utils.notify("Failed to write to " .. filename, vim.log.levels.ERROR)
		if callback then
			callback(false)
		end
		return
	end

	for _, line in ipairs(content_lines) do
		file:write(line .. "\n")
	end
	file:close()

	utils.notify(string.format("Wrote %d new task(s) to %s", new_task_count, filename))
	if callback then
		callback(true)
	end
end

---Updates the completion status of a task in markdown
---@param file_path string Path to the markdown file
---@param line_number number Line number of the task (1-indexed)
---@param completed boolean New completion status
---@param callback function Callback when complete (success, err_msg)
function M.update_task_completion_in_markdown(file_path, line_number, completed, callback)
	-- Read file
	local file = io.open(file_path, "r")
	if not file then
		if callback then
			callback(false, "Failed to open file: " .. file_path)
		end
		return
	end

	local lines = {}
	for line in file:lines() do
		table.insert(lines, line)
	end
	file:close()

	-- Update the checkbox on the specified line
	if line_number < 1 or line_number > #lines then
		if callback then
			callback(false, "Invalid line number: " .. line_number)
		end
		return
	end

	local line = lines[line_number]
	local checkbox_pattern = "^(%s*%-%s+%[)[%sx](%])"

	if not line:match(checkbox_pattern) then
		if callback then
			callback(false, "Line is not a task: " .. line)
		end
		return
	end

	-- Replace checkbox
	local new_checkbox = completed and "x" or " "
	lines[line_number] = line:gsub(checkbox_pattern, "%1" .. new_checkbox .. "%2", 1)

	-- Write back to file
	file = io.open(file_path, "w")
	if not file then
		if callback then
			callback(false, "Failed to open file for writing: " .. file_path)
		end
		return
	end

	for _, l in ipairs(lines) do
		file:write(l .. "\n")
	end
	file:close()

	if callback then
		callback(true)
	end
end

---Deletes a task from markdown file
---@param file_path string Path to the markdown file
---@param line_number number Line number of the task to delete (1-indexed)
---@param callback function Callback when complete (success, err_msg)
function M.delete_task_from_markdown(file_path, line_number, callback)
	-- Read file
	local file = io.open(file_path, "r")
	if not file then
		if callback then
			callback(false, "Failed to open file: " .. file_path)
		end
		return
	end

	local lines = {}
	for line in file:lines() do
		table.insert(lines, line)
	end
	file:close()

	if line_number < 1 or line_number > #lines then
		if callback then
			callback(false, "Invalid line number: " .. line_number)
		end
		return
	end

	-- Get task line and its indentation
	local task_line = lines[line_number]
	local task_indent = task_line:match("^(%s*)")
	local task_indent_level = math.floor(#task_indent / 2)

	-- Mark lines for deletion: the task line, its description, and all subtasks
	local to_delete = {}
	to_delete[line_number] = true

	-- Scan forward to find description lines and subtasks
	local i = line_number + 1
	while i <= #lines do
		local line = lines[i]

		-- Empty line
		if line:match("^%s*$") then
			-- Check next line to see if it's still part of this task's content
			if i + 1 <= #lines then
				local next_line = lines[i + 1]
				local next_indent = next_line:match("^(%s*)")
				local next_indent_level = math.floor(#next_indent / 2)

				-- If next line is a task at same or lower level, stop
				if next_line:match("^%s*%-%s+%[[ x]%]") and next_indent_level <= task_indent_level then
					break
				end

				-- If next line is also empty, we've hit double empty line - stop
				if next_line:match("^%s*$") then
					break
				end

				-- Next line is indented content, continue
				to_delete[i] = true
			else
				-- End of file
				break
			end
		else
			local line_indent = line:match("^(%s*)")
			local line_indent_level = math.floor(#line_indent / 2)

			-- Check if this is a task
			if line:match("^%s*%-%s+%[[ x]%]") then
				-- Task at same or lower level - stop
				if line_indent_level <= task_indent_level then
					break
				end
				-- Subtask (higher indent level) - delete it
				to_delete[i] = true
			else
				-- Not a task - could be description
				-- If indented more than or equal to task, it's part of this task
				if line_indent_level > task_indent_level then
					to_delete[i] = true
				else
					-- Less indented, not part of this task
					break
				end
			end
		end

		i = i + 1
	end

	-- Create new lines array without deleted lines
	local new_lines = {}
	for idx, line in ipairs(lines) do
		if not to_delete[idx] then
			table.insert(new_lines, line)
		end
	end

	-- Write back to file
	file = io.open(file_path, "w")
	if not file then
		if callback then
			callback(false, "Failed to open file for writing: " .. file_path)
		end
		return
	end

	for _, line in ipairs(new_lines) do
		file:write(line .. "\n")
	end
	file:close()

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
		utils.notify(err, vim.log.levels.ERROR)
		if callback then
			callback(false)
		end
		return
	end

	utils.notify("Starting 2-way sync: scanning markdown directory and fetching Google Tasks...")

	-- First, fetch all Google Task lists
	api.get_task_lists(function(response, api_err)
		if api_err then
			utils.notify("Failed to fetch Google Task lists: " .. api_err, vim.log.levels.ERROR)
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

		utils.notify(
			string.format(
				"Found %d markdown task(s) in %d file(s), %d Google list(s), syncing %d total list(s)",
				total_markdown_tasks,
				#all_file_data,
				#google_lists,
				list_count
			)
		)

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
		utils.notify("No task lists to sync")
		if callback then
			callback(true)
		end
		return
	end

	-- CRITICAL: Load mapping once and share across all syncs to prevent race conditions
	local shared_map = mapping.load()

	local completed_lists = 0
	local total_lists = #list_names
	local errors = {}

	local function list_complete(success, err_msg)
		completed_lists = completed_lists + 1

		if not success and err_msg then
			table.insert(errors, err_msg)
		end

		if completed_lists >= total_lists then
			-- Save mapping after all lists are synced
			mapping.save(shared_map)

			if #errors > 0 then
				utils.notify(
					string.format("Sync completed with errors: %s", table.concat(errors, ", ")),
					vim.log.levels.WARN
				)
				if callback then
					callback(false)
				end
			else
				utils.notify(string.format("Successfully synced %d task list(s)!", total_lists))
				if callback then
					callback(true)
				end
			end
		end
	end

	-- Sync each list with shared mapping
	for _, list_name in ipairs(list_names) do
		M.sync_single_list(list_name, lists_data[list_name], markdown_dir, shared_map, list_complete)
	end
end

---Syncs a single task list
---@param list_name string Name of the task list
---@param list_data table {tasks, files}
---@param markdown_dir string Markdown directory path
---@param shared_map table Shared mapping data (to prevent race conditions)
---@param callback function Callback when list is synced
function M.sync_single_list(list_name, list_data, markdown_dir, shared_map, callback)
	utils.notify(string.format("Syncing list: %s", list_name))

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
			utils.notify(
				string.format(
					"List '%s': %d markdown tasks, %d Google tasks",
					list_name,
					#list_data.tasks,
					#google_tasks
				)
			)

			-- Perform 2-way sync for this list
			M.perform_twoway_sync({
				markdown_tasks = list_data.tasks,
				google_tasks = google_tasks,
				task_list_id = task_list_id,
				markdown_dir = markdown_dir,
				list_name = list_name,
				shared_map = shared_map,
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
