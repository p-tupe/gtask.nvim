# Authentication

Uses OAuth proxy - no Google Cloud setup needed.

## Steps

1. `:GtaskAuth` in Neovim
2. URL appears in `:messages` and copied to clipboard
3. Visit URL in browser → complete Google OAuth
4. Return to Neovim (auto-completes)

Tokens stored in `~/.local/share/nvim/gtask_tokens.json`, auto-refresh.

## "Unverified App" Warning

Google shows this because verification costs $15k-$75k. Not worth it for hobby projects.

**Safe?** Yes:
- Open source code (review it yourself)
- Proxy only handles OAuth (never sees your tasks)
- Tasks sync directly: Neovim ↔ Google
- Tokens stored locally only
- Can self-host backend

**Proceed:**
1. Click "Advanced"
2. "Go to gtask.nvim (unsafe)"
3. Grant permissions (Google Tasks read/write only)
