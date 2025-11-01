<br />
<div style="width:100%" align="center"> <img src="./logo.svg" alt="gtask.nvim Image"> </div>
<h1 align="center">gtask.nvim</h1>
<p align="center"><strong>Google Tasks in Neovim (Under Construction)</strong></p>
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

### Basic Usage

1. **Authenticate**: Run `:GtaskAuth` and visit the URL in your browser
2. **Create tasks** in markdown files (see format below)
3. **Sync**: Run `:GtaskSync` to sync with Google Tasks

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

## Configuration

All options are optional. Heh.

```lua
require("gtask").setup({
  markdown_dir = "~/gtask.nvim",              -- Where to store markdown files
  proxy_url = "https://app.priteshtupe.com/gtask",  -- OAuth proxy (default is fine)
  ignore_patterns = { "archive", "draft.md" },    -- Files/dirs to skip
})
```

## Commands

- **`:GtaskAuth`** - Authenticate with Google (one-time setup)
- **`:GtaskSync`** - Sync markdown files with Google Tasks

## Known Issues & Limitations

- **No conflict resolution**: Simultaneous edits are not detected. Markdown is always considered source of truth during sync.
- **Manual sync only**: No automatic background sync. You must run `:GtaskSync` manually. Or use an autocommand on entering directory.
- **Task matching**: Uses position-based tracking with some recovery heuristics, but some weird issues like duplicates or new tasks could crop up in edge cases.
- Please open an issue if you find more... :)

## Wiki

### Testing

```bash
# To install dependencies: make install-deps
make test
```

See [tests/README.md](tests/README.md) for detailed testing documentation.

### Configuration Options

- `markdown_dir` (string): **Absolute path** to your markdown directory. Default: `~/gtask.nvim`. Must start with `/` or `~` (no relative paths like `./notes`)
- `proxy_url` (string): URL of your OAuth proxy backend. Default: `https://app.priteshtupe.com/gtask`
- `ignore_patterns` (string[]): List of directory names or `.md` file names to ignore when scanning. Directory names will skip entire subdirectories, file names will skip specific markdown files. Default: `{}`

### Authentication & Security

The plugin uses a secure OAuth proxy service for authentication. No manual Google Cloud setup required!

**Authentication Flow:**

1. Run `:GtaskAuth` in Neovim
2. The auth URL is displayed in `:messages` and copied to your clipboard
3. Visit the URL in your browser and complete Google OAuth consent (you'll see an "unverified app" warning - see why below)
4. Authentication completes automatically - return to Neovim

**Note:** You only need to authenticate once. Tokens are stored securely in Neovim's data directory and refreshed automatically.

#### Why "Unverified App" Warning?

When you authenticate, Google will show a warning that gtask.nvim is an "unverified app". This is **expected** - here's why:

**What "unverified" means:**

- Google requires apps to go through a security verification process before removing this warning
- Verification is designed for commercial apps and requires:
  - Formal security audits ($15,000-$75,000 cost)
  - Legal documentation (privacy policies, terms of service)
  - Company information and compliance certifications
  - Ongoing compliance reviews

**Why gtask.nvim is unverified:**

- This is a small open-source personal project, not a commercial application
- The verification process is prohibitively expensive and time-consuming for hobby projects
- Many legitimate open-source tools remain unverified for this reason

**Is it safe to proceed?**

- **Yes!** The code is open source - you can review exactly what it does
- The OAuth proxy only handles authentication - it never sees or stores your task data
- Your tasks sync directly between Neovim and Google's servers
- Tokens are stored locally on your machine only
- You may also host the backend server yourself and eliminate all third-parties

**How to proceed:**

1. Click "Advanced" on the warning screen
2. Click "Go to gtask.nvim (unsafe)"
3. Grant the requested permissions (read/write access to Google Tasks only)

The "unsafe" label is Google's standard warning for unverified apps - it doesn't mean the app is actually unsafe.

### Markdown Task Format

Tasks use standard markdown checkbox syntax!**Format Rules:**

- **List name**: H1 heading (`# Name`) becomes Google Tasks list name (filename is auto-normalized to lowercase with hyphens)
- **Task hierarchy**: Subtasks must be indented alteast 2 spaces from their parent
- **Task descriptions**: Any non-task, non-empty line following a task becomes its description (no strict indentation required)
- **Checkbox format**: `- [ ]` for incomplete, `- [x]` for completed
- **Due dates**: Optional `| YYYY-MM-DD` or `| YYYY-MM-DD HH:MM` after task title
  - Time is optional; if omitted, defaults to midnight UTC
  - When syncing from Google, time is only shown if not midnight
- **Blank lines**: One blank line may separate a task from its description

### 2-Way Sync

`:GtaskSync` performs intelligent bidirectional synchronization:

1. **Scans your markdown directory** (default: `~/gtask.nvim`, or configured in `setup()`) for all `.md` files recursively
2. **Fetches all Google Task lists** from your account
3. **Groups tasks by H1 heading** (list name)
4. **For each list**:
   - Finds or creates the list in Google Tasks
   - Fetches existing tasks from that list
   - Syncs in both directions:
     - Tasks in markdown but not in Google → Created in Google Tasks
     - Tasks in Google but not in markdown → Written to `[normalized-list-name].md`
     - Tasks in both locations → Updated to match (markdown is source of truth)

**Important Notes:**

- Tasks are matched by title. If you rename a task in markdown, it will be treated as a new task.
- Filenames are auto-normalized (e.g., "My Shopping List" → `my-shopping-list.md`) to prevent duplicates
- The H1 heading in the file preserves the original list name from Google Tasks
- The markdown directory is created automatically if it doesn't exist
- Files/directories matching `ignore_patterns` are skipped during scanning

### Example Workflows

**Starting from Google Tasks (pulling down existing tasks):**

```bash
# 1. Authenticate once
:GtaskAuth

# 2. Run sync to pull tasks from Google
:GtaskSync
```

After syncing:

- Tasks from each Google Tasks list will be written to separate files: `~/gtask.nvim/[ListName].md`
- You can then:
  - Review and organize these tasks
  - Move them to your own markdown files
  - Edit and re-sync to update Google Tasks
  - Keep the files for continued syncing

**Starting from markdown (pushing up new tasks):**

```bash
# 1. Authenticate once
:GtaskAuth

# 2. Create a markdown file in ~/gtask.nvim/ (or your configured directory)
# File: ~/gtask.nvim/shopping-list.md

# Shopping List
- [ ] Buy milk | 2025-01-15
- [ ] Get eggs
    Remember to get organic eggs

# 3. Sync anytime
:GtaskSync
```

After syncing:

- A "Shopping List" will be created (or found) in Google Tasks
- Your tasks will be synced with due dates and descriptions
- Any tasks from Google Tasks will appear in `[ListName].md` files
