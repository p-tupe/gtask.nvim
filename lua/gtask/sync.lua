local M = {}

local api = require("gtask.api")
local parser = require("gtask.parser")
local files = require("gtask.files")
local mapping = require("gtask.mapping")
local utils = require("gtask.utils")

-- Sync state management to prevent concurrent syncs
local sync_in_progress = false

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

	-- Ensure filename isn't too long (most filesystems limit to 255 bytes)
	-- Reserve 3 chars for ".md" extension
	if #normalized > 252 then
		-- Truncate and add hash to maintain uniqueness
		local hash = string.format("%04x", math.random(0, 65535))
		normalized = normalized:sub(1, 247) .. "-" .. hash
	end

	return normalized
end

---Generates a short UUID for task identification
---Uses base62 encoding to create compact, URL-safe IDs (8-12 characters)
---@return string A unique UUID string
local function generate_uuid()
	-- Use timestamp + random for uniqueness
	local timestamp = os.time()
	local random = math.random(0, 999999)

	-- Combine and encode to create a compact ID
	local combined = timestamp * 1000000 + random

	-- Base62 charset (alphanumeric, case-sensitive)
	local charset = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"
	local uuid = ""

	while combined > 0 do
		local remainder = combined % 62
		uuid = charset:sub(remainder + 1, remainder + 1) .. uuid
		combined = math.floor(combined / 62)
	end

	-- Ensure minimum length of 8 chars by padding
	while #uuid < 8 do
		uuid = "0" .. uuid
	end

	return uuid
end

---Embeds a UUID comment into a markdown file after a task line
---@param file_path string Path to the markdown file
---@param task_line_number integer Line number of the task (1-indexed)
---@param uuid string The UUID to embed
---@param callback function|nil Optional callback (success, err_msg)
local function embed_task_uuid(file_path, task_line_number, uuid, callback)
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

	-- Validate line number
	if task_line_number < 1 or task_line_number > #lines then
		if callback then
			callback(false, string.format("Invalid line number: %d (file has %d lines)", task_line_number, #lines))
		end
		return
	end

	-- Check if UUID comment already exists on next line
	if task_line_number < #lines then
		local next_line = lines[task_line_number + 1]
		local existing_uuid = parser.extract_task_uuid(next_line)
		if existing_uuid then
			-- UUID already exists, don't duplicate
			if callback then
				callback(true, nil)
			end
			return
		end
	end

	-- Get indentation from task line
	local task_line = lines[task_line_number]
	local indent = task_line:match("^(%s*)")

	-- Create UUID comment with same indentation as task
	local uuid_comment = indent .. "<!-- gtask:" .. uuid .. " -->"

	-- Insert UUID comment after task line
	table.insert(lines, task_line_number + 1, uuid_comment)

	-- Write back to file
	local write_file = io.open(file_path, "w")
	if not write_file then
		if callback then
			callback(false, "Failed to open file for writing: " .. file_path)
		end
		return
	end

	for _, line in ipairs(lines) do
		write_file:write(line .. "\n")
	end
	write_file:close()

	if callback then
		callback(true, nil)
	end
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

	-- Always set notes and due, even if empty/nil (to clear them if removed from markdown)
	if mdtask.description and mdtask.description ~= "" then
		updated_task.notes = mdtask.description
	else
		-- Clear notes if removed from markdown
		updated_task.notes = vim.NIL -- Use vim.NIL to represent JSON null
	end

	if mdtask.due_date and mdtask.due_date ~= "" then
		updated_task.due = mdtask.due_date
	else
		-- Clear due date if removed from markdown
		updated_task.due = vim.NIL -- Use vim.NIL to represent JSON null
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

---Performs 2-way sync between markdown and Google Tasks
---
---Sync flow:
---  1. Match tasks by ID (from mapping) or title (fallback)
---  2. Detect deletions (tasks in mapping but not in current markdown)
---  3. Build sync operations (creates, updates, deletes)
---  4. Execute operations and update mappings
---
---Key behaviors:
---  - Bidirectional sync: Uses Google Task's updated timestamp vs last_synced to determine winner
---  - When Google was modified after last sync, Google wins (updates markdown)
---  - When markdown was modified (or timestamps unavailable), markdown wins (updates Google)
---  - All fields sync bidirectionally: title, description, completion status, due date
---  - Title-based matching creates mappings to enable future deletion detection
---  - Deleted task IDs are marked to prevent re-adding them
---
---@param sync_state table State containing tasks and configuration
---@param callback function Callback when sync is complete
function M.perform_twoway_sync(sync_state, callback)
	local markdown_tasks = sync_state.markdown_tasks
	local google_tasks = sync_state.google_tasks
	local task_list_id = sync_state.task_list_id
	local markdown_dir = sync_state.markdown_dir
	local list_name = sync_state.list_name

	-- Use shared mapping data (prevents race conditions when syncing multiple lists)
	local map = sync_state.shared_map or mapping.load()

	-- Index Google tasks for efficient lookups during matching
	local google_by_id = {}
	local google_by_title = {}
	for _, gtask in ipairs(google_tasks) do
		google_by_id[gtask.id] = gtask
		local normalized_title = gtask.title:match("^%s*(.-)%s*$")
		google_by_title[normalized_title] = gtask
	end

	-- Build task keys using UUID-based matching
	local md_task_uuids = {}
	local md_task_uuids_set = {}
	local all_md_tasks_with_keys = {}
	local tasks_needing_uuids = {} -- Track tasks that need UUIDs generated

	for i, mdtask in ipairs(markdown_tasks) do
		local file_path = mdtask.source_file_path or ""

		-- Generate or use existing UUID
		local task_uuid = mdtask.uuid
		if not task_uuid then
			-- Task doesn't have UUID yet - generate one
			task_uuid = generate_uuid()
			mdtask.uuid = task_uuid
			-- Mark for UUID embedding later
			table.insert(tasks_needing_uuids, {
				file_path = file_path,
				line_number = mdtask.line_number,
				uuid = task_uuid,
			})
		end

		-- Generate UUID-based key
		local task_key = mapping.generate_task_key(task_uuid)

		-- Get mapping data for this task
		local mapping_data = map.tasks[task_key]
		local google_id = mapping_data and mapping_data.google_id or nil
		local matched_gtask = nil

		if google_id and google_by_id[google_id] then
			-- Preferred: Match by Google Task ID from our mapping
			matched_gtask = google_by_id[google_id]
		elseif not mapping_data then
			-- Fallback: Match by title when no mapping exists (migration/recovery)
			-- This handles cases where mappings were lost or tasks were manually added
			-- IMPORTANT: Only match if parent relationships are compatible (both top-level)
			local normalized_md_title = mdtask.title:match("^%s*(.-)%s*$")
			local candidate_gtask = google_by_title[normalized_md_title]

			if candidate_gtask then
				-- Check parent relationship compatibility
				local md_is_toplevel = not mdtask.parent_index
				local g_is_toplevel = not candidate_gtask.parent or candidate_gtask.parent == ""

				if md_is_toplevel == g_is_toplevel then
					-- Both are top-level or both have parents - safe to match
					matched_gtask = candidate_gtask
					google_id = candidate_gtask.id
					utils.notify(
						string.format("Matched task by title (no mapping): '%s'", mdtask.title),
						vim.log.levels.INFO
					)
				else
					-- Parent relationship mismatch - don't match (treat as different tasks)
					utils.notify(
						string.format(
							"Skipping title match for '%s': parent mismatch (md=%s, g=%s)",
							mdtask.title,
							md_is_toplevel and "top-level" or "subtask",
							g_is_toplevel and "top-level" or "subtask"
						),
						vim.log.levels.INFO
					)
				end
			end
		end

		table.insert(md_task_uuids, task_key)
		md_task_uuids_set[task_key] = true
		table.insert(all_md_tasks_with_keys, {
			task = mdtask,
			key = task_key,
			uuid = task_uuid,
			task_index = i, -- Store array index for parent-child mapping
			google_id = google_id, -- Will be set by title match if no mapping exists
			matched_gtask = matched_gtask,
			mapping_data = mapping_data,
		})
	end

	-- Detect tasks deleted from markdown (exist in mapping but not in current markdown)
	local deleted_from_markdown = {}
	for task_uuid, mapping_data in pairs(map.tasks) do
		if mapping_data.list_name == list_name and not md_task_uuids_set[task_uuid] then
			-- Task UUID was in mapping but not in current markdown
			table.insert(deleted_from_markdown, {
				uuid = task_uuid,
				google_id = mapping_data.google_id,
				mapping_data = mapping_data,
			})
		end
	end

	-- Build sync operations (creates, updates, deletes)
	local operations = {
		to_google = {}, -- Tasks to create/update in Google
		to_markdown = {}, -- Tasks to write to markdown
		delete_from_google = {}, -- Tasks to delete from Google
		delete_from_markdown = {}, -- Tasks to delete from markdown
	}

	-- Track which Google task IDs we've seen to avoid duplicate processing
	local seen_google_ids = {}

	-- Mark deleted tasks' IDs as seen to prevent them from being re-added
	-- This fixes the issue where deleted tasks would be written back from Google
	for _, deleted_item in ipairs(deleted_from_markdown) do
		if deleted_item.google_id then
			seen_google_ids[deleted_item.google_id] = true
		end
	end

	-- Process each markdown task to determine what operations are needed
	for _, item in ipairs(all_md_tasks_with_keys) do
		-- Build parent reference for subtasks (used in Google Tasks parent-child relationships)
		local parent_uuid = nil
		if item.task.parent_index and all_md_tasks_with_keys[item.task.parent_index] then
			parent_uuid = all_md_tasks_with_keys[item.task.parent_index].uuid
		end

		if item.google_id then
			-- Mark this Google task as processed
			seen_google_ids[item.google_id] = true

			if item.matched_gtask then
				-- Task exists in both markdown and Google - check if sync is needed
				local needs_update = false
				local update_direction = nil -- "to_google" or "to_markdown"

				-- Use timestamps to determine which version is newer for bidirectional sync
				local google_updated = item.matched_gtask.updated
				local mapping_google_updated = item.mapping_data and item.mapping_data.google_updated

				-- Check if there are any differences between markdown and Google
				if M.task_needs_update(item.task, item.matched_gtask) then
					-- Changes detected - use timestamp comparison to determine direction
					if google_updated and mapping_google_updated and google_updated > mapping_google_updated then
						-- Google was modified after our last sync - Google wins for all fields
						update_direction = "to_markdown"
						needs_update = true
					else
						-- Markdown change is newer (or timestamps unavailable) - Markdown wins for all fields
						update_direction = "to_google"
						needs_update = true
					end
				end

				if needs_update then
					if update_direction == "to_google" then
						table.insert(operations.to_google, {
							type = "update",
							markdown_task = item.task,
							google_task = item.matched_gtask,
							task_key = item.key,
							uuid = item.uuid,
							task_index = item.task_index,
							parent_uuid = parent_uuid,
						})
					else -- to_markdown
						table.insert(operations.to_markdown, {
							type = "update_from_google",
							google_task = item.matched_gtask,
							task_key = item.key,
							file_path = item.task.source_file_path,
							markdown_task = item.task, -- Keep reference to markdown task for comparison
						})
					end
				else
					-- Tasks are in sync, but create mapping if missing
					-- This handles title-matched tasks that don't have mappings yet
					-- Without this, deleted tasks won't be detected on next sync
					if not item.mapping_data then
						mapping.register_task(
							map,
							item.uuid,
							item.google_id,
							list_name,
							item.task.source_file_path or "",
							parent_uuid,
							item.matched_gtask.updated or os.date("!%Y-%m-%dT%H:%M:%SZ")
						)
					end
				end
			else
				-- Task was deleted from Google (has google_id in mapping but not found in API response)
				utils.notify(
					string.format(
						"WARNING: Task '%s' has Google ID '%s' but not found in API response. Treating as deleted from Google.",
						item.task.title,
						item.google_id or "nil"
					),
					vim.log.levels.WARN
				)

				local config = require("gtask.config")
				if item.task.completed then
					-- Completed task deleted from Google
					if config.sync.keep_completed_in_markdown then
						-- Remove from mapping but keep in markdown
						-- This prevents the task from being re-synced to Google
						mapping.remove_task(map, item.uuid)
						utils.notify(
							string.format("Completed task deleted from Google (kept in markdown): %s", item.task.title),
							vim.log.levels.INFO
						)
					else
						-- Delete from markdown too
						table.insert(operations.delete_from_markdown, {
							task_key = item.uuid,
							file_path = item.task.source_file_path,
							title = item.task.title,
						})
					end
				else
					-- Incomplete task deleted from Google - delete from markdown
					table.insert(operations.delete_from_markdown, {
						task_key = item.uuid,
						file_path = item.task.source_file_path,
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
				uuid = item.uuid,
				task_index = item.task_index,
				parent_uuid = parent_uuid,
			})
		end
	end

	-- Find Google tasks that haven't been processed yet (new tasks from Google)
	-- These will be written to markdown files
	for _, gtask in ipairs(google_tasks) do
		if not seen_google_ids[gtask.id] then
			table.insert(operations.to_markdown, gtask)
		end
	end

	-- Queue deletions for tasks that were removed from markdown
	-- These tasks exist in our mapping but no longer in the markdown file
	for _, deleted_item in ipairs(deleted_from_markdown) do
		table.insert(operations.delete_from_google, {
			google_id = deleted_item.google_id,
			task_key = deleted_item.uuid,
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
		return type(op) == "table" and op.type == "update_from_google"
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
	M.execute_twoway_sync(
		operations,
		task_list_id,
		markdown_dir,
		list_name,
		map,
		md_task_uuids,
		markdown_tasks,
		tasks_needing_uuids,
		callback
	)
end

---Executes 2-way sync operations with two-pass creation for parent-child relationships
---
---The two-pass approach ensures subtasks can reference their parent's Google Task ID:
---  1. Create all top-level tasks first and store their IDs
---  2. Create subtasks using parent IDs from step 1
---
---@param operations table Operations to perform
---@param task_list_id string Google Tasks list ID
---@param markdown_dir string Markdown directory path
---@param list_name string Name of the task list
---@param map table Mapping data
---@param md_task_uuids table Array of current markdown task UUIDs
---@param markdown_tasks table Array of markdown tasks for this list
---@param tasks_needing_uuids table Array of tasks that need UUIDs embedded
---@param callback function Callback when complete
function M.execute_twoway_sync(
	operations,
	task_list_id,
	markdown_dir,
	list_name,
	map,
	md_task_uuids,
	markdown_tasks,
	tasks_needing_uuids,
	callback
)
	-- Categorize operations: updates, top-level creates, and subtask creates
	-- Subtasks must be created after their parents to get proper parent IDs
	local updates = {}
	local creates_toplevel = {}
	local creates_subtasks = {}

	for _, op in ipairs(operations.to_google) do
		if op.type == "update" then
			table.insert(updates, op)
		elseif op.type == "create" then
			if op.markdown_task.parent_index then
				-- Subtask - needs parent ID, create in phase 2
				table.insert(creates_subtasks, op)
			else
				-- Top-level task - create in phase 1
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
	-- Maps markdown task array index to its Google Task ID (for parent-child linking)
	local task_id_map = {}

	-- Pre-populate task_id_map with existing tasks (so subtasks can find their parents)
	for i, task in ipairs(markdown_tasks) do
		local task_uuid = task.uuid
		if task_uuid then
			local mapping_data = map.tasks[task_uuid]
			if mapping_data and mapping_data.google_id then
				task_id_map[i] = mapping_data.google_id
			end
		end
	end

	-- Callback invoked after each async operation completes
	local function op_complete(success, err_msg)
		completed = completed + 1
		if not success and err_msg then
			table.insert(errors, err_msg)
		end

		-- All operations complete - cleanup and finalize
		if completed >= total_ops then
			-- Remove stale mappings for tasks that no longer exist in this list
			local removed_count = mapping.cleanup_orphaned_tasks(map, list_name, md_task_uuids)
			if removed_count > 0 then
				utils.notify(
					string.format("Cleaned up %d orphaned task mapping(s)", removed_count),
					vim.log.levels.INFO
				)
			end

			-- Embed UUIDs for tasks that were created without them
			if #tasks_needing_uuids > 0 then
				utils.notify(
					string.format("Embedding %d UUID(s) in markdown files...", #tasks_needing_uuids),
					vim.log.levels.INFO
				)

				-- Group tasks by file to minimize file operations
				local tasks_by_file = {}
				for _, task_info in ipairs(tasks_needing_uuids) do
					if not tasks_by_file[task_info.file_path] then
						tasks_by_file[task_info.file_path] = {}
					end
					table.insert(tasks_by_file[task_info.file_path], task_info)
				end

				-- Embed UUIDs file by file
				local embedding_errors = {}
				for file_path, file_tasks in pairs(tasks_by_file) do
					-- Sort by line number descending (embed from bottom to top to preserve line numbers)
					table.sort(file_tasks, function(a, b)
						return a.line_number > b.line_number
					end)

					for _, task_info in ipairs(file_tasks) do
						embed_task_uuid(file_path, task_info.line_number, task_info.uuid, function(success, err_msg)
							if not success and err_msg then
								table.insert(embedding_errors, err_msg)
							end
						end)
					end
				end

				if #embedding_errors > 0 then
					utils.notify(
						"UUID embedding completed with errors: " .. table.concat(embedding_errors, ", "),
						vim.log.levels.WARN
					)
				end
			end

			-- Note: Final mapping.save() happens in sync_multiple_lists after all lists sync

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
					op.uuid,
					op.google_task.id,
					list_name,
					file_path,
					
					op.parent_uuid,
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
	-- Group deletions by file and sort by position path (deeper positions first)
	local deletions_by_file = {}
	for _, del_op in ipairs(operations.delete_from_markdown) do
		local file_path = del_op.file_path
		if not deletions_by_file[file_path] then
			deletions_by_file[file_path] = {}
		end
		table.insert(deletions_by_file[file_path], del_op)
	end

	-- Process deletions sequentially for each file
	for file_path, file_deletions in pairs(deletions_by_file) do
		-- Process deletions sequentially for this file
		local function delete_next(index)
			if index > #file_deletions then
				return -- Done with this file
			end

			local del_op = file_deletions[index]
			M.delete_task_by_uuid(del_op.file_path, del_op.task_key, function(success, err_msg)
				if success then
					-- Remove from mapping
					mapping.remove_task(map, del_op.task_key)
					utils.notify(string.format("Deleted task from markdown: %s", del_op.title), vim.log.levels.INFO)
				end
				op_complete(success, err_msg)

				-- Process next deletion for this file
				delete_next(index + 1)
			end)
		end

		-- Start sequential deletion for this file
		delete_next(1)
	end

	-- Note: If no deletions, the loop above won't execute (no operations)

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
						op.uuid,
						created_task.id,
						list_name,
						file_path,
						
						nil, -- parent_uuid is nil for top-level tasks
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
										subop.uuid,
										sub_created_task.id,
										list_name,
										sub_file_path,
										subop.parent_uuid,
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
							subop.uuid,
							sub_created_task.id,
							list_name,
							sub_file_path,
							subop.parent_uuid,
							sub_created_task.updated
						)
					end
					op_complete(sub_success, sub_err_msg)
				end
			)
		end
	end

	-- Phase 4: Sync to markdown
	-- Separate new tasks from field updates
	local new_tasks_to_markdown = {}
	local field_updates = {}

	for _, op in ipairs(operations.to_markdown) do
		if type(op) == "table" and op.type == "update_from_google" then
			table.insert(field_updates, op)
		else
			table.insert(new_tasks_to_markdown, op)
		end
	end

	-- Phase 4a: Write new tasks to markdown (single operation for all new tasks)
	if #new_tasks_to_markdown > 0 then
		-- Determine target file path: use existing file path if list has markdown tasks
		local target_file_path = nil
		if #markdown_tasks > 0 and markdown_tasks[1].source_file_path then
			target_file_path = markdown_tasks[1].source_file_path
		end

		M.write_google_tasks_to_markdown(
			new_tasks_to_markdown,
			markdown_dir,
			list_name,
			target_file_path,
			function(success)
				op_complete(success, success and nil or "Failed to write tasks to markdown")
			end
		)
	end

	-- Phase 4b: Update tasks in markdown from Google (individual operations)
	for _, update_op in ipairs(field_updates) do
		M.update_task_from_google_by_uuid(
			update_op.file_path,
			update_op.task_key,
			update_op.google_task,
			update_op.markdown_task,
			function(success, err_msg)
				if success then
					-- Update mapping with new Google timestamp
					local mapping_data = map.tasks[update_op.task_key]
					if mapping_data then
						mapping_data.google_updated = update_op.google_task.updated or os.date("!%Y-%m-%dT%H:%M:%SZ")
						mapping_data.last_synced = os.date("!%Y-%m-%dT%H:%M:%SZ")
					end
					utils.notify(
						string.format("Updated task from Google: %s", update_op.google_task.title),
						vim.log.levels.INFO
					)
				end
				op_complete(success, err_msg)
			end
		)
	end
end

---Helper function to convert a Google Task to markdown lines with proper indentation
---@param gtask table Google Task object
---@param indent_level number Number of indentation levels (0 for top-level, 1 for first-level subtasks, etc.)
---@return table Array of markdown lines for this task
local function google_task_to_markdown_lines(gtask, indent_level)
	local lines = {}
	local indent = string.rep("  ", indent_level) -- 2 spaces per level

	-- Build task line
	local checkbox = gtask.status == "completed" and "x" or " "
	local task_line = indent .. string.format("- [%s] %s", checkbox, gtask.title)

	-- Add due date if present (convert from RFC3339 to YYYY-MM-DD HH:MM or YYYY-MM-DD)
	if gtask.due and gtask.due ~= "" then
		-- RFC3339 format: "2025-01-15T14:30:00.000Z"
		-- Note: Google Tasks API only stores dates, not times (time is always 00:00:00.000Z)
		local date_part, time_part = gtask.due:match("(%d%d%d%d%-%d%d%-%d%d)T(%d%d:%d%d)")
		if date_part then
			task_line = task_line .. " | " .. date_part
			-- Only add time if it's not midnight (00:00)
			if time_part and time_part ~= "00:00" then
				task_line = task_line .. " " .. time_part
			end
		end
	end

	table.insert(lines, task_line)

	-- Add UUID comment for stable task identification
	-- Generate UUID for this task if coming from Google
	local uuid = generate_uuid()
	table.insert(lines, indent .. "<!-- gtask:" .. uuid .. " -->")

	-- Add description/notes if present
	if gtask.notes and gtask.notes ~= "" then
		-- Add blank line before description
		table.insert(lines, "")
		for line in gtask.notes:gmatch("[^\n]+") do
			table.insert(lines, indent .. "  " .. line)
		end
	end

	return lines
end

---Recursively write a task and its subtasks to markdown
---@param gtask table Google Task object
---@param children_by_parent table Map of parent_id -> array of child tasks
---@param existing_by_title table Set of existing task titles (normalized)
---@param existing_google_ids table Set of Google task IDs already in mapping
---@param indent_level number Current indentation level
---@param output_lines table Array to append lines to
---@return number Count of new tasks written
local function write_task_and_children(
	gtask,
	children_by_parent,
	existing_by_title,
	existing_google_ids,
	indent_level,
	output_lines
)
	local count = 0

	-- Normalize title for comparison (trim whitespace)
	local normalized_title = gtask.title:match("^%s*(.-)%s*$")

	-- Write this task if it doesn't already exist (by title OR by Google ID in mapping)
	if not existing_by_title[normalized_title] and not existing_google_ids[gtask.id] then
		local task_lines = google_task_to_markdown_lines(gtask, indent_level)
		for _, line in ipairs(task_lines) do
			table.insert(output_lines, line)
		end
		count = count + 1
	end

	-- Write children (subtasks)
	local children = children_by_parent[gtask.id] or {}
	for _, child in ipairs(children) do
		count = count
			+ write_task_and_children(
				child,
				children_by_parent,
				existing_by_title,
				existing_google_ids,
				indent_level + 1,
				output_lines
			)
	end

	return count
end

---Writes Google Tasks to markdown file
---@param tasks table[] Array of Google Tasks to write
---@param markdown_dir string Directory to write to
---@param list_name string Name of the task list
---@param existing_file_path string|nil Existing file path for this list (if any)
---@param callback function Callback when complete
function M.write_google_tasks_to_markdown(tasks, markdown_dir, list_name, existing_file_path, callback)
	-- Use existing file path if provided, otherwise create at root with normalized name
	local filename
	if existing_file_path and existing_file_path ~= "" then
		filename = existing_file_path
	else
		local normalized_name = normalize_filename(list_name)
		filename = markdown_dir .. "/" .. normalized_name .. ".md"
	end

	-- Load mapping to check if Google task IDs are already synced
	local map = mapping.load()
	local existing_google_ids = {}
	for _, mapping_data in pairs(map.tasks) do
		if mapping_data.list_name == list_name and mapping_data.google_id then
			existing_google_ids[mapping_data.google_id] = true
		end
	end

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
		-- Normalize title for comparison (trim whitespace)
		local normalized_title = task.title:match("^%s*(.-)%s*$")
		existing_by_title[normalized_title] = true
	end

	-- Build parent-child hierarchy from Google Tasks
	local top_level_tasks = {}
	local children_by_parent = {}

	for _, gtask in ipairs(tasks) do
		if gtask.parent and gtask.parent ~= "" then
			-- This is a subtask
			if not children_by_parent[gtask.parent] then
				children_by_parent[gtask.parent] = {}
			end
			table.insert(children_by_parent[gtask.parent], gtask)
		else
			-- Top-level task
			table.insert(top_level_tasks, gtask)
		end
	end

	-- Convert tasks to markdown format (hierarchically)
	local new_task_lines = {}
	local new_task_count = 0

	for _, gtask in ipairs(top_level_tasks) do
		new_task_count = new_task_count
			+ write_task_and_children(
				gtask,
				children_by_parent,
				existing_by_title,
				existing_google_ids,
				0,
				new_task_lines
			)
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

---Updates the completion status of a task in markdown by line number (internal helper, prefer update_task_completion_by_position)
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

---Helper function to find a task by UUID in a file
---@param file_path string Path to the markdown file
---@param uuid string Task UUID
---@return table|nil task The found task with its line number, or nil if not found
---@return table|nil lines All lines from the file
local function find_task_by_uuid(file_path, uuid)
	local file = io.open(file_path, "r")
	if not file then
		return nil, nil
	end

	local lines = {}
	for line in file:lines() do
		table.insert(lines, line)
	end
	file:close()

	local tasks = parser.parse_tasks(lines)
	for _, task in ipairs(tasks) do
		if task.uuid == uuid then
			return task, lines
		end
	end

	return nil, lines
end

---Updates a task from Google Tasks data (UUID-based)
---@param file_path string Path to the markdown file
---@param uuid string Task UUID
---@param google_task table Google Task data
---@param markdown_task table Markdown task data (for comparison)
---@param callback function Callback when complete (success, err_msg)
function M.update_task_from_google_by_uuid(file_path, uuid, google_task, markdown_task, callback)
	local target_task, lines = find_task_by_uuid(file_path, uuid)

	if not target_task then
		if callback then
			callback(false, string.format("Task with UUID %s not found in %s", uuid, file_path))
		end
		return
	end

	-- Build updated task line from Google Task data
	local indent = string.rep("\t", target_task.indent_level or 0)
	local checkbox = google_task.status == "completed" and "[x]" or "[ ]"
	local title = google_task.title or target_task.title

	-- Add due date if present (convert from RFC3339 to YYYY-MM-DD HH:MM or YYYY-MM-DD)
	local due_str = ""
	if google_task.due and google_task.due ~= "" then
		local date_part, time_part = google_task.due:match("(%d%d%d%d%-%d%d%-%d%d)T(%d%d:%d%d)")
		if date_part then
			due_str = " | " .. date_part
			if time_part and time_part ~= "00:00" then
				due_str = due_str .. " " .. time_part
			end
		end
	end

	local new_task_line = indent .. "- " .. checkbox .. " " .. title .. due_str

	-- Update the task line
	lines[target_task.line_number] = new_task_line

	-- Handle description update
	local description = google_task.notes or ""

	-- Find and remove old description lines
	local desc_start = target_task.line_number + 1

	-- Skip UUID comment if present
	if desc_start <= #lines and lines[desc_start]:match("^%s*<!%-%-%s*gtask:") then
		desc_start = desc_start + 1
	end

	local desc_end = desc_start - 1

	-- Find the end of the current description
	for i = desc_start, #lines do
		local line = lines[i]
		if line:match("^%s*%-%s+%[") then
			break
		elseif line:match("^%s*$") then
			desc_end = i
		elseif line:match("^%s+%S") then
			desc_end = i
		else
			break
		end
	end

	-- Remove old description lines
	if desc_end >= desc_start then
		for i = desc_end, desc_start, -1 do
			table.remove(lines, i)
		end
	end

	-- Insert new description if present
	if description ~= "" then
		local desc_indent = indent .. "  "
		local desc_lines = vim.split(description, "\n", { plain = true })

		-- Calculate insertion point (after task line and UUID comment if present)
		local insert_pos = target_task.line_number + 1
		if insert_pos <= #lines and lines[insert_pos]:match("^%s*<!%-%-%s*gtask:") then
			insert_pos = insert_pos + 1
		end

		-- Insert blank line before description
		table.insert(lines, insert_pos, "")

		-- Insert description lines
		for i, desc_line in ipairs(desc_lines) do
			if desc_line ~= "" then
				table.insert(lines, insert_pos + i, desc_indent .. desc_line)
			else
				table.insert(lines, insert_pos + i, "")
			end
		end
	end

	-- Write back to file
	local write_file = io.open(file_path, "w")
	if not write_file then
		if callback then
			callback(false, "Failed to open file for writing: " .. file_path)
		end
		return
	end

	for _, line in ipairs(lines) do
		write_file:write(line .. "\n")
	end
	write_file:close()

	if callback then
		callback(true, nil)
	end
end

---Deletes a task from markdown by UUID
---@param file_path string Path to the markdown file
---@param uuid string Task UUID
---@param callback function Callback (success, err_msg)
function M.delete_task_by_uuid(file_path, uuid, callback)
	local target_task, lines = find_task_by_uuid(file_path, uuid)

	if not target_task then
		if callback then
			callback(false, string.format("Task with UUID %s not found in %s", uuid, file_path))
		end
		return
	end

	-- Delete by the current line number
	M.delete_task_from_markdown(file_path, target_task.line_number, callback)
end

---DEPRECATED: Updates the completion status of a task in markdown by position path
---Use UUID-based functions instead
---@param file_path string Path to the markdown file
---@param position_path string Tree-based position path (e.g., "[0]", "[2][1]")
---@param completed boolean New completion status
---@param callback function Callback when complete (success, err_msg)
function M.update_task_completion_by_position(file_path, position_path, completed, callback)
	-- Re-parse the file to get current task positions
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

	-- Parse tasks to find the one with matching position_path
	local tasks = parser.parse_tasks(lines)
	local target_task = nil

	for _, task in ipairs(tasks) do
		if task.position_path == position_path then
			target_task = task
			break
		end
	end

	if not target_task then
		if callback then
			callback(false, string.format("Task with position %s not found in %s", position_path, file_path))
		end
		return
	end

	-- Now update using the current line number
	M.update_task_completion_in_markdown(file_path, target_task.line_number, completed, callback)
end

---Updates all fields of a task in markdown from Google Task data (bidirectional sync)
---@param file_path string Path to the markdown file
---@param position_path string Tree-based position path (e.g., "[0]", "[2][1]")
---@param google_task table Google Task object with updated data
---@param markdown_task table Current markdown task (for reference)
---@param callback function Callback (success, err_msg)
function M.update_task_from_google(file_path, position_path, google_task, markdown_task, callback)
	-- Re-parse the file to get current task positions
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

	-- Parse tasks to find the one with matching position_path
	local tasks = parser.parse_tasks(lines)
	local target_task = nil

	for _, task in ipairs(tasks) do
		if task.position_path == position_path then
			target_task = task
			break
		end
	end

	if not target_task then
		if callback then
			callback(false, string.format("Task with position %s not found in %s", position_path, file_path))
		end
		return
	end

	-- Build updated task line from Google Task data
	local indent = string.rep("\t", target_task.indent_level or 0)
	local checkbox = google_task.status == "completed" and "[x]" or "[ ]"
	local title = google_task.title or target_task.title

	-- Add due date if present (convert from RFC3339 to YYYY-MM-DD HH:MM or YYYY-MM-DD)
	local due_str = ""
	if google_task.due and google_task.due ~= "" then
		-- RFC3339 format: "2025-01-15T14:30:00.000Z"
		-- Note: Google Tasks API only stores dates, not times (time is always 00:00:00.000Z)
		local date_part, time_part = google_task.due:match("(%d%d%d%d%-%d%d%-%d%d)T(%d%d:%d%d)")
		if date_part then
			due_str = " | " .. date_part
			-- Only add time if it's not midnight (00:00)
			if time_part and time_part ~= "00:00" then
				due_str = due_str .. " " .. time_part
			end
		end
	end

	local new_task_line = indent .. "- " .. checkbox .. " " .. title .. due_str

	-- Update the task line
	lines[target_task.line_number] = new_task_line

	-- Handle description update
	local description = google_task.notes or ""

	-- Find and remove old description lines
	local desc_start = target_task.line_number + 1

	-- Skip UUID comment if present
	if desc_start <= #lines and lines[desc_start]:match("^%s*<!%-%-%s*gtask:") then
		desc_start = desc_start + 1
	end

	local desc_end = desc_start - 1

	-- Find the end of the current description
	for i = desc_start, #lines do
		local line = lines[i]
		-- Stop if we hit another task, or a line with less/equal indentation that's not a description
		if line:match("^%s*%-%s+%[") then
			break -- Hit another task
		elseif line:match("^%s*$") then
			-- Empty line might be part of description or separator
			desc_end = i
		elseif line:match("^%s+%S") then
			-- Indented content - part of description
			desc_end = i
		else
			break -- Non-indented content, stop
		end
	end

	-- Remove old description lines
	if desc_end >= desc_start then
		for i = desc_end, desc_start, -1 do
			table.remove(lines, i)
		end
	end

	-- Insert new description if present
	if description ~= "" then
		local desc_indent = indent .. "  "
		local desc_lines = vim.split(description, "\n", { plain = true })

		-- Calculate insertion point (after task line and UUID comment if present)
		local insert_pos = target_task.line_number + 1
		if insert_pos <= #lines and lines[insert_pos]:match("^%s*<!%-%-%s*gtask:") then
			insert_pos = insert_pos + 1
		end

		-- Insert blank line before description
		table.insert(lines, insert_pos, "")

		-- Insert description lines
		for i, desc_line in ipairs(desc_lines) do
			if desc_line ~= "" then
				table.insert(lines, insert_pos + i, desc_indent .. desc_line)
			else
				table.insert(lines, insert_pos + i, "")
			end
		end
	end

	-- Write back to file
	local write_file = io.open(file_path, "w")
	if not write_file then
		if callback then
			callback(false, "Failed to open file for writing: " .. file_path)
		end
		return
	end

	for _, line in ipairs(lines) do
		write_file:write(line .. "\n")
	end
	write_file:close()

	if callback then
		callback(true, nil)
	end
end

---Deletes a task from markdown by position path (more reliable than line number)
---@param file_path string Path to the markdown file
---@param position_path string Tree-based position path (e.g., "[0]", "[2][1]")
---@param callback function Callback (success, err_msg)
function M.delete_task_by_position(file_path, position_path, callback)
	-- Re-parse the file to get current task positions
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

	-- Parse tasks to find the one with matching position_path
	local tasks = parser.parse_tasks(lines)
	local target_task = nil

	for _, task in ipairs(tasks) do
		if task.position_path == position_path then
			target_task = task
			break
		end
	end

	if not target_task then
		if callback then
			callback(false, string.format("Task with position %s not found in %s", position_path, file_path))
		end
		return
	end

	-- Now delete by the current line number
	M.delete_task_from_markdown(file_path, target_task.line_number, callback)
end

---Deletes a task from markdown by line number (legacy, prefer delete_task_by_position)
---@param file_path string Path to the markdown file
---@param line_number number Line number of the task
---@param callback function Callback (success, err_msg)
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
	-- Check if sync is already in progress
	if sync_in_progress then
		utils.notify("Sync already in progress. Please wait for it to complete.", vim.log.levels.WARN)
		if callback then
			callback(false)
		end
		return
	end

	-- Set sync lock
	sync_in_progress = true

	-- Validate directory configuration
	local valid, err = files.validate_markdown_dir()
	if not valid then
		sync_in_progress = false
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
			sync_in_progress = false
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
		sync_in_progress = false
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

			-- Reset sync lock
			sync_in_progress = false

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
