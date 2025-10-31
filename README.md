<br />
<div style="width:100%" align="center"> <img src="./logo.svg" alt="gtask.nvim Image"> </div>
<h1 align="center">gtask.nvim</h1>
<p align="center"><strong>Google Tasks in Neovim (Under Construction)</strong></p>
<hr />
<br />

## Motivation

Over time, I have consolidated all my stuff into neovim - local CSVs over spreadsheet apps, markdown notes instead of the latest flavor of Evernote, journals, progress trackers, dev logs, so on and so forth.

One notable exception however has been task management. While I've tried many apps and strategies for managing my tasks, Google Tasks was one I kept returning to. It has all the features that I need (and few more), and it works well with (unfortunately, indispensable) Google Calendar. I've been _mostly_ happy with it (esp on mobile with tight integration with assistant). So why gtask.nvim?

Besides the obvious end-goal of managing my entire life from a single interface, there are a couple of pain point that I hope to address with this plugin:

First and foremost, my aim to have tasks slot into my current workflow. By that, I mean I do not plan to use it as a "separate" app or interface, rather it should fit inside notes as I take them.

For e.g., if I were to start a new note for "travel plan 3025" I would like to add tasks right inside the rest of the plan.

```markdown
# Travel Plan 3025 <-- This is a tasks list

## Let's go to Mars!

... more notes on space regulations <-- These notes are NOT saved on Google

- [ ] Check visa requirements | 2025-10-31 <-- This is a task with "title" | "due date"

  Notes on visa requirements when checking <-- This is the task's description
  - [ ] Contact Martian friend who knows stuff <-- This becomes a sub-task

    Friend's contact number: xxx-yyy-zz <-- This is sub-task's description (note the spacing)
```

One of the major issues I face is that the "description" field is extremely cumbersome to use. Unable to add any formatting, and the way it is shown is downright horrendous. In here though, it's just another markdown content block. Neat, eh? The next issue is the subtask management in official apps - they are treated as second class citizens. Here they are not.

## Installation

**Example lazy.nvim:**

```lua
{
  "p-tupe/gtask.nvim",
  dependencies = { "nvim-lua/plenary.nvim" },
}

require("gtask").setup()
```

## Configuration

The plugin works out of the box with default settings, but you can customize it:

```lua
require("gtask").setup({
  -- Absolute path to markdown directory
  markdown_dir = "~/gtask.nvim",

  -- Custom OAuth proxy backend URL
  proxy_url = "https://gtask.priteshtupe.com",

  -- Custom token storage filename
  token_file = "gtask_tokens.json",
})
```

**Configuration Options:**

- `markdown_dir` (string): **Absolute path** to your markdown directory. Default: `~/gtask.nvim`. Must start with `/` or `~` (no relative paths like `./notes`)
- `proxy_url` (string): URL of your OAuth proxy backend. Default: `localhost:3000` for local development.
- `token_file` (string): Filename for storing OAuth tokens in Neovim's data directory.

### Authentication

The plugin uses a secure OAuth proxy service for authentication. No manual Google Cloud setup required!

1. Run `:GtaskAuth` in Neovim
2. Visit the generated authorization URL in your browser
3. Complete Google OAuth consent (you'll see an "unverified app" warning - click "Advanced" → "Go to gtask.nvim (unsafe)")
4. Authentication completes automatically - return to Neovim

**Note:** You only need to authenticate once. Tokens are stored securely and refreshed automatically.

## Usage

### Available Commands

The plugin provides only two simple commands:

- **`:GtaskAuth`** - Authenticate with Google (clears any previous authentication and forces re-auth)
- **`:GtaskSync`** - Perform 2-way sync between your markdown directory and Google Tasks

That's it! Simple and focused.

## How It Works

**Task List Names:** The H1 heading (`# My List Name`) in each markdown file becomes the Google Tasks list name. Tasks are automatically synced to lists matching their H1 heading.

**Due Dates:** Add due dates to tasks using the format: `- [ ] Task title | YYYY-MM-DD`

**2-Way Sync:** `:GtaskSync` performs intelligent bidirectional synchronization:

1. **Scans your markdown directory** (default: `~/gtask.nvim`, or configured in `setup()`) for all `.md` files recursively
2. **Groups tasks by H1 heading** (list name)
3. **For each list**:
   - Finds or creates the list in Google Tasks
   - Fetches existing tasks from that list
   - Syncs in both directions:
     - Tasks in markdown but not in Google → Created in Google Tasks
     - Tasks in Google but not in markdown → Written to `[ListName].md`
     - Tasks in both locations → Updated to match (markdown is source of truth)

> Tasks are matched by title. If you rename a task in markdown, it will be treated as a new task.

**Example Workflow (starting from tasks already present in Google Tasks):**

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

**Example Workflow (starting from scratch with markdown):**

```bash
# 1. Authenticate once
:GtaskAuth

# 2. Create a markdown file in ~/gtask.nvim/ (or your configured directory)
# File: ~/gtask.nvim/shopping.md

# Shopping List
- [ ] Buy milk | 2025-01-15
- [ ] Get eggs
    Remember to get organic eggs

# 3. Sync anytime
:GtaskSync
```

After syncing:

- A "Shopping List" will be created (or found) in Google Tasks
- Your tasks will be synced with due dates
- Any tasks from Google Tasks will appear in `[ListName].md` files
