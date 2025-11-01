---@class GtaskMapping
---Manages the mapping between markdown tasks and Google Task IDs
local M = {}

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
			tasks = {}, -- task_key -> {google_id, list_name, title, file_path, line_number, parent_key, context_sig}
			context_index = {}, -- context_sig -> task_key (for fuzzy matching)
		}
	end

	local content = file:read("*all")
	file:close()

	if content == "" then
		return {
			lists = {},
			tasks = {},
			context_index = {},
		}
	end

	local success, decoded = pcall(vim.fn.json_decode, content)
	if not success then
		vim.notify("Warning: Failed to parse mapping file, creating new one", vim.log.levels.WARN)
		return {
			lists = {},
			tasks = {},
		}
	end

	-- Ensure structure exists
	decoded.lists = decoded.lists or {}
	decoded.tasks = decoded.tasks or {}
	decoded.context_index = decoded.context_index or {}

	return decoded
end

--- Save the mapping data to disk
---@param mapping table The mapping data to save
function M.save(mapping)
	local file_path = get_mapping_file_path()
	local file = io.open(file_path, "w")

	if not file then
		vim.notify("Error: Failed to open mapping file for writing", vim.log.levels.ERROR)
		return false
	end

	local success, encoded = pcall(vim.fn.json_encode, mapping)
	if not success then
		vim.notify("Error: Failed to encode mapping data", vim.log.levels.ERROR)
		file:close()
		return false
	end

	file:write(encoded)
	file:close()

	return true
end

--- Generate a position-based key for a task
--- Uses file path and line numbers for stable tracking
---@param list_name string The task list name
---@param file_path string The file path
---@param line_number integer The line number where task appears
---@param parent_line_number integer|nil The parent's line number if this is a subtask
---@return string A position-based key for this task
function M.generate_task_key(list_name, file_path, line_number, parent_line_number)
	-- Create identifier based on position in file
	-- Format: list_name|file_path:line_number:parent_line
	local parent_suffix = parent_line_number and tostring(parent_line_number) or "top"
	return string.format("%s|%s:%d:%s", list_name, file_path, line_number, parent_suffix)
end

--- Generate a context signature for fuzzy matching
--- This is used when position-based key doesn't match
---@param list_name string The task list name
---@param task_title string The task title
---@param parent_title string|nil The parent task title if this is a subtask
---@return string A context signature for fuzzy matching
function M.generate_context_signature(list_name, task_title, parent_title)
	-- Create identifier based on content context
	-- Format: list_name||parent_title||task_title
	return string.format("%s||%s||%s", list_name, parent_title or "", task_title)
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
---@param title string The task title
---@param file_path string The file path
---@param line_number integer The line number
---@param parent_key string|nil The parent task key if this is a subtask
---@param context_sig string The context signature for fuzzy matching
function M.register_task(mapping, task_key, google_id, list_name, title, file_path, line_number, parent_key, context_sig)
	-- Ensure context_index exists
	if not mapping.context_index then
		mapping.context_index = {}
	end

	mapping.tasks[task_key] = {
		google_id = google_id,
		list_name = list_name,
		title = title,
		file_path = file_path,
		line_number = line_number,
		parent_key = parent_key,
		context_sig = context_sig,
		last_synced = os.date("!%Y-%m-%dT%H:%M:%SZ"),
	}

	-- Update context index for fuzzy matching
	mapping.context_index[context_sig] = task_key
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
	local task_data = mapping.tasks[task_key]
	if task_data and task_data.context_sig then
		-- Remove from context index
		if mapping.context_index then
			mapping.context_index[task_data.context_sig] = nil
		end
	end
	mapping.tasks[task_key] = nil
end

--- Find task by context signature
---@param mapping table The mapping data
---@param context_sig string The context signature
---@return string|nil task_key The task key if found
---@return table|nil task_data The task data if found
function M.find_by_context(mapping, context_sig)
	if not mapping.context_index then
		return nil, nil
	end

	local task_key = mapping.context_index[context_sig]
	if task_key then
		return task_key, mapping.tasks[task_key]
	end
	return nil, nil
end

--- Find task by nearby position (within range of expected line number)
---@param mapping table The mapping data
---@param list_name string The list name
---@param file_path string The file path
---@param line_number integer The expected line number
---@param parent_line_number integer|nil The parent's line number
---@param range integer The search range (default 5)
---@return string|nil task_key The task key if found
---@return table|nil task_data The task data if found
---@return integer|nil offset The line offset from expected position
function M.find_nearby(mapping, list_name, file_path, line_number, parent_line_number, range)
	range = range or 5
	local parent_suffix = parent_line_number and tostring(parent_line_number) or "top"

	-- Try positions within range
	for offset = -range, range do
		local search_line = line_number + offset
		if search_line > 0 then -- Line numbers must be positive
			local search_key = string.format("%s|%s:%d:%s", list_name, file_path, search_line, parent_suffix)
			local task_data = mapping.tasks[search_key]
			if task_data then
				return search_key, task_data, offset
			end
		end
	end

	return nil, nil, nil
end

--- Update task position after detecting it moved
---@param mapping table The mapping data
---@param old_key string The old task key
---@param new_key string The new task key
---@param new_line_number integer The new line number
function M.update_task_position(mapping, old_key, new_key, new_line_number)
	local task_data = mapping.tasks[old_key]
	if not task_data then
		return false
	end

	-- Update task data
	task_data.line_number = new_line_number

	-- Move to new key
	mapping.tasks[new_key] = task_data
	mapping.tasks[old_key] = nil

	-- Update context index to point to new key
	if mapping.context_index and task_data.context_sig then
		mapping.context_index[task_data.context_sig] = new_key
	end

	return true
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
