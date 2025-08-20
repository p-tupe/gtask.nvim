# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Gtask.nvim is a Neovim plugin that integrates Google Tasks into the editor. The plugin provides two main workflows:

1. **Task-only Workflow**: View and manage Google Tasks in formatted buffers within Neovim
2. **Integrated Workflow**: Sync markdown task lists with Google Tasks

## Key Architecture Components

### Core Modules Structure
- `lua/gtask/init.lua`: Main module entry point (minimal implementation)
- `lua/gtask/config.lua`: Google OAuth credentials and API configuration
- `lua/gtask/auth.lua`: OAuth 2.0 authentication flow with local server
- `lua/gtask/api.lua`: Google Tasks API client with token refresh handling and CRUD operations
- `lua/gtask/store.lua`: Token persistence to Neovim's data directory
- `lua/gtask/view.lua`: Task rendering with hierarchical sorting by due date
- `lua/gtask/parser.lua`: Markdown task parser for integrated workflow
- `lua/gtask/sync.lua`: Bidirectional sync between markdown and Google Tasks
- `plugin/gtask.lua`: Neovim command definitions

### Authentication Flow
The plugin uses OAuth 2.0 via a secure proxy backend service. Users authenticate through a browser-based flow that redirects to the proxy service, which handles all credential exchange securely. The plugin polls the backend for completion and receives tokens once authentication succeeds. Tokens are stored in `vim.fn.stdpath("data")/gtask_tokens.json`. The API module handles automatic token refresh via the proxy service when access tokens expire.

### Task Rendering Philosophy
Tasks are displayed hierarchically sorted by due date, with subtasks grouped under their parents rather than being scattered by individual due dates. This addresses the author's specific workflow preference outlined in the README.

### Integrated Workflow Implementation
The parser recognizes markdown tasks with the pattern `- [ ] Task title` and `- [x] Completed task`. Task descriptions are indented lines following the task (without `>` prefix). The sync module performs one-way sync from markdown to Google Tasks, creating new tasks and updating existing ones based on title matching.

## Available Commands

### Task-only Workflow
- `:GtaskAuth` - Initiates OAuth authentication flow
- `:GtaskClearAuth` - Clear stored authentication tokens to force re-authentication
- `:GtaskAuthTest` - Test authentication server functionality
- `:GtaskGetLists` - Fetch and display all task lists
- `:GtaskGetTasks <id>` - Fetch and print tasks for a given list ID
- `:GtaskView <id>` - Render formatted task view for a specific list

### Integrated Workflow
- `:GtaskSync <id>` - Sync markdown tasks from current buffer with Google Tasks list

## Dependencies

The plugin requires:
- `plenary.nvim` for async job handling and HTTP requests
- `curl` system command for API requests
- Neovim's built-in `vim.loop` for the local OAuth server

## Development Status

Current implementation status:

### Completed Features
- **Secure Proxy Authentication**: OAuth 2.0 flow via backend proxy service - no user setup required
- **API Core**: Authenticated API calls with automatic token refreshing via proxy, can fetch, create, and update tasks
- **Custom Task View**: `:GtaskView` command fetches tasks and displays them in a new buffer, sorted hierarchically by due date, includes descriptions and completion status
- **Integrated Markdown Workflow**: Parser and sync functionality to convert markdown tasks to Google Tasks
- **Backend Proxy Service**: Go-based OAuth proxy that handles credentials securely, supports PKCE, includes polling endpoints for seamless UX

### Implementation Status
Both major objectives are now complete:
1. **Task-only Workflow**: Fully implemented with viewing and management commands
2. **Integrated Markdown Workflow**: Basic implementation complete with one-way sync (markdown → Google Tasks)
3. **Production-Ready Authentication**: Secure proxy backend eliminates user setup requirements

## Security Notes

- **No credentials in plugin code** - OAuth credentials handled by secure backend proxy
- **User tokens only** - Access/refresh tokens are persisted locally in Neovim's data directory
- **PKCE implementation** - Backend uses Proof Key for Code Exchange for enhanced security
- **Polling-based flow** - No local server required, eliminates port conflicts
- **Temporary state storage** - Backend stores PKCE states temporarily (10 minute expiry) for security