<br />
<div style="width:100%" align="center"> <img src="./logo.svg" alt="gtask.nvim Image"> </div>
<h1 align="center">gtask.nvim</h1>
<p align="center"><strong>Google Tasks in Neovim!</strong></p>
<p align="center">
<img alt="GitHub tag (latest SemVer)" src="https://img.shields.io/github/v/tag/p-tupe/gtask.nvim" >
<a href="https://github.com/p-tupe/gtask.nvim/blob/main/LICENSE"><img alt="GitHub license" src="https://img.shields.io/github/license/p-tupe/gtask.nvim"></a>
<img alt="GitHub last commit" src="https://img.shields.io/github/last-commit/p-tupe/gtask.nvim">
<br />

## Motivation

Over time, I have consolidated all my stuff into neovim - local CSVs over spreadsheet apps, markdown notes instead of the latest flavor of Evernote, journals, progress trackers, dev logs, so on and so forth.

One notable exception however has been task management. While I've tried many apps and strategies for managing my tasks, Google Tasks was one I kept returning to. It has all the features that I need (and few more), and it works well with (unfortunately, indispensable) Google Calendar. I've been _mostly_ happy with it (esp on mobile with tight integration with assistant). So why gtask.nvim?

There are a couple of pain point that I hope to address with this plugin:

First and foremost, my aim to have tasks slot into my current workflow. By that, I mean I do not plan to use it as a "separate" app or interface, rather it should fit inside notes as I take them.

Another major I face is that the "description" field is extremely cumbersome to use. Unable to add any formatting, and the way it is shown is downright horrendous. In here though, it's just another markdown content block. Neat, eh? The next issue is the subtask management in official apps - they are treated as second class citizens. Here they are not.

## Quick Start

### Setup Video (v0.1)

https://github.com/user-attachments/assets/fd17810e-3a4e-4bdd-b3ae-3467d245cf5d

### Installation

**Example lazy.nvim:**

```lua
{
  "p-tupe/gtask.nvim",
  dependencies = { "nvim-lua/plenary.nvim" },
}

require("gtask").setup()
```

## Configuration

All options are optional. Heh.

```lua
-- Default Options
require("gtask").setup({
  markdown_dir = "~/gtask.nvim",                     -- Directory of markdown files
  ignore_patterns = {},                              -- Files/dirs to skip like "archive", "draft.md"
  proxy_url = "https://app.priteshtupe.com/gtask",   -- OAuth proxy
  keep_completed_in_markdown = true,                 -- Keep completed tasks in markdown even if deleted from Google Tasks
  verbosity = "error",                               -- Logging level: "error", "warn", or "info"
})
```

- `markdown_dir` : **Absolute path** to your markdown directory. Must start with `/` or `~` (no relative paths like `./notes`)
- `proxy_url` : URL of your OAuth proxy backend.
- `ignore_patterns` : List of directory names or `.md` file names to ignore when scanning. Directory names will skip entire subdirectories, file names will skip specific markdown files.
- `keep_completed_in_markdown` : When `true`, completed tasks deleted from Google Tasks will remain in your markdown files as historical records. When `false`, they will be deleted from markdown to mirror Google Tasks exactly.
- `verbosity` : Controls which log messages are displayed:
  - `"error"`: Only show error messages
  - `"warn"`: Show warnings and errors
  - `"info"`: Show all messages including info, warnings, and errors

> I recommend setting `verbosity` to `"info"` for initial setup.

### Basic Usage

1. Configure gtask.nvim using setup options if you have an existing directory or custom proxy
1. Run `:GtaskAuth` and follow the steps to authenticate
1. **Sync**: Run `:GtaskSync` to sync with Google Tasks
1. Done!

You may now update tasks in either markdown_dir or Google Tasks and :GtaskSync to synchronize them.

### Task Format

```markdown
# Travel Plan 3025 `<-- First H1 heading is the tasks list name (and the file name as well)`

## Let's go to Mars!

... more notes on space regulations `<-- These notes (list description?) are NOT saved on Google`

- [ ] Check visa requirements | 2025-10-31 `<-- Task with due date (YYYY-MM-DD)`
- [ ] Submit application | 2025-11-01 09:00 `<-- Task with due date and time (YYYY-MM-DD HH:MM)`

      Notes on visa requirements when checking `<-- This is the task's description (any spacing, optional blank line)`
      More notes here (until a double empty line is encountered)

      - [ ] Contact Martian friend who knows stuff `<-- This becomes a sub-task (indented 2 spaces)`

          Friend's contact number: xxx-yyy-zz `<-- This is sub-task's description`
```

## Known Issues

- **Duplicate Tasks** : When synced on more than one machince (or after extensive re-ordering), Google Tasks may sometimes have duplicates.
- **Task matching**: Uses **positional matching** list→task1,task2→subtask1,subtask2... Optimal use would be to simply add a new task at the end, so other tasks aren't changed. If you move a task to a different line or insert one in between, it will end up deleting/recreating the tasks that have had their positions changed.
- **File Rename**: Current behaviour for task file renames is undefined.
- Please open an issue if you find more... :)

See [gtask.nvim/wiki](https://github.com/p-tupe/gtask.nvim/wiki) for more details!
