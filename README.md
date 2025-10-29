# Gtask.nvim

> Under Construction

Google Tasks in Neovim

## Motivation

Over time, I have consolidated all my stuff into neovim - local CSVs over spreadsheet apps, markdown notes instead of the latest flavor of Evernote, journals, progress trackers, dev logs, so on and so forth.

One notable exception however has been task management. While I've tried many apps and strategies for managing my tasks, Google Tasks was one I kept returning to. It has all the features that I need (and few more), and it works well with (unfortunately, indispensable) Google Calendar. I've been _mostly_ happy with it (esp on mobile with tight integration with assistant). So why gtask.nvim?

Besides the obvious end-goal of managing my entire life from a single interface, there are a couple of pain point that I hope to address with this plugin:

First and foremost, my aim to have tasks slot into my current workflow. By that, I mean I do not plan to use it as a "separate" app or interface, rather it should fit inside notes as I take them.

For e.g., if I were to start a new note for "travel plan 3025" I would like to add tasks right inside the rest of the plan.

```
# Travel Plan 3025 <-- This is a new task list

## Let's go to Mars!

... notes on space regulations

- [ ] Check visa requirements <-- This is a task

    Notes on visa requirements when checking <-- This is the task's description

    - [ ] Contact Martian friend who knows stuff <-- This becomes a sub-task

        Friend's contact number: xxx-yyy-zz <-- This is sub-task's description (note the spacing)
```

One of the major issues I face is that the "description" field is extremely cumbersome to use. Unable to add any formatting, and the way it is shown is downright horrendous. In here though, it's just another markdown content block. Neat, eh? The next issue is the subtask management in official apps - they are treated as second class citizens. Here they are not.

## Setup

### Installation

Using your favorite plugin manager:

**lazy.nvim:**

```lua
{
  "your-username/gtask.nvim",
  dependencies = { "nvim-lua/plenary.nvim" },
  config = function()
    -- Optional configuration
  end
}
```

**packer.nvim:**

```lua
use {
  "your-username/gtask.nvim",
  requires = { "nvim-lua/plenary.nvim" }
}
```

### Authentication

The plugin uses a secure OAuth proxy service for authentication. No manual Google Cloud setup required!

1. Run `:GtaskAuth` in Neovim
2. Visit the generated authorization URL in your browser
3. Complete Google OAuth consent (you'll see an "unverified app" warning - click "Advanced" → "Go to gtask.nvim (unsafe)")
4. Authentication completes automatically - return to Neovim

**Note:** You only need to authenticate once. Tokens are stored securely and refreshed automatically.

## Usage

### Available Commands

#### Authentication

- `:GtaskAuth` - Start OAuth authentication flow
- `:GtaskClearAuth` - Clear stored tokens (force re-authentication)
- `:GtaskAuthTest` - Test authentication server (development)

#### Task Management

- `:GtaskGetLists` - Fetch and display all task lists
- `:GtaskGetTasks <list_id>` - Fetch and print tasks for a specific list
- `:GtaskView <list_id>` - Open formatted task view in new buffer

#### Markdown Integration

- `:GtaskSync <list_id>` - Sync markdown tasks from current buffer to Google Tasks

### Task-only Workflow

View and manage Google Tasks directly within Neovim:

1. **Get your task lists:** `:GtaskGetLists`
2. **View tasks:** `:GtaskView <list_id>`
3. **Manage tasks:** Use the formatted view with hierarchical sorting by due date

The task view displays:

- Tasks grouped by due date
- Subtasks under their parent tasks
- Completion status and descriptions
- Clean markdown formatting

### Integrated Workflow

Manage tasks directly in your markdown files:

1. **Create tasks in markdown:**

```markdown
# My Project Notes

- [ ] Main task with due date
      Description for the main task
  - [ ] Subtask one
  - [x] Completed subtask
- [ ] Another task
      Additional notes about this task
```

2. **Sync with Google Tasks:** `:GtaskSync <list_id>`

**Task Format:**

- `- [ ]` for incomplete tasks
- `- [x]` for completed tasks
- Indented lines become task descriptions
- Nested tasks become subtasks

### Features

- **Secure Authentication** - OAuth proxy service handles credentials
- **Automatic Token Refresh** - Seamless re-authentication when needed
- **Hierarchical Task Display** - Subtasks grouped under parents, sorted by due date
- **Markdown Integration** - Convert markdown task lists to Google Tasks
- **Offline Support** - View cached tasks when offline
- **No Manual Setup** - No Google Cloud configuration required

### Security & Privacy

- **No credentials stored locally** - Uses secure OAuth proxy
- **Tokens encrypted** - Stored securely in Neovim's data directory
- **No data logging** - Proxy service doesn't store or log your tasks
- **Standard OAuth flow** - Industry-standard authentication
