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
			tasks = {}, -- task_key -> {google_id, list_name, file_path, position_path, parent_key, google_updated, deleted_from_google, last_synced}
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

--- Generate a tree-position-based key for a task
--- Uses hierarchical position path for stable tracking resilient to line changes
---@param list_name string The task list name
---@param file_path string The file path
---@param position_path string The tree position (e.g., "[0]" or "[0].[1].[2]")
---@return string A tree-position-based key for this task
function M.generate_task_key(list_name, file_path, position_path)
	-- Create identifier based on tree position
	-- Format: list_name|file_path:[pos].[pos]...
	return string.format("%s|%s:%s", list_name, file_path, position_path)
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
---@param task_key string The task key
---@param google_id string The Google Task ID
---@param list_name string The list name
---@param file_path string The file path
---@param position_path string The tree position path
---@param parent_key string|nil The parent task key if this is a subtask
---@param google_updated string|nil The Google Task's last update timestamp (RFC3339)
function M.register_task(mapping, task_key, google_id, list_name, file_path, position_path, parent_key, google_updated)
	local now = os.date("!%Y-%m-%dT%H:%M:%SZ")
	mapping.tasks[task_key] = {
		google_id = google_id,
		list_name = list_name,
		file_path = file_path,
		position_path = position_path,
		parent_key = parent_key,
		google_updated = google_updated or now,  -- Use provided timestamp or current time
		deleted_from_google = false,
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
---@param task_key string The task key to remove
function M.remove_task(mapping, task_key)
	mapping.tasks[task_key] = nil
end

--- Mark a task as deleted from Google Tasks
---@param mapping table The mapping data
---@param task_key string The task key
function M.mark_deleted_from_google(mapping, task_key)
	local task_data = mapping.tasks[task_key]
	if task_data then
		task_data.deleted_from_google = true
		task_data.last_synced = os.date("!%Y-%m-%dT%H:%M:%SZ")
	end
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

return M
