## Markdown Format

```markdown
# Shopping List

- [ ] Buy milk | 2025-01-15
<!-- gtask:abc123 -->
- [ ] Get groceries | 2025-01-20 14:30
  <!-- gtask:xyz789 -->

  Need eggs, bread, cheese
  Check for sales
  - [ ] Organic eggs
  <!-- gtask:def456 -->
```

**Rules:**

- H1 heading → Google Tasks list name
- `- [ ]` incomplete, `- [x]` complete
- `| YYYY-MM-DD` or `| YYYY-MM-DD HH:MM` for due dates
- Subtasks: indent 2+ spaces from parent
- Descriptions: indented lines after task
- UUIDs: auto-generated `<!-- gtask:uuid -->` comments

## Auto-sync on save

```lua
vim.api.nvim_create_autocmd("BufWritePost", {
  pattern = vim.fn.expand("~/gtask.nvim") .. "/*.md",
  callback = function()
    vim.cmd(":GtaskSync")
  end,
})
```

OR

```vim
autocmd BufWritePost ~/gtask.nvim/*.md :GtaskSync
```

## Hide UUID comments

```lua
vim.api.nvim_create_autocmd("FileType", {
  pattern = "markdown",
  callback = function()
    vim.defer_fn(function()
      vim.cmd([[syntax match gtaskComment /<!--\s*gtask:[^>]*-->/ conceal]])
      vim.opt_local.conceallevel = 2
      vim.opt_local.concealcursor = "v"
    end, 0)
  end,
})
```

OR

```vim
augroup GtaskConceal
  autocmd!
  autocmd FileType markdown syntax match gtaskComment /<!--\s*gtask:[^>]*-->/ conceal
  autocmd FileType markdown setlocal conceallevel=2 concealcursor=v
augroup END
```

OR

In `~/.config/nvim/after/syntax/markdown.vim`:

```vim
syntax match gtaskComment /<!--\s*gtask:[^>]*-->/ conceal
```

Then in your config:

```vim
set conceallevel=2
set concealcursor=v
```
