local M = {}

local api = require("gtask.api")
local parser = require("gtask.parser")
local files = require("gtask.files")
local mapping = require("gtask.mapping")

---Calculate simple string similarity (0.0 to 1.0)
---@param str1 string First string
---@param str2 string Second string
---@return number Similarity ratio (1.0 = exact match, 0.0 = completely different)
local function calculate_similarity(str1, str2)
	if str1 == str2 then
		return 1.0
	end

	-- Simple approach: check if one contains the other
	local lower1 = str1:lower()
	local lower2 = str2:lower()

	if lower1:find(lower2, 1, true) or lower2:find(lower1, 1, true) then
		return 0.8
	end

	-- Check first/last words match
	local words1 = {}
	for word in lower1:gmatch("%S+") do
		table.insert(words1, word)
	end
	local words2 = {}
	for word in lower2:gmatch("%S+") do
		table.insert(words2, word)
	end

	if #words1 > 0 and #words2 > 0 then
		if words1[1] == words2[1] or words1[#words1] == words2[#words2] then
			return 0.7
		end
	end

	return 0.0
end

---Check if markdown task is similar enough to Google task
---@param mdtask table Markdown task
---@param gtask table Google task
---@return boolean True if tasks appear to be the same
local function tasks_are_similar(mdtask, gtask)
	-- Title similarity check
	local title_sim = calculate_similarity(mdtask.title, gtask.title)
	if title_sim > 0.75 then
		return true
	end

	-- If completion status matches, more likely to be the same task
	local md_completed = mdtask.completed
	local g_completed = (gtask.status == "completed")
	if md_completed == g_completed and title_sim > 0.6 then
		return true
	end

	return false
end

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
---@param callback function Callback when operation completes (success, err_msg, task_id, task_index)
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
			callback(false, "Failed to create task: " .. mdtask.title, nil, nil)
		else
			-- Return success, no error, the new task ID, and the task's line_number (as index)
			callback(true, nil, response.id, mdtask.line_number)
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

---Performs 2-way sync between markdown and Google Tasks (position-based with recovery)
---@param sync_state table State containing tasks and configuration
---@param callback function Callback when sync is complete
function M.perform_twoway_sync(sync_state, callback)
	local markdown_tasks = sync_state.markdown_tasks
	local google_tasks = sync_state.google_tasks
	local task_list_id = sync_state.task_list_id
	local markdown_dir = sync_state.markdown_dir
	local list_name = sync_state.list_name

	-- Load mapping data
	local map = mapping.load()

	-- Index Google tasks by ID for quick lookup
	local google_by_id = {}
	for _, gtask in ipairs(google_tasks) do
		google_by_id[gtask.id] = gtask
	end

	-- Build task keys and perform tiered matching
	local md_task_keys = {}
	local all_md_tasks_with_keys = {}
	local match_stats = { exact = 0, nearby = 0, context = 0, new = 0 }

	for i, mdtask in ipairs(markdown_tasks) do
		-- Get parent information
		local parent_title = nil
		local parent_line_number = nil
		if mdtask.parent_index and markdown_tasks[mdtask.parent_index] then
			parent_title = markdown_tasks[mdtask.parent_index].title
			parent_line_number = markdown_tasks[mdtask.parent_index].line_number
		end

		-- Generate position-based key
		local file_path = mdtask.source_file_path or ""
		local task_key = mapping.generate_task_key(list_name, file_path, mdtask.line_number, parent_line_number)
		local context_sig = mapping.generate_context_signature(list_name, mdtask.title, parent_title)

		-- Tier 1: Try exact position match
		local google_id = mapping.get_google_id(map, task_key)
		local match_type = nil
		local matched_gtask = nil

		if google_id and google_by_id[google_id] then
			-- Exact match found
			matched_gtask = google_by_id[google_id]
			match_type = "exact"
			match_stats.exact = match_stats.exact + 1
		else
			-- Tier 2: Try nearby position match
			local nearby_key, nearby_data, offset = mapping.find_nearby(map, list_name, file_path, mdtask.line_number, parent_line_number)
			if nearby_data and google_by_id[nearby_data.google_id] then
				local nearby_gtask = google_by_id[nearby_data.google_id]
				-- Verify similarity before accepting
				if tasks_are_similar(mdtask, nearby_gtask) then
					google_id = nearby_data.google_id
					matched_gtask = nearby_gtask
					match_type = "nearby"
					match_stats.nearby = match_stats.nearby + 1

					-- Update mapping with new position
					mapping.update_task_position(map, nearby_key, task_key, mdtask.line_number)
					vim.notify(string.format("Recovered moved task: '%s' (moved %d lines)", mdtask.title, offset), vim.log.levels.INFO)
				end
			end

			-- Tier 3: Try context-based match
			if not google_id then
				local context_key, context_data = mapping.find_by_context(map, context_sig)
				if context_data and google_by_id[context_data.google_id] then
					local context_gtask = google_by_id[context_data.google_id]
					-- Verify similarity
					if tasks_are_similar(mdtask, context_gtask) then
						google_id = context_data.google_id
						matched_gtask = context_gtask
						match_type = "context"
						match_stats.context = match_stats.context + 1

						-- Update mapping with new position
						mapping.update_task_position(map, context_key, task_key, mdtask.line_number)
						vim.notify(string.format("Recovered reorganized task: '%s'", mdtask.title), vim.log.levels.INFO)
					end
				end
			end
		end

		-- If no match found, it's a new task
		if not google_id then
			match_type = "new"
			match_stats.new = match_stats.new + 1
		end

		table.insert(md_task_keys, task_key)
		table.insert(all_md_tasks_with_keys, {
			task = mdtask,
			key = task_key,
			context_sig = context_sig,
			parent_title = parent_title,
			parent_line_number = parent_line_number,
			google_id = google_id,
			matched_gtask = matched_gtask,
			match_type = match_type,
		})
	end

	-- Build operations based on matching results
	local operations = {
		to_google = {},
		to_markdown = {},
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
				-- Task exists in both, check if update needed
				if M.task_needs_update(item.task, item.matched_gtask) then
					table.insert(operations.to_google, {
						type = "update",
						markdown_task = item.task,
						google_task = item.matched_gtask,
						task_key = item.key,
						context_sig = item.context_sig,
						parent_title = item.parent_title,
						parent_line_number = item.parent_line_number,
						parent_key = parent_key,
					})
				end
			else
				-- Task was deleted in Google
				vim.notify(string.format("Task '%s' was deleted in Google Tasks", item.task.title), vim.log.levels.INFO)
			end
		else
			-- No mapping - new task
			table.insert(operations.to_google, {
				type = "create",
				markdown_task = item.task,
				task_key = item.key,
				context_sig = item.context_sig,
				parent_title = item.parent_title,
				parent_line_number = item.parent_line_number,
				parent_key = parent_key,
			})
		end
	end

	-- Find Google tasks not in markdown
	for _, gtask in ipairs(google_tasks) do
		if not seen_google_ids[gtask.id] then
			table.insert(operations.to_markdown, gtask)
		end
	end

	-- Report sync plan with match statistics
	vim.notify(string.format(
		"Sync plan: %d to Google (%d new, %d updates), %d to markdown | Matches: %d exact, %d nearby, %d context, %d new",
		#operations.to_google,
		#vim.tbl_filter(function(op) return op.type == "create" end, operations.to_google),
		#vim.tbl_filter(function(op) return op.type == "update" end, operations.to_google),
		#operations.to_markdown,
		match_stats.exact,
		match_stats.nearby,
		match_stats.context,
		match_stats.new
	))

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
	local total_ops = #updates + #creates_toplevel + #creates_subtasks
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
	local task_id_map = {} -- Maps markdown task index to Google task ID

	local function op_complete(success, err_msg)
		completed = completed + 1
		if not success and err_msg then
			table.insert(errors, err_msg)
		end

		if completed >= total_ops then
			-- Clean up orphaned tasks and save mapping
			local removed_count = mapping.cleanup_orphaned_tasks(map, list_name, md_task_keys)
			if removed_count > 0 then
				vim.notify(string.format("Cleaned up %d orphaned task mapping(s)", removed_count), vim.log.levels.INFO)
			end
			mapping.save(map)

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

	-- Phase 1: Update existing tasks
	for _, op in ipairs(updates) do
		M.update_google_task(op.markdown_task, op.google_task, task_list_id, function(success, err_msg)
			if success then
				-- Update mapping with current information (title might have changed)
				local file_path = op.markdown_task.source_file_path or ""
				mapping.register_task(
					map,
					op.task_key,
					op.google_task.id,
					list_name,
					op.markdown_task.title,
					file_path,
					op.markdown_task.line_number,
					op.parent_key,
					op.context_sig
				)
			end
			op_complete(success, err_msg)
		end)
	end

	-- Phase 2: Create top-level tasks
	local toplevel_completed = 0
	local toplevel_total = #creates_toplevel

	if toplevel_total > 0 then
		for _, op in ipairs(creates_toplevel) do
			M.create_google_task(op.markdown_task, task_list_id, nil, function(success, err_msg, task_id, task_index)
				if success and task_id and task_index then
					task_id_map[task_index] = task_id

					-- Register in mapping
					local file_path = op.markdown_task.source_file_path or ""
					mapping.register_task(
						map,
						op.task_key,
						task_id,
						list_name,
						op.markdown_task.title,
						file_path,
						op.markdown_task.line_number,
						nil, -- parent_key is nil for top-level tasks
						op.context_sig
					)
				end
				toplevel_completed = toplevel_completed + 1

				-- When all top-level tasks are done, create subtasks
				if toplevel_completed >= toplevel_total then
					-- Phase 3: Create subtasks with parent references
					for _, subop in ipairs(creates_subtasks) do
						local parent_id = task_id_map[subop.markdown_task.parent_index]
						M.create_google_task(subop.markdown_task, task_list_id, parent_id, function(sub_success, sub_err_msg, sub_task_id, sub_task_index)
							if sub_success and sub_task_id then
								-- Register subtask in mapping
								local sub_file_path = subop.markdown_task.source_file_path or ""
								mapping.register_task(
									map,
									subop.task_key,
									sub_task_id,
									list_name,
									subop.markdown_task.title,
									sub_file_path,
									subop.markdown_task.line_number,
									subop.parent_key,
									subop.context_sig
								)
							end
							op_complete(sub_success, sub_err_msg)
						end)
					end
				end

				op_complete(success, err_msg)
			end)
		end
	else
		-- No top-level tasks, go directly to subtasks
		for _, subop in ipairs(creates_subtasks) do
			local parent_id = task_id_map[subop.markdown_task.parent_index]
			M.create_google_task(subop.markdown_task, task_list_id, parent_id, function(sub_success, sub_err_msg, sub_task_id, sub_task_index)
				if sub_success and sub_task_id then
					-- Register subtask in mapping
					local sub_file_path = subop.markdown_task.source_file_path or ""
					mapping.register_task(
						map,
						subop.task_key,
						sub_task_id,
						list_name,
						subop.markdown_task.title,
						sub_file_path,
						subop.markdown_task.line_number,
						subop.parent_key,
						subop.context_sig
					)
				end
				op_complete(sub_success, sub_err_msg)
			end)
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
