# Sync System

## How It Works

`:GtaskSync` performs UUID-based bidirectional sync:

1. **Scans** markdown directory for `.md` files (respects `ignore_patterns`)
2. **Fetches** all Google Task lists
3. **Groups** tasks by H1 heading (list name)
4. **Matches** tasks by UUID (or title for migration)
5. **Syncs** bidirectionally with timestamp-based conflict resolution

## UUID Tracking

Each task gets a unique ID:

```markdown
- [ ] Task title
<!-- gtask:abc123 -->
```

- **Auto-generated** during first sync
- **Stable** across renames, moves, edits
- **Hidden** with conceal (see Home#hide-uuid-comments)
- **Embedded** as HTML comment (invisible when rendered)

## Sync Operations

### Create

**Markdown → Google:** New task without UUID → create in Google, embed UUID
**Google → Markdown:** New Google task → write to `[list-name].md` with UUID

### Update

**Conflict resolution:** Compare `google_task.updated` vs `mapping.google_updated`

- Google newer → update markdown
- Otherwise → update Google

**What syncs:** Title, status, description, due date
**What doesn't:** Order, creation time, links, attachments

### Delete

**Markdown → Google:** Missing UUID in markdown → delete from Google
**Google → Markdown:**

- Incomplete tasks → delete from markdown
- Completed tasks → depends on `keep_completed_in_markdown` (default: keep)

## Subtasks

Parent-child relationships preserved:

```markdown
- [ ] Parent
  <!-- gtask:parent123 -->
  - [ ] Child (2+ space indent)
  <!-- gtask:child456 -->
```

**Two-pass creation:**

1. Create all top-level tasks first
2. Create subtasks with parent references

## Mapping File

`~/.local/share/nvim/gtask_mappings.json` stores sync state:

```json
{
  "lists": { "Shopping": "google_list_id_123" },
  "tasks": {
    "abc123": {
      "google_id": "gtask_456",
      "list_name": "Shopping",
      "file_path": "/path/to/shopping.md",
      "parent_uuid": null,
      "google_updated": "2025-01-15T10:00:00Z",
      "last_synced": "2025-01-15T10:05:00Z"
    }
  }
}
```
