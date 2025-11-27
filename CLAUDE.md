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
<!-- gtask:abc123 --> <-- UUID for stable task identification (auto-generated)
- [ ] Another task | 2025-01-15 14:30 <-- Task with due date and time
<!-- gtask:xyz789 -->

  Task description (must be indented at least as much as the task, not less)
  More description lines
  - [ ] Subtask (indented 2 spaces from parent)
  <!-- gtask:def456 -->

    Subtask description (indented at least as much as the subtask)
```

**Format rules** (implemented in `parser.lua` and `sync.lua`):

- **List name**: H1 heading (`# Name`) used to find/create Google Tasks list. Filenames are auto-normalized (lowercase, spaces→hyphens) to prevent duplicates.
- **Task hierarchy**: Subtasks must be indented at least 2 spaces more than their parent (can be 2, 4, 6+ spaces)
- **Task descriptions**: Any non-empty, non-task line following a task becomes its description. **MUST be indented at least as much as the task**. One blank line may separate a task from its description.
- **Checkbox format**: `- [ ]` for incomplete, `- [x]` for completed
- **Due dates**: Optional `| YYYY-MM-DD` or `| YYYY-MM-DD HH:MM` after task title, converted to RFC3339 format. Time is optional; if omitted, defaults to midnight UTC. When syncing from Google, time is only shown if not midnight.
- **Task ID Tracking**: Each task is assigned a unique UUID embedded as an HTML comment (`<!-- gtask:uuid -->`). UUIDs are stable identifiers that persist across renames, moves, and edits. The mapping file `vim.fn.stdpath("data")/gtask_mappings.json` stores UUID→Google-ID relationships with sync timestamps (managed automatically). This enables task renaming, deletion detection, and proper parent-child relationships.
- **Indentation calculation**: `math.floor(#indent_str / 2)` determines nesting level. The hierarchy builder uses a stack to find the nearest less-indented task as the parent.
- **Filename normalization**: List names are normalized to safe filenames (e.g., "My Shopping List" → `my-shopping-list.md`). The H1 heading preserves the original name.

## Key Architecture Components

### Lua Plugin Modules

- `lua/gtask/init.lua`: Main module entry point with `setup()` function for configuration
- `lua/gtask/config.lua`: Configuration management with defaults and user overrides (proxy URL, markdown directory, ignore_patterns)
- `lua/gtask/auth.lua`: OAuth 2.0 authentication with polling-based flow
- `lua/gtask/api.lua`: Google Tasks API client with automatic token refresh, list management (find/create by name), subtask creation
- `lua/gtask/store.lua`: Token persistence to `vim.fn.stdpath("data")/gtask_tokens.json`
- `lua/gtask/mapping.lua`: UUID-based task mapping persistence to `vim.fn.stdpath("data")/gtask_mappings.json` (tracks UUID↔Google task relationships with sync timestamps, includes automatic migration from old position-based format)
- `lua/gtask/parser.lua`: Markdown task parser (handles hierarchy, descriptions, due dates, UUID extraction from HTML comments, and H1 extraction for list names)
- `lua/gtask/sync.lua`: 2-way sync between markdown and Google Tasks (UUID-based matching with title fallback, automatic UUID generation/embedding, multiple lists, parent-child relationships, timestamp-based conflict resolution)
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
   - Match markdown tasks to Google tasks by UUID (primary) or title (fallback for migration)
   - Generate UUIDs for any tasks without them
   - Plan operations:
     - Tasks only in markdown → create in Google Tasks, embed UUID in markdown
     - Tasks only in Google → write to `[normalized-filename].md` with UUID comment
     - Tasks in both with differences → use timestamp comparison to determine winner:
       - If Google's `updated` > mapping's `google_updated`: Google wins, update markdown
       - Otherwise: Markdown wins, update Google
   - Execute operations in parallel (Google API calls + markdown file writes)
   - Embed all generated UUIDs into markdown files (bottom-to-top to preserve line numbers)

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

### Testing

**Unit Tests** (fast, no authentication required):
```bash
make test
# or
make test-unit
```

**End-to-End Tests** (requires authentication, tests against real Google Tasks API):
```bash
# First authenticate in Neovim
nvim -c ":GtaskAuth"

# Then run E2E tests
make test-e2e
```

The E2E test suite (`tests/e2e/e2e_spec.lua`) creates a unique test list (e.g., `E2E_Test_List_<timestamp>`) and performs comprehensive testing:
- Authentication verification
- Task creation from markdown → Google Tasks
- Subtask hierarchy and parent-child relationships
- Task updates (title, status, description, due date)
- Google Tasks → markdown sync
- Task deletion detection
- Edge cases (unicode, special characters)
- Round-trip data integrity (markdown → Google → markdown)

Each test automatically cleans up after itself by:
1. Deleting the local test directory (`~/gtask-e2e-test`)
2. Removing all tasks from the test list in Google Tasks

See `tests/e2e/README.md` for detailed E2E test documentation.

## Dependencies

- **Plugin**: `curl` (system command)
- **Backend**: Go 1.16+ runtime
- **Neovim**: Built-in `vim.system` for async operations, `vim.loop` for filesystem operations

## Current Limitations

### 1. Manual Sync Only

- **Issue**: No automatic or scheduled synchronization
- **Current behavior**: User must run `:GtaskSync` command manually
- **Impact**: Changes aren't reflected until manual sync is triggered
- **Potential enhancement**: Background sync, file watcher, or periodic auto-sync

### 2. Limited Task Metadata Sync

- **What syncs**: Title, status (completed/incomplete), description (notes), due date
- **What doesn't sync**: Task order/position, creation date, last update time, links, attachments, other Google Tasks metadata
- **Impact**: Full task history and metadata only available in Google Tasks interface

### 3. Single H1 Heading Per File

- **Issue**: Only the first H1 heading in a file is used as the task list name
- **Current behavior**: Subsequent H1 headings are ignored; all tasks in file go to the same list
- **Impact**: Can't have multiple task lists in a single markdown file
- **Workaround**: Use separate markdown files for different task lists

### 4. Subtask Indentation Requirements

- **Subtasks**: Must be indented at least 2 spaces more than their parent (2, 4, 6+ spaces all work)
- **Task descriptions**: No strict indentation required - any non-task line following a task becomes its description
- **Impact**: Subtasks with less than 2 spaces of additional indentation won't be recognized as children
- **Note**: Based on `indent_level = math.floor(#indent_str / 2)` calculation and stack-based hierarchy building

### 5. App isn't verified on Google

## UUID-Based Task Tracking

The plugin uses a UUID-based system for stable task identification across renames, moves, and edits.

### UUID Format

- **Format**: `<!-- gtask:abc123 -->` - HTML comment, invisible when markdown is rendered
- **Generation**: Base62-encoded timestamp + random number (8-12 characters)
- **Placement**: Immediately after task line in markdown file
- **Visibility**: Hidden in most markdown renderers, easy to ignore when reading raw markdown

### UUID Generation and Embedding

UUIDs are automatically generated and embedded during sync:

1. **New tasks from markdown**: Generate UUID, create in Google Tasks, embed UUID comment in markdown
2. **New tasks from Google**: Create task with UUID in markdown file
3. **Existing tasks without UUID**: Generate UUID during sync, embed after sync completes
4. **Migration from old format**: Title-based fallback matching reconnects tasks during first sync after migration

**Embedding strategy**:
- UUIDs are embedded **after** sync operations complete
- Tasks are processed **bottom-to-top** to preserve line numbers during embedding
- Each UUID is inserted on the line immediately following its task

### Mapping File Structure

The mapping file (`vim.fn.stdpath("data")/gtask_mappings.json`) stores:

```json
{
  "lists": {
    "Shopping": "google_list_id_123"
  },
  "tasks": {
    "uuid-abc123": {
      "google_id": "google_task_456",
      "list_name": "Shopping",
      "file_path": "/path/to/shopping.md",
      "parent_uuid": null,
      "google_updated": "2025-01-15T10:00:00Z",
      "last_synced": "2025-01-15T10:05:00Z"
    }
  }
}
```

**Fields**:
- `google_id`: Google Tasks API task ID
- `list_name`: Task list name (matches H1 heading)
- `file_path`: Absolute path to markdown file containing the task
- `parent_uuid`: UUID of parent task (null for top-level tasks)
- `google_updated`: Last update timestamp from Google Tasks API (RFC3339)
- `last_synced`: Timestamp when mapping was last updated (RFC3339)

### Automatic Migration

The plugin automatically detects and migrates old position-based mappings:

1. **Detection**: `is_old_format()` checks for `position_path` field in any task
2. **Backup**: Creates `gtask_mappings.json.backup` with old format
3. **Migration**: Clears task mappings (preserves list mappings)
4. **Re-matching**: Next sync uses title-based fallback to reconnect tasks
5. **UUID generation**: All tasks get UUIDs during first sync after migration

**User experience**: Migration is automatic and transparent. Users see a notification about migration and title-based re-matching on first sync.

## Subtask Implementation

Subtask parent-child relationships are **fully implemented** and synced bidirectionally between markdown and Google Tasks.

### How It Works

**Markdown Format**:
Subtasks are detected by indentation (minimum 2 spaces more than parent), with UUID comments for stable tracking:

```markdown
- [ ] Parent task
<!-- gtask:abc123 -->
  - [ ] Subtask (2 spaces)
  <!-- gtask:def456 -->
    - [ ] Nested subtask (4 spaces)
    <!-- gtask:ghi789 -->
      Description (4+ spaces)
```

**Parsing** (`parser.lua`):
- Indentation level calculated: `indent_level = math.floor(#indent_str / 2)`
- Stack-based hierarchy building finds nearest less-indented task as parent
- Sets `parent_index` field on each subtask
- Extracts UUID from `<!-- gtask:uuid -->` comment following task line

**Syncing** (`sync.lua`):
The sync uses a **two-pass creation strategy**:

**Phase 1: Top-level tasks**
- Creates all tasks without `parent_index` first
- Stores created task IDs mapped by UUID: `created_google_ids[uuid] = google_id`
- Waits for ALL top-level tasks to complete

**Phase 2: Subtasks with parent references**
- For each subtask, looks up parent's UUID from `parent_index`
- Gets `parent_google_id = created_google_ids[parent_uuid]`
- Calls `api.create_task_with_parent(list_id, task_data, parent_google_id, nil, callback)`
- Registers with `parent_uuid` in mapping

**API Support** (`api.lua`):
```lua
function M.create_task_with_parent(task_list_id, task_data, parent_id, previous_id, callback)
  local url = string.format("https://tasks.googleapis.com/tasks/v1/lists/%s/tasks", task_list_id)

  -- Add parent query parameter if provided
  if parent_id and parent_id ~= "" then
    url = url .. "?parent=" .. parent_id
  end

  request({ method = "POST", url = url, body = task_data }, callback)
end
```

**Mapping Tracking** (`gtask_mappings.json`):
```json
{
  "lists": {"Shopping": "google_list_id_123"},
  "tasks": {
    "abc123": {
      "google_id": "google_task_id_456",
      "list_name": "Shopping",
      "file_path": "/path/to/shopping.md",
      "parent_uuid": null,
      "google_updated": "2025-01-15T10:00:00Z",
      "last_synced": "2025-01-15T10:05:00Z"
    },
    "def456": {
      "google_id": "google_task_id_789",
      "list_name": "Shopping",
      "file_path": "/path/to/shopping.md",
      "parent_uuid": "abc123",
      "google_updated": "2025-01-15T10:00:00Z",
      "last_synced": "2025-01-15T10:05:00Z"
    }
  }
}
```
- Parent-child relationships tracked via `parent_uuid` field
- UUIDs provide stable references across renames and moves

### Current Limitations

- **No sibling ordering**: The `previous` parameter is not used yet, so subtask order may not be preserved
- **Parent changes**: Moving a subtask to a different parent requires updating the parent relationship. The `move_task()` API function is available in `api.lua` but not yet integrated into sync logic
- **Deep nesting**: No depth limit validation (Google Tasks supports unlimited depth)

## Security Notes

- **No credentials in plugin code**: OAuth secrets handled entirely by backend proxy
- **Local token storage**: Access/refresh tokens stored in Neovim data directory only
- **PKCE implementation**: Backend uses Proof Key for Code Exchange for enhanced security
- **Temporary state storage**: PKCE states expire after 10 minutes
- **No local server in plugin**: Polling-based flow eliminates port conflicts
