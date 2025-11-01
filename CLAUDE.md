# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Gtask.nvim is a Neovim plugin that integrates Google Tasks into the editor.

### Design Philosophy

The plugin is designed to embed tasks directly within markdown notes rather than as a separate interface. Key pain points addressed:

1. **Better Description Formatting**: Google Tasks' description field is cumbersome. This plugin treats descriptions as markdown content blocks with proper formatting.
2. **Hierarchical Subtask Display**: When viewing tasks by due date, subtasks stay grouped under their parent tasks instead of being scattered by their individual due dates.

### Markdown Task Format

Tasks use standard markdown checkbox syntax with specific indentation rules:

```markdown
# Task List Name <-- H1 heading becomes Google Tasks list name

- [ ] Task title | 2025-01-15 <-- Task with due date
- [ ] Another task | 2025-01-15 14:30 <-- Task with due date and time

  Task description (must be indented at least as much as the task, not less)
  More description lines
  - [ ] Subtask (indented 2 spaces from parent)

    Subtask description (indented at least as much as the subtask)
```

**Format rules** (implemented in `parser.lua` and `sync.lua`):

- **List name**: H1 heading (`# Name`) used to find/create Google Tasks list. Filenames are auto-normalized (lowercase, spaces→hyphens) to prevent duplicates.
- **Task hierarchy**: Subtasks must be indented at least 2 spaces more than their parent (can be 2, 4, 6+ spaces)
- **Task descriptions**: Any non-empty, non-task line following a task becomes its description. **MUST be indented at least as much as the task**. One blank line may separate a task from its description.
- **Checkbox format**: `- [ ]` for incomplete, `- [x]` for completed
- **Due dates**: Optional `| YYYY-MM-DD` or `| YYYY-MM-DD HH:MM` after task title, converted to RFC3339 format. Time is optional; if omitted, defaults to midnight UTC. When syncing from Google, time is only shown if not midnight.
- **Task ID Tracking**: Task-to-Google-ID mappings are stored in `vim.fn.stdpath("data")/gtask_mappings.json` (managed automatically). This enables task renaming, deletion detection, and proper parent-child relationships while keeping markdown files clean.
- **Indentation calculation**: `math.floor(#indent_str / 2)` determines nesting level. The hierarchy builder uses a stack to find the nearest less-indented task as the parent.
- **Filename normalization**: List names are normalized to safe filenames (e.g., "My Shopping List" → `my-shopping-list.md`). The H1 heading preserves the original name.

## Key Architecture Components

### Lua Plugin Modules

- `lua/gtask/init.lua`: Main module entry point with `setup()` function for configuration
- `lua/gtask/config.lua`: Configuration management with defaults and user overrides (proxy URL, markdown directory, ignore_patterns)
- `lua/gtask/auth.lua`: OAuth 2.0 authentication with polling-based flow
- `lua/gtask/api.lua`: Google Tasks API client with automatic token refresh, list management (find/create by name), subtask creation
- `lua/gtask/store.lua`: Token persistence to `vim.fn.stdpath("data")/gtask_tokens.json`
- `lua/gtask/mapping.lua`: Task ID mapping persistence to `vim.fn.stdpath("data")/gtask_mappings.json` (tracks markdown↔Google task relationships)
- `lua/gtask/parser.lua`: Markdown task parser (handles hierarchy, descriptions, due dates, and H1 extraction for list names)
- `lua/gtask/sync.lua`: 2-way sync between markdown and Google Tasks (ID-based matching, multiple lists, parent-child relationships, deletion detection)
- `lua/gtask/files.lua`: Markdown file discovery, directory scanning (recursive with ignore_patterns), and list name extraction
- `plugin/gtask.lua`: Neovim command definitions - only 2 commands: `:GtaskAuth` and `:GtaskSync`

### Backend Proxy Service

The `backend/main.go` Go server handles OAuth 2.0 with PKCE:

**Endpoints**:

- `POST /auth/start` - Generates OAuth URL with PKCE challenge
- `GET /auth/callback` - Receives OAuth callback from Google
- `GET /auth/poll/{state}` - Polling endpoint for auth completion
- `POST /auth/refresh` - Refreshes expired access tokens
- `GET /health` - Health check

**Architecture**: The backend stores PKCE verifiers and completed auth states in-memory with automatic cleanup (10 minute expiry). The plugin polls `/auth/poll/{state}` every 5 seconds for up to 5 minutes after the user visits the auth URL.

### Authentication Flow

1. User runs `:GtaskAuth`
2. Plugin calls `POST /auth/start` → receives auth URL and state
3. User visits URL in browser, completes Google OAuth
4. Google redirects to backend `/auth/callback`
5. Backend exchanges code for tokens, stores in `completedAuth` map
6. Plugin polls `/auth/poll/{state}` until tokens received
7. Tokens saved to `vim.fn.stdpath("data")/gtask_tokens.json`

### Task Rendering Algorithm

The `view.lua` module implements the hierarchical sorting philosophy:

1. **Build tree**: Parse flat task list into parent-child relationships using `task.parent` field
2. **Sort by due date**: Top-level tasks sorted by `task.due` (no due date = last)
3. **Recursive render**: Subtasks rendered under their parent, maintaining parent's position even if subtasks have different due dates

This keeps related tasks together visually.

### File Discovery System

The `files.lua` module handles markdown file operations:

**Key functions**:

- `validate_markdown_dir()`: Checks if configured directory exists and is accessible; creates it if missing
- `find_markdown_files()`: Recursively scans directory using `vim.loop.fs_scandir` for `.md` files, respecting `ignore_patterns`
- `read_markdown_file()`: Reads file contents into line array
- `parse_markdown_file()`: Combines file reading + parsing, returns tasks with file metadata including `list_name` from H1 heading
- `parse_all_markdown_files()`: Entry point for directory sync, returns array of `{file_path, file_name, list_name, tasks}` structures

**Implementation notes**:

- Uses `vim.loop` (libuv bindings) for async-safe filesystem operations
- Path validation: Only accepts absolute paths (starting with `/` or `~`)
- Path expansion: `vim.fn.expand()` for `~` home directory expansion
- Extracts H1 heading via `parser.extract_list_name()` for list name
- Trailing slashes removed for consistency
- Default directory: `~/gtask.nvim` if not configured
- Only files with tasks are included in results
- **Ignore patterns**: The `should_ignore()` function filters out files/directories matching configured patterns:
  - Directory names are matched exactly (e.g., `"archive"` skips any directory named "archive")
  - File names must end in `.md` and match exactly (e.g., `"draft.md"` skips only files named "draft.md")
  - Ignored directories are not scanned recursively

### Sync Implementation

`sync.lua` performs **2-way sync** (markdown ↔ Google Tasks) using H1 headings as list names:

**Implementation flow** (`sync_directory_with_google` → `sync_multiple_lists` → `sync_single_list` → `perform_twoway_sync`):

1. **Parse & Group** (`sync_directory_with_google`):
   - Validate markdown directory via `files.validate_markdown_dir()` (creates if missing)
   - **Fetch ALL Google Task lists** via `api.get_task_lists()` to discover existing lists
   - Scan for `.md` files with `files.find_markdown_files()` (respecting `ignore_patterns`)
   - Parse all files with `files.parse_all_markdown_files()` (extracts H1 headings and tasks)
   - Group markdown tasks by H1 heading (list name) from each file
   - Add source file metadata to each task
   - **Merge lists**: Include all Google Task lists in sync, even if no local markdown exists (initializes with empty task arrays)

2. **Sync Each List** (`sync_multiple_lists` + `sync_single_list`):
   - For each list name (from markdown OR Google):
     - Call `api.get_or_create_list(list_name)` to find or create Google Tasks list
     - Fetch existing tasks from that list via `api.get_tasks(list_id)`
     - Perform 2-way sync for that specific list

3. **2-Way Sync Per List** (`perform_twoway_sync`):
   - Compare markdown tasks vs Google tasks by title (exact match, case-sensitive)
   - Plan operations:
     - Tasks only in markdown → create in Google Tasks
     - Tasks only in Google → write to `[normalized-filename].md`
     - Tasks in both with differences → update Google (markdown is source of truth)
   - Execute operations in parallel (Google API calls + markdown file write)

**Key functions**:

- `normalize_filename()` - Converts list names to safe, consistent filenames (lowercase, spaces→hyphens, removes special chars)
- `sync_directory_with_google()` - Entry point, no parameters needed
- `sync_multiple_lists()` - Manages parallel syncing of multiple lists
- `sync_single_list()` - Syncs one list (get/create + fetch + sync)
- `perform_twoway_sync()` - Compares and plans operations for one list
- `execute_twoway_sync()` - Executes planned operations with parallel API calls
- `create_google_task()` - Creates task with title, description, status, and **due date**
- `update_google_task()` - Updates task including **due date** if present
- `write_google_tasks_to_markdown()` - Writes Google tasks to normalized filename, preserving original list name in H1

**API additions**:

- `api.find_list_by_name()` - Searches for existing list by title
- `api.create_task_list()` - Creates new task list
- `api.get_or_create_list()` - Convenience function combining find + create

**Limitations**:

- Subtask parent relationships are parsed but not synced to Google Tasks
- Title-based matching (renaming tasks creates duplicates)
- No conflict resolution for simultaneous edits (markdown wins)
- Due dates are one-way (markdown → Google) for now

## Configuration

The plugin can be configured via the `setup()` function in `lua/gtask/init.lua`:

```lua
require('gtask').setup({
  proxy_url = "https://your-deployed-proxy.example.com",  -- Default: "https://app.priteshtupe.com/gtask"
  markdown_dir = "~/notes",                                -- Default: "~/gtask.nvim", must be absolute
  ignore_patterns = { "archive", "draft.md" },             -- Default: {}, directory names or .md file names to skip
})
```

**Implementation details**:

- Configuration is managed in `lua/gtask/config.lua` using a defaults table merged with user options
- The `config.lua` module exposes `M.proxy`, `M.storage`, `M.markdown`, and `M.scopes` for backward compatibility
- Proxy URL changes are applied immediately and affect all API calls through `api.lua` and `auth.lua`
- Markdown directory **must be absolute path** (starts with `/` or `~`), defaults to `~/gtask.nvim`
- Path validation ensures no relative paths are accepted (will error on setup)
- The markdown directory will be created automatically if it doesn't exist when running `:GtaskSync`
- `ignore_patterns` accepts an array of strings:
  - Directory names (e.g., `"archive"`) will skip entire subdirectories during scanning
  - File names (e.g., `"draft.md"`) will skip specific markdown files (must end in `.md`)
  - Matching is exact (not pattern/regex matching)

## Available Commands

The plugin exposes only two commands for simplicity:

- **`:GtaskAuth`** - OAuth authentication (automatically clears previous auth and forces re-authentication)
- **`:GtaskSync`** - Performs 2-way sync between markdown directory and Google Tasks (no parameters needed)

## Development Commands

### Running the Backend Proxy

```bash
cd backend
GOOGLE_CLIENT_ID="your-id" \
GOOGLE_CLIENT_SECRET="your-secret" \
REDIRECT_URI="http://localhost:3000/auth/callback" \
PORT="3000" \
go run main.go
```

**Required environment variables**:

- `GOOGLE_CLIENT_ID` - OAuth 2.0 client ID from Google Cloud Console
- `GOOGLE_CLIENT_SECRET` - OAuth 2.0 client secret
- `REDIRECT_URI` - Must match Google Cloud Console redirect URI configuration
- `PORT` - Server port (default: 3000)

### Testing Lua Modules

Test specific Lua patterns:

```bash
lua test_pkce:*
```

## Dependencies

- **Plugin**: `plenary.nvim` (HTTP requests, async jobs), `curl` (system command)
- **Backend**: Go 1.16+ runtime
- **Neovim**: Built-in `vim.loop` for async operations

## Current Limitations

### 1. No Subtask Parent Relationships in Sync

- **Issue**: The parser correctly detects subtasks in markdown (indented tasks) and builds parent-child relationships via `parent_index`
- **Current behavior**: All tasks are created as top-level tasks in Google Tasks, losing the hierarchy
- **Impact**: Parent-child structure visible in markdown is flattened when synced to Google Tasks
- **Note**: See "Implementing Subtask Support" section below for solution details

### 2. Title-Based Matching Only

- **Issue**: Tasks are matched between markdown and Google Tasks by exact title (case-sensitive)
- **Current behavior**: Renaming a task in markdown creates a new task in Google Tasks; the old task remains
- **Impact**: Can lead to duplicate tasks if titles are modified
- **Workaround**: Delete old tasks manually in Google Tasks after renaming in markdown

### 3. No Deletion Sync

- **Issue**: Removing a task from markdown does not delete it from Google Tasks
- **Current behavior**: Deleted tasks will reappear in your markdown files on the next sync (written back from Google)
- **Impact**: Tasks must be deleted manually in both locations
- **Workaround**: Delete in Google Tasks first, then remove from markdown

### 4. One-Way Conflict Resolution

- **Issue**: When a task exists in both locations with different content, markdown always wins
- **Current behavior**: No conflict detection, notification, or user choice
- **Impact**: Changes made in Google Tasks app/web may be overwritten by markdown version on next sync
- **Note**: This is by design - markdown is considered the source of truth

### 5. Manual Sync Only

- **Issue**: No automatic or scheduled synchronization
- **Current behavior**: User must run `:GtaskSync` command manually
- **Impact**: Changes aren't reflected until manual sync is triggered
- **Potential enhancement**: Background sync, file watcher, or periodic auto-sync

### 6. Limited Task Metadata Sync

- **What syncs**: Title, status (completed/incomplete), description (notes), due date
- **What doesn't sync**: Task order/position, creation date, last update time, links, attachments, other Google Tasks metadata
- **Impact**: Full task history and metadata only available in Google Tasks interface

### 7. Single H1 Heading Per File

- **Issue**: Only the first H1 heading in a file is used as the task list name
- **Current behavior**: Subsequent H1 headings are ignored; all tasks in file go to the same list
- **Impact**: Can't have multiple task lists in a single markdown file
- **Workaround**: Use separate markdown files for different task lists

### 8. Subtask Indentation Requirements

- **Subtasks**: Must be indented at least 2 spaces more than their parent (2, 4, 6+ spaces all work)
- **Task descriptions**: No strict indentation required - any non-task line following a task becomes its description
- **Impact**: Subtasks with less than 2 spaces of additional indentation won't be recognized as children
- **Note**: Based on `indent_level = math.floor(#indent_str / 2)` calculation and stack-based hierarchy building

### 9. App isn't verified on Google

## Implementing Subtask Support

This section documents how to implement parent-child task relationships (limitation #1) using the Google Tasks API.

### API Support for Subtasks

The Google Tasks API v1 **fully supports** parent-child task relationships through:

- **Query parameter approach**: Use `parent` parameter when creating tasks
- **Move method**: Relocate existing tasks to establish/change parent relationships
- **Read-only `parent` field**: Task objects include parent ID in responses

### Required API Changes

#### New Functions in `api.lua`

**1. Create Task with Parent**

```lua
--- Create a task with optional parent and positioning
---@param task_list_id string The task list ID
---@param task_data table Task data (title, notes, status, due)
---@param parent_id string|nil Parent task ID (nil for top-level)
---@param previous_id string|nil Previous sibling task ID for ordering
---@param callback function Callback with response or error
function M.create_task_with_parent(task_list_id, task_data, parent_id, previous_id, callback)
	local url = string.format("https://tasks.googleapis.com/tasks/v1/lists/%s/tasks", task_list_id)

	-- Build query parameters
	local query_params = {}
	if parent_id and parent_id ~= "" then
		table.insert(query_params, "parent=" .. parent_id)
	end
	if previous_id and previous_id ~= "" then
		table.insert(query_params, "previous=" .. previous_id)
	end

	if #query_params > 0 then
		url = url .. "?" .. table.concat(query_params, "&")
	end

	request({
		method = "POST",
		url = url,
		body = task_data,
	}, callback)
end
```

**2. Move Task (Future Enhancement)**

```lua
--- Move a task to change parent or position
---@param task_list_id string The task list ID
---@param task_id string The task to move
---@param parent_id string|nil New parent ID (nil for top-level)
---@param previous_id string|nil New previous sibling ID
---@param callback function Callback with response or error
function M.move_task(task_list_id, task_id, parent_id, previous_id, callback)
	local url = string.format(
		"https://tasks.googleapis.com/tasks/v1/lists/%s/tasks/%s/move",
		task_list_id,
		task_id
	)

	local query_params = {}
	if parent_id then
		table.insert(query_params, "parent=" .. parent_id)
	end
	if previous_id then
		table.insert(query_params, "previous=" .. previous_id)
	end

	if #query_params > 0 then
		url = url .. "?" .. table.concat(query_params, "&")
	end

	request({
		method = "POST",
		url = url,
	}, callback)
end
```

### Sync Logic Changes

#### Two-Pass Creation Strategy in `sync.lua`

Replace the current `create_google_task()` approach with a two-pass system:

**Pass 1: Create Top-Level Tasks**

```lua
-- Create all tasks without parents first
local task_id_map = {} -- Maps markdown task index to Google task ID

for i, mdtask in ipairs(markdown_tasks) do
	if not mdtask.parent_index then
		-- Top-level task
		M.create_google_task(mdtask, task_list_id, function(response, err)
			if response and response.id then
				task_id_map[i] = response.id
			end
		end)
	end
end
```

**Pass 2: Create Subtasks with Parent IDs**

```lua
-- Wait for Pass 1 to complete, then create subtasks
for i, mdtask in ipairs(markdown_tasks) do
	if mdtask.parent_index then
		local parent_id = task_id_map[mdtask.parent_index]
		if parent_id then
			-- Create subtask with parent reference
			api.create_task_with_parent(
				task_list_id,
				{
					title = mdtask.title,
					notes = mdtask.description,
					status = mdtask.completed and "completed" or "needsAction",
					due = mdtask.due_date,
				},
				parent_id,
				nil, -- previous_id for ordering (future enhancement)
				callback
			)
		else
			-- Parent wasn't created - log error or create as top-level
			vim.notify("Warning: Parent task not found for " .. mdtask.title, vim.log.levels.WARN)
		end
	end
end
```

#### Updated `create_google_task()` Function

Modify to support parent parameter:

```lua
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

	-- Use new API function with parent support
	api.create_task_with_parent(task_list_id, google_task, parent_id, nil, callback)
end
```

### API Restrictions and Validation

**Must validate before creating subtasks:**

1. **2,000 Subtask Limit**: Count children per parent

   ```lua
   local children_count = {}
   for _, task in ipairs(tasks) do
       if task.parent_index then
           children_count[task.parent_index] = (children_count[task.parent_index] or 0) + 1
           if children_count[task.parent_index] > 2000 then
               -- Error: too many subtasks
           end
       end
   end
   ```

2. **No Assigned Tasks as Parents**: Google Tasks assigned from Chat/Docs cannot be parents (check `assignmentInfo` field)

3. **No Completed+Hidden as Nested**: Tasks with both `completed=true` and `hidden=true` cannot have parent

4. **No Repeating Tasks**: Tasks with `recurrence` field cannot be parents or subtasks

### Edge Cases to Handle

**1. Orphaned Subtasks**

```lua
-- Markdown has subtask but parent task is missing
if mdtask.parent_index and not tasks[mdtask.parent_index] then
	vim.notify("Orphaned subtask: " .. mdtask.title, vim.log.levels.WARN)
	-- Create as top-level task instead
	mdtask.parent_index = nil
end
```

**2. Circular References**

```lua
-- Should never happen with proper indentation parsing, but validate anyway
local function has_circular_ref(tasks, task_index, visited)
	if visited[task_index] then return true end
	visited[task_index] = true

	local parent_idx = tasks[task_index].parent_index
	if parent_idx then
		return has_circular_ref(tasks, parent_idx, visited)
	end
	return false
end
```

**3. Deep Nesting**

```lua
-- Calculate maximum depth
local function get_depth(tasks, task_index, depth)
	local parent_idx = tasks[task_index].parent_index
	if not parent_idx then return depth end
	return get_depth(tasks, parent_idx, depth + 1)
end

-- Warn if very deep (Google supports it but may have performance impact)
if get_depth(tasks, i, 0) > 10 then
	vim.notify("Very deep nesting detected (>10 levels)", vim.log.levels.WARN)
end
```

**4. Sibling Ordering**

```lua
-- Preserve order of subtasks under same parent
local siblings = {}
for _, task in ipairs(tasks) do
	if task.parent_index == parent_idx then
		table.insert(siblings, task)
	end
end

-- Create siblings in order using `previous` parameter
local previous_id = nil
for _, sibling in ipairs(siblings) do
	api.create_task_with_parent(list_id, sibling_data, parent_id, previous_id, function(resp)
		previous_id = resp.id
	end)
end
```

### Example API Requests

**Creating a parent task:**

```
POST https://tasks.googleapis.com/tasks/v1/lists/MTIzNDU2Nzg5/tasks
Authorization: Bearer {access_token}
Content-Type: application/json

{
  "title": "Plan project",
  "notes": "Define scope and timeline"
}

Response:
{
  "id": "parent-abc123",
  "title": "Plan project",
  "status": "needsAction"
}
```

**Creating a subtask:**

```
POST https://tasks.googleapis.com/tasks/v1/lists/MTIzNDU2Nzg5/tasks?parent=parent-abc123
Authorization: Bearer {access_token}
Content-Type: application/json

{
  "title": "Define scope",
  "status": "needsAction"
}

Response:
{
  "id": "subtask-xyz789",
  "title": "Define scope",
  "parent": "parent-abc123",
  "status": "needsAction"
}
```

### Implementation Roadmap

**Phase 1: Basic Subtask Creation**

1. Add `create_task_with_parent()` to api.lua
2. Implement two-pass sync in sync.lua
3. Handle basic parent-child relationships
4. Test with simple 2-level hierarchies

**Phase 2: Robust Error Handling**

1. Add validation for orphaned subtasks
2. Implement circular reference detection
3. Add depth warnings
4. Handle API quota limits

**Phase 3: Advanced Features**

1. Implement sibling ordering with `previous` parameter
2. Add `move_task()` for reorganizing existing hierarchies
3. Support updating parent relationships on re-sync
4. Sync parent changes from Google Tasks back to markdown

**Note**: This implementation assumes tasks are matched by title (current limitation #2). For a more robust solution that handles renames and deletions, consider implementing a task ID mapping system (see user discussion above).

## Security Notes

- **No credentials in plugin code**: OAuth secrets handled entirely by backend proxy
- **Local token storage**: Access/refresh tokens stored in Neovim data directory only
- **PKCE implementation**: Backend uses Proof Key for Code Exchange for enhanced security
- **Temporary state storage**: PKCE states expire after 10 minutes
- **No local server in plugin**: Polling-based flow eliminates port conflicts
