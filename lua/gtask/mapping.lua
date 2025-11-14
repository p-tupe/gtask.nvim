---@class GtaskMapping
---Manages the mapping between markdown tasks and Google Task IDs
local M = {}

local utils = require("gtask.utils")

--- Get the path to the mapping file
---@return string Path to the mapping file
local function get_mapping_file_path()
	local data_dir = vim.fn.stdpath("data")
	return data_dir .. "/gtask_mappings.json"
end

--- Load the mapping data from disk
---@return table The mapping data structure
function M.load()
	local file_path = get_mapping_file_path()
	local file = io.open(file_path, "r")

	if not file then
		-- File doesn't exist, return empty structure
		return {
			lists = {}, -- list_name -> google_list_id
			tasks = {}, -- uuid -> {google_id, list_name, file_path, parent_uuid, google_updated, last_synced}
		}
	end

	local content = file:read("*all")
	file:close()

	if content == "" then
		return {
			lists = {},
			tasks = {},
		}
	end

	local success, decoded = pcall(vim.fn.json_decode, content)
	if not success then
		utils.notify("Warning: Failed to parse mapping file, creating new one", vim.log.levels.WARN)
		return {
			lists = {},
			tasks = {},
		}
	end

	-- Ensure structure exists
	decoded.lists = decoded.lists or {}
	decoded.tasks = decoded.tasks or {}

	-- Check for old format and migrate if needed
	if M.is_old_format(decoded) then
		decoded = M.migrate_to_uuid_format(decoded)
		-- Save migrated format immediately
		M.save(decoded)
	end

	return decoded
end

--- Save the mapping data to disk
---@param mapping table The mapping data to save
function M.save(mapping)
	local file_path = get_mapping_file_path()
	local file = io.open(file_path, "w")

	if not file then
		utils.notify("Error: Failed to open mapping file for writing", vim.log.levels.ERROR)
		return false
	end

	local success, encoded = pcall(vim.fn.json_encode, mapping)
	if not success then
		utils.notify("Error: Failed to encode mapping data", vim.log.levels.ERROR)
		file:close()
		return false
	end

	file:write(encoded)
	file:close()

	return true
end

--- Generate a UUID-based key for a task
--- The UUID is extracted from the markdown file and serves as the stable identifier
---@param uuid string The task's UUID (from <!-- gtask:uuid --> comment)
---@return string The UUID itself (used as the mapping key)
function M.generate_task_key(uuid)
	-- UUID is the key - simple and stable across renames, moves, reorders
	return uuid
end

--- Get Google ID for a task
---@param mapping table The mapping data
---@param task_key string The task key
---@return string|nil The Google Task ID if found
function M.get_google_id(mapping, task_key)
	local task_data = mapping.tasks[task_key]
	if task_data then
		return task_data.google_id
	end
	return nil
end

--- Get Google List ID for a list
---@param mapping table The mapping data
---@param list_name string The list name
---@return string|nil The Google List ID if found
function M.get_list_id(mapping, list_name)
	return mapping.lists[list_name]
end

--- Set Google List ID for a list
---@param mapping table The mapping data
---@param list_name string The list name
---@param google_list_id string The Google List ID
function M.set_list_id(mapping, list_name, google_list_id)
	mapping.lists[list_name] = google_list_id
end

--- Register a task mapping
---@param mapping table The mapping data
---@param uuid string The task's UUID (used as the key)
---@param google_id string The Google Task ID
---@param list_name string The list name
---@param file_path string The file path
---@param parent_uuid string|nil The parent task's UUID if this is a subtask
---@param google_updated string|nil The Google Task's last update timestamp (RFC3339)
function M.register_task(mapping, uuid, google_id, list_name, file_path, parent_uuid, google_updated)
	local now = os.date("!%Y-%m-%dT%H:%M:%SZ")
	mapping.tasks[uuid] = {
		google_id = google_id,
		list_name = list_name,
		file_path = file_path,
		parent_uuid = parent_uuid,
		google_updated = google_updated or now, -- Use provided timestamp or current time
		last_synced = now,
	}
end

--- Find task key by Google ID
---@param mapping table The mapping data
---@param google_id string The Google Task ID
---@return string|nil The task key if found
function M.find_task_key_by_google_id(mapping, google_id)
	for key, data in pairs(mapping.tasks) do
		if data.google_id == google_id then
			return key
		end
	end
	return nil
end

--- Remove task from mapping
---@param mapping table The mapping data
---@param uuid string The task's UUID
function M.remove_task(mapping, uuid)
	mapping.tasks[uuid] = nil
end

--- Clean up orphaned tasks for a specific list
--- Removes tasks that no longer exist in markdown
---@param mapping table The mapping data
---@param list_name string The list name
---@param current_task_keys table Array of current task keys from markdown
function M.cleanup_orphaned_tasks(mapping, list_name, current_task_keys)
	local current_keys_set = {}
	for _, key in ipairs(current_task_keys) do
		current_keys_set[key] = true
	end

	local to_remove = {}
	for key, data in pairs(mapping.tasks) do
		if data.list_name == list_name and not current_keys_set[key] then
			table.insert(to_remove, key)
		end
	end

	for _, key in ipairs(to_remove) do
		mapping.tasks[key] = nil
	end

	return #to_remove
end

--- Check if mapping file uses old position-based format
---@param mapping table The mapping data
---@return boolean True if old format detected
function M.is_old_format(mapping)
	-- Check if any task has position_path field (old format)
	for _, task_data in pairs(mapping.tasks) do
		if task_data.position_path then
			return true
		end
	end
	return false
end

--- Migrate old position-based mapping to UUID format
--- This is a one-time migration for existing users
---@param old_mapping table The old mapping data
---@return table The migrated mapping with UUID keys
function M.migrate_to_uuid_format(old_mapping)
	utils.notify("Migrating mapping file from position-based to UUID format...", vim.log.levels.INFO)

	-- Backup old mapping
	local backup_path = get_mapping_file_path() .. ".backup"
	local backup_file = io.open(backup_path, "w")
	if backup_file then
		local encoded = vim.fn.json_encode(old_mapping)
		backup_file:write(encoded)
		backup_file:close()
		utils.notify("Created backup at: " .. backup_path, vim.log.levels.INFO)
	end

	-- Create new mapping with UUID-based structure
	local new_mapping = {
		lists = old_mapping.lists or {}, -- Lists remain the same
		tasks = {}, -- Will be empty - UUIDs will be generated on next sync
	}

	-- We can't migrate tasks because we don't have UUIDs for them yet
	-- The next sync will:
	-- 1. Generate UUIDs for all tasks
	-- 2. Use title-based fallback matching to reconnect with Google Task IDs
	-- 3. Create new UUID-based mappings

	utils.notify(
		"Migration complete. All tasks will be re-matched on next sync using title-based matching.",
		vim.log.levels.WARN
	)

	return new_mapping
end

return M
