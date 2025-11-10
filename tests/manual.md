# Manual Test Plan for gtask.nvim

This document provides a comprehensive manual testing checklist for gtask.nvim. Tests are organized by feature area and include expected results.

## Prerequisites

Before running tests:
- [ ] Plugin is installed and loaded in Neovim
- [ ] Backend proxy is running and accessible
- [ ] OAuth authentication completed (`:GtaskAuth`)
- [ ] Test markdown directory exists (default: `~/gtask.nvim` or configured path)

## Test Environment Setup

Create a clean test environment:
```bash
# Backup existing data
mv ~/.local/share/nvim/gtask_mappings.json ~/.local/share/nvim/gtask_mappings.json.bak
mv ~/.local/share/nvim/gtask_tokens.json ~/.local/share/nvim/gtask_tokens.json.bak

# Clear all tasks from Google Tasks web interface
# Create fresh test directory
mkdir -p ~/gtask-test
```

Configure plugin to use test directory:
```lua
require('gtask').setup({
  markdown_dir = "~/gtask-test"
})
```

---

## 1. Authentication Flow

### 1.1 Initial Authentication
- [ ] Run `:GtaskAuth`
- [ ] Verify auth URL is displayed
- [ ] Open URL in browser
- [ ] Complete Google OAuth consent
- [ ] **Expected**: "Authentication successful" message in Neovim
- [ ] **Expected**: Token file created at `~/.local/share/nvim/gtask_tokens.json`

### 1.2 Re-authentication (Token Refresh)
- [ ] Delete token file: `rm ~/.local/share/nvim/gtask_tokens.json`
- [ ] Run `:GtaskSync`
- [ ] **Expected**: Authentication error prompting to run `:GtaskAuth`
- [ ] Run `:GtaskAuth` again
- [ ] **Expected**: Successfully re-authenticated

### 1.3 Token Persistence
- [ ] Authenticate successfully
- [ ] Close and reopen Neovim
- [ ] Run `:GtaskSync`
- [ ] **Expected**: Sync works without re-authenticating

---

## 2. Basic Task Sync - Markdown to Google

### 2.1 Create Single Task in Markdown
- [ ] Create file: `~/gtask-test/test-list.md`
- [ ] Add content:
  ```markdown
  # Test List

  - [ ] Task A
  ```
- [ ] Run `:GtaskSync`
- [ ] **Expected**: "1→Google (1 new, 0 update)" in sync plan
- [ ] **Expected**: Task appears in Google Tasks web interface under "Test List"
- [ ] **Expected**: Mapping created in `gtask_mappings.json`

### 2.2 Create Multiple Tasks
- [ ] Add to `test-list.md`:
  ```markdown
  # Test List

  - [ ] Task A
  - [ ] Task B
  - [ ] Task C
  ```
- [ ] Run `:GtaskSync`
- [ ] **Expected**: "2→Google (2 new, 0 update)"
- [ ] **Expected**: All three tasks in Google Tasks
- [ ] **Expected**: Tasks maintain order

### 2.3 Create Task with Description
- [ ] Add to `test-list.md`:
  ```markdown
  # Test List

  - [ ] Task with Description

    This is the description.
    It has multiple lines.
  ```
- [ ] Run `:GtaskSync`
- [ ] **Expected**: Task created with description in Google Tasks
- [ ] **Expected**: Description text matches (including multiple lines)

### 2.4 Create Task with Due Date
- [ ] Add to `test-list.md`:
  ```markdown
  # Test List

  - [ ] Task with Date | 2025-12-25
  ```
- [ ] Run `:GtaskSync`
- [ ] **Expected**: Task created with due date Dec 25, 2025
- [ ] **Expected**: Time is midnight (Google Tasks API limitation)

### 2.5 Create Task with Date and Time
- [ ] Add to `test-list.md`:
  ```markdown
  # Test List

  - [ ] Task with DateTime | 2025-12-25 14:30
  ```
- [ ] Run `:GtaskSync`
- [ ] **Expected**: Task created with due date Dec 25, 2025
- [ ] **Expected**: Time is still midnight (API limitation - time component ignored)

### 2.6 Create Completed Task
- [ ] Add to `test-list.md`:
  ```markdown
  # Test List

  - [x] Completed Task
  ```
- [ ] Run `:GtaskSync`
- [ ] **Expected**: Task created and marked as completed in Google Tasks

---

## 3. Basic Task Sync - Google to Markdown

### 3.1 Create Task in Google Tasks
- [ ] Open Google Tasks web interface
- [ ] Create new list: "Google List"
- [ ] Add task: "Google Task A"
- [ ] Run `:GtaskSync` in Neovim
- [ ] **Expected**: File created: `~/gtask-test/google-list.md`
- [ ] **Expected**: Contains:
  ```markdown
  # Google List

  - [ ] Google Task A
  ```

### 3.2 Create Task with Details in Google
- [ ] In Google Tasks, create task: "Detailed Task"
- [ ] Add description: "This is from Google"
- [ ] Set due date: Tomorrow
- [ ] Mark as completed
- [ ] Run `:GtaskSync`
- [ ] **Expected**: Task in markdown with:
  - Description indented under task
  - Due date in `| YYYY-MM-DD` format
  - Checkbox marked: `- [x]`

### 3.3 Multiple Lists
- [ ] Create two lists in Google Tasks: "Work" and "Personal"
- [ ] Add tasks to each list
- [ ] Run `:GtaskSync`
- [ ] **Expected**: Two files created:
  - `~/gtask-test/work.md`
  - `~/gtask-test/personal.md`
- [ ] **Expected**: Each contains correct tasks

---

## 4. Subtasks and Hierarchy

### 4.1 Create Subtask in Markdown
- [ ] Add to `test-list.md`:
  ```markdown
  # Test List

  - [ ] Parent Task
    - [ ] Subtask 1
    - [ ] Subtask 2
  ```
- [ ] Run `:GtaskSync`
- [ ] **Expected**: Parent task created first
- [ ] **Expected**: Subtasks created with correct parent reference
- [ ] **Expected**: Hierarchy visible in Google Tasks

### 4.2 Nested Subtasks
- [ ] Add to `test-list.md`:
  ```markdown
  # Test List

  - [ ] Parent
    - [ ] Child
      - [ ] Grandchild
  ```
- [ ] Run `:GtaskSync`
- [ ] **Expected**: Three-level hierarchy in Google Tasks

### 4.3 Subtask with Description
- [ ] Add to `test-list.md`:
  ```markdown
  # Test List

  - [ ] Parent
    - [ ] Subtask

      Subtask description here
  ```
- [ ] Run `:GtaskSync`
- [ ] **Expected**: Subtask created with description

### 4.4 Create Subtask in Google
- [ ] In Google Tasks, add task "Google Parent"
- [ ] Add subtask "Google Child" under it
- [ ] Run `:GtaskSync`
- [ ] **Expected**: Markdown shows proper indentation:
  ```markdown
  - [ ] Google Parent
    - [ ] Google Child
  ```

---

## 5. Task Updates

### 5.1 Update Task Title in Markdown
- [ ] Edit existing task title in markdown
- [ ] Run `:GtaskSync`
- [ ] **Expected**: "1→Google (0 new, 1 update)"
- [ ] **Expected**: Title updated in Google Tasks

### 5.2 Update Task Description
- [ ] Add or modify description in markdown
- [ ] Run `:GtaskSync`
- [ ] **Expected**: Description updated in Google Tasks

### 5.3 Update Due Date
- [ ] Change due date in markdown: `| 2025-11-15` → `| 2025-11-20`
- [ ] Run `:GtaskSync`
- [ ] **Expected**: Due date updated in Google Tasks

### 5.4 Mark Task Complete in Markdown
- [ ] Change `- [ ]` to `- [x]`
- [ ] Run `:GtaskSync`
- [ ] **Expected**: Task marked complete in Google Tasks

### 5.5 Mark Task Incomplete in Markdown
- [ ] Change `- [x]` to `- [ ]`
- [ ] Run `:GtaskSync`
- [ ] **Expected**: Task marked incomplete in Google Tasks

### 5.6 Complete Task in Google
- [ ] Mark task complete in Google Tasks
- [ ] Run `:GtaskSync`
- [ ] **Expected**: "0→markdown (0 new, 1 update)"
- [ ] **Expected**: Checkbox updated to `- [x]` in markdown

### 5.7 Conflict Resolution - Completion Status
- [ ] Mark task complete in markdown: `- [x]`
- [ ] Mark same task incomplete in Google Tasks
- [ ] Run `:GtaskSync`
- [ ] **Expected**: Google's change wins (newer timestamp)
- [ ] **Expected**: Markdown updated to `- [ ]`

---

## 6. Task Deletion

### 6.1 Delete Task from Markdown (First Time Setup)
- [ ] Create task: `- [ ] Delete Test A`
- [ ] Run `:GtaskSync` (creates task and mapping)
- [ ] Run `:GtaskSync` again (ensures mapping exists)
- [ ] Delete task line from markdown
- [ ] Save file
- [ ] Run `:GtaskSync`
- [ ] **Expected**: "1 deletions from markdown" in sync plan
- [ ] **Expected**: Task deleted from Google Tasks
- [ ] **Expected**: Task does NOT reappear in markdown

### 6.2 Delete Task from Google
- [ ] Delete task from Google Tasks web interface
- [ ] Run `:GtaskSync`
- [ ] **Expected**: "1 deletions from Google"
- [ ] **Expected**: Task removed from markdown file

### 6.3 Delete Completed Task from Markdown
- [ ] Create completed task: `- [x] Completed Delete Test`
- [ ] Run `:GtaskSync` twice (create mapping)
- [ ] Delete from markdown
- [ ] Run `:GtaskSync`
- [ ] **Expected**: Task deleted from Google (default behavior)

### 6.4 Delete Parent Task
- [ ] Create parent with subtasks
- [ ] Run `:GtaskSync` twice
- [ ] Delete parent task line
- [ ] Run `:GtaskSync`
- [ ] **Expected**: Parent deleted
- [ ] **Expected**: Subtasks become orphaned or deleted (check behavior)

### 6.5 Delete Subtask Only
- [ ] Create parent with subtasks
- [ ] Run `:GtaskSync` twice
- [ ] Delete one subtask line
- [ ] Run `:GtaskSync`
- [ ] **Expected**: Subtask deleted
- [ ] **Expected**: Parent and other subtasks remain

---

## 7. Title-Based Matching and Mapping

### 7.1 Task Created in Google (No Mapping)
- [ ] Create task in Google Tasks: "Mapping Test A"
- [ ] Run `:GtaskSync`
- [ ] **Expected**: Task written to markdown
- [ ] **Expected**: Message: "Matched task by title (no mapping)"
- [ ] Run `:GtaskSync` again
- [ ] **Expected**: No message (mapping now exists)
- [ ] Delete from markdown
- [ ] Run `:GtaskSync`
- [ ] **Expected**: Task deleted from Google (mapping enabled deletion)

### 7.2 Mapping File Deleted
- [ ] Delete `~/.local/share/nvim/gtask_mappings.json`
- [ ] Run `:GtaskSync`
- [ ] **Expected**: Title-based matching occurs for all existing tasks
- [ ] **Expected**: Mappings recreated
- [ ] **Expected**: No duplicate tasks created

### 7.3 Task Renamed in Markdown
- [ ] Rename task: "Old Name" → "New Name"
- [ ] Run `:GtaskSync`
- [ ] **Expected**: Title updated in Google Tasks
- [ ] **Expected**: Mapping updated with new title

---

## 8. Multiple Lists and Files

### 8.1 Multiple Markdown Files
- [ ] Create `~/gtask-test/work.md`:
  ```markdown
  # Work

  - [ ] Work Task 1
  ```
- [ ] Create `~/gtask-test/personal.md`:
  ```markdown
  # Personal

  - [ ] Personal Task 1
  ```
- [ ] Run `:GtaskSync`
- [ ] **Expected**: Two lists created in Google Tasks
- [ ] **Expected**: Tasks in correct lists

### 8.2 Same List Name in Different Files
- [ ] Create `~/gtask-test/list-a.md` with `# Shopping`
- [ ] Create `~/gtask-test/list-b.md` with `# Shopping`
- [ ] Add different tasks to each
- [ ] Run `:GtaskSync`
- [ ] **Expected**: Both files sync to same "Shopping" list in Google
- [ ] **Expected**: All tasks from both files appear in Google

### 8.3 File Name Normalization
- [ ] Create `~/gtask-test/My Shopping List.md` with `# My Shopping List`
- [ ] Run `:GtaskSync`
- [ ] **Expected**: File created: `my-shopping-list.md`
- [ ] **Expected**: H1 heading preserved: `# My Shopping List`

---

## 9. Edge Cases

### 9.1 Empty File
- [ ] Create `empty.md` with only:
  ```markdown
  # Empty List
  ```
- [ ] Run `:GtaskSync`
- [ ] **Expected**: List created in Google but no tasks
- [ ] **Expected**: No errors

### 9.2 File with No H1 Heading
- [ ] Create `no-heading.md`:
  ```markdown
  - [ ] Task without heading
  ```
- [ ] Run `:GtaskSync`
- [ ] **Expected**: List named "none" or default
- [ ] **Expected**: Task synced

### 9.3 Special Characters in Task Title
- [ ] Create task: `- [ ] Task with "quotes" and 'apostrophes'`
- [ ] Run `:GtaskSync`
- [ ] **Expected**: Title preserved correctly in Google

### 9.4 Very Long Task Title
- [ ] Create task with 500+ character title
- [ ] Run `:GtaskSync`
- [ ] **Expected**: Task created (Google Tasks may truncate)

### 9.5 Very Long Description
- [ ] Create task with multi-paragraph, 1000+ character description
- [ ] Run `:GtaskSync`
- [ ] **Expected**: Full description synced

### 9.6 Unicode Characters
- [ ] Create task: `- [ ] Task with émojis 🎉 and 中文字符`
- [ ] Run `:GtaskSync`
- [ ] **Expected**: Unicode preserved in Google Tasks

### 9.7 Blank Lines in Description
- [ ] Create task:
  ```markdown
  - [ ] Task with gaps

    Paragraph 1

    Paragraph 2
  ```
- [ ] Run `:GtaskSync`
- [ ] **Expected**: Description formatting preserved

### 9.8 Invalid Due Date Format
- [ ] Create task: `- [ ] Bad Date | 2025-13-40`
- [ ] Run `:GtaskSync`
- [ ] **Expected**: Error or date ignored

### 9.9 Task at File End (No Trailing Newline)
- [ ] Create file ending with task, no blank line after
- [ ] Run `:GtaskSync`
- [ ] **Expected**: Task synced correctly

---

## 10. File Discovery and Ignore Patterns

### 10.1 Subdirectories
- [ ] Create `~/gtask-test/projects/project-a.md`
- [ ] Add tasks to file
- [ ] Run `:GtaskSync`
- [ ] **Expected**: File discovered and synced

### 10.2 Nested Subdirectories
- [ ] Create `~/gtask-test/work/2025/january.md`
- [ ] Add tasks
- [ ] Run `:GtaskSync`
- [ ] **Expected**: File discovered and synced

### 10.3 Ignore Directory Pattern
- [ ] Configure: `ignore_patterns = { "archive" }`
- [ ] Create `~/gtask-test/archive/old.md` with tasks
- [ ] Create `~/gtask-test/current.md` with tasks
- [ ] Run `:GtaskSync`
- [ ] **Expected**: `current.md` synced
- [ ] **Expected**: `archive/old.md` ignored

### 10.4 Ignore File Pattern
- [ ] Configure: `ignore_patterns = { "draft.md" }`
- [ ] Create `~/gtask-test/draft.md` with tasks
- [ ] Create `~/gtask-test/final.md` with tasks
- [ ] Run `:GtaskSync`
- [ ] **Expected**: `final.md` synced
- [ ] **Expected**: `draft.md` ignored

### 10.5 Non-Markdown Files Ignored
- [ ] Create `~/gtask-test/notes.txt` with task-like content
- [ ] Run `:GtaskSync`
- [ ] **Expected**: File ignored (only `.md` files processed)

---

## 11. Error Handling

### 11.1 Network Error During Sync
- [ ] Disconnect from internet
- [ ] Run `:GtaskSync`
- [ ] **Expected**: Error message about network failure
- [ ] **Expected**: Sync does not corrupt data
- [ ] Reconnect internet
- [ ] Run `:GtaskSync`
- [ ] **Expected**: Sync succeeds

### 11.2 Invalid OAuth Token
- [ ] Corrupt token file: Edit `~/.local/share/nvim/gtask_tokens.json` with invalid data
- [ ] Run `:GtaskSync`
- [ ] **Expected**: Error about authentication
- [ ] **Expected**: Prompt to run `:GtaskAuth`

### 11.3 Markdown Directory Doesn't Exist
- [ ] Configure: `markdown_dir = "~/nonexistent"`
- [ ] Run `:GtaskSync`
- [ ] **Expected**: Directory created automatically OR error message

### 11.4 Markdown Directory Not Absolute Path
- [ ] Configure: `markdown_dir = "relative/path"`
- [ ] Run `:GtaskSync`
- [ ] **Expected**: Error about absolute path required

### 11.5 File Permission Error
- [ ] Create read-only file: `chmod 444 ~/gtask-test/readonly.md`
- [ ] Try to sync task to it
- [ ] **Expected**: Error message about write permissions

### 11.6 Corrupted Mapping File
- [ ] Edit `gtask_mappings.json` with invalid JSON
- [ ] Run `:GtaskSync`
- [ ] **Expected**: Error or mapping file reset

### 11.7 Google Tasks API Rate Limit
- [ ] Create 100+ tasks in markdown
- [ ] Run `:GtaskSync`
- [ ] **Expected**: Sync handles rate limiting gracefully (retries or batches)

---

## 12. Concurrent Sync Prevention

### 12.1 Sync Already Running
- [ ] Run `:GtaskSync`
- [ ] Immediately run `:GtaskSync` again (before first completes)
- [ ] **Expected**: Second sync blocked with message "Sync already in progress"

---

## 13. Configuration Changes

### 13.1 Change Markdown Directory
- [ ] Initial setup with `markdown_dir = "~/gtask-test-old"`
- [ ] Create tasks and sync
- [ ] Change to `markdown_dir = "~/gtask-test-new"`
- [ ] Restart Neovim
- [ ] Run `:GtaskSync`
- [ ] **Expected**: New directory used
- [ ] **Expected**: Tasks from Google written to new directory

### 13.2 Change Proxy URL
- [ ] Configure custom `proxy_url`
- [ ] Run `:GtaskAuth`
- [ ] **Expected**: Uses new proxy URL

---

## 14. Stress Tests

### 14.1 Large Number of Tasks
- [ ] Create file with 500 tasks
- [ ] Run `:GtaskSync`
- [ ] **Expected**: All tasks synced
- [ ] **Expected**: Reasonable performance (< 60 seconds)

### 14.2 Large Number of Lists
- [ ] Create 50 markdown files with different list names
- [ ] Run `:GtaskSync`
- [ ] **Expected**: All lists synced
- [ ] **Expected**: All lists appear in Google Tasks

### 14.3 Deeply Nested Subtasks
- [ ] Create task with 10 levels of nesting
- [ ] Run `:GtaskSync`
- [ ] **Expected**: Hierarchy synced correctly

---

## 15. Round-Trip Tests

### 15.1 Markdown → Google → Markdown
- [ ] Create `roundtrip.md` with tasks
- [ ] Run `:GtaskSync`
- [ ] Delete `roundtrip.md`
- [ ] Run `:GtaskSync`
- [ ] **Expected**: File recreated with same tasks
- [ ] **Expected**: Content matches original

### 15.2 Google → Markdown → Google
- [ ] Create tasks in Google Tasks
- [ ] Run `:GtaskSync` (writes to markdown)
- [ ] Delete all tasks from Google Tasks
- [ ] Run `:GtaskSync`
- [ ] **Expected**: Tasks recreated in Google from markdown

### 15.3 Edit in Both Places
- [ ] Edit task title in markdown
- [ ] Edit same task's description in Google
- [ ] Run `:GtaskSync`
- [ ] **Expected**: Both changes preserved (title from markdown, description from Google)

---

## Test Summary Template

After completing tests, record results:

```
Date: _____________
Tester: _____________
Plugin Version: _____________

Total Tests: ___
Passed: ___
Failed: ___
Skipped: ___

Failed Tests:
1. [Test ID] - [Issue Description]
2. ...

Notes:
- ...
```

---

## Known Limitations (Document, Don't Test as Failures)

1. **Time Component Ignored**: Google Tasks API only stores dates, not times
2. **One Sync for Mapping**: Tasks created in Google need one sync to create mapping before deletion detection works
3. **Position-Based Tracking**: Task positions matter for mapping; extensive reordering may cause confusion
4. **No Offline Support**: Requires internet connection for all operations
5. **Single Account**: Only one Google account supported per Neovim instance
