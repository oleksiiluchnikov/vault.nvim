- when work on bases verify it is up to date to https://help.obsidian.md/bases

## Known pitfalls for agents working on this codebase

### Neovim RPC blockers

- `vim.notify()` with `ERROR` or `WARN` level triggers "Press ENTER or type command to continue" prompts that **block the RPC socket entirely**. All subsequent tool calls (`nvim_eval`, `nvim_lua`, `nvim_screen`) will fail with `E247: connection refused` until the prompt is dismissed.
- **Solution**: Before any live testing session, override `vim.notify` to log to a file instead:
  ```lua
  vim.notify = function(msg, level, opts)
    local f = io.open('/tmp/nvim_notify.txt', 'a')
    if f then f:write(os.date() .. " [" .. tostring(level) .. "] " .. msg .. "\n"); f:close() end
  end
  ```
- `vim.fn.confirm()` (used for delete/create confirmations) also blocks RPC. You cannot answer confirmation dialogs via `nvim_lua` or `nvim_eval`. Use `nvim --server /tmp/nvim-server.sock --remote-send 'Y'` via Bash to respond.
- Lua errors in autocmd callbacks (e.g. `TextChanged`) produce native error messages that also block RPC. These are NOT caught by a `vim.notify` override. Wrap autocmd callbacks in `pcall` if they may error during testing.
- When RPC is stuck, use `nvim_dismiss` tool first. If that fails, use `nvim --server <socket> --remote-send '<CR><Esc>'` via Bash as a hard unblock.

### sign_text must be 1-2 display cells

- `nvim_buf_set_extmark` with `sign_text` longer than 2 display cells throws `Invalid 'sign_text'`. This crashed `update_diff_signs` when displaying large delete counts (e.g. `:g/pattern/d` deleting 700+ lines produced a 3-digit sign_text).
- Fixed by capping sign_text: numbers > 99 display as `##`.

### Module reload gotcha

- `package.loaded["vault.bases.editor"] = nil` clears the module but does NOT update closures already captured by autocmds (`BufWriteCmd`, `TextChanged`). If you edit `editor.lua` and reload, existing process buffers still use the old code.
- **Solution**: Always `:bwipeout!` the process buffer, THEN reload the module, THEN `:Vault process` to reopen.

### Process buffer live testing protocol

1. Always work on a **dedicated git branch** in the knowledge vault (e.g. `testing/vault-process-stress`). Never test destructive operations on main.
2. Override `vim.notify` before opening the process buffer.
3. After each test, check `/tmp/nvim_notify.txt` for save results and `git diff --stat` for actual file changes.
4. Bug reports and test artifacts go in **vault.nvim**, not in the knowledge vault — otherwise rolling back the knowledge vault to a clean state loses the reports.
5. The `title` field is purely decorative and user-optional. Never rely on it for core logic (identity, slug generation, reconciliation). The slug column is the source of truth for note identity.
6. Column order from base definitions may be non-deterministic between reopens. Do not assume a fixed column layout in tests.

### Dangerous vim motions in process buffers

- `J` (join lines): Merges two note rows into one malformed line with double separators. Causes phantom deletes.
- `f│x` (delete separator char): Breaks column parsing for that line. The line becomes unparseable.
- `:%s/pattern/replacement/g`: Works correctly but is a footgun — it can rename slugs (triggering file moves + wikilink patches) if the pattern matches the slug column. Always preview with `:%s/pattern/replacement/gc` (confirm each).
- `ggdG` (clear buffer): Safety cap refuses to delete more than 100 notes. Safe.

### Extmark identity and the diff engine

- Each line in the process buffer has an extmark carrying the note's slug identity. The diff engine compares current cell values against a snapshot (captured at buffer open time) to detect updates, creates, deletes, and renames.
- The **slug column** is the primary identity source (line text matched against snapshot keys). Extmark slug is the secondary fallback. Title-based matching is a last-resort tertiary fallback.
- `ddp` (swap lines) is safe — extmarks follow the lines, no data diff detected.
- `yyp` (paste) creates lines without extmarks → detected as new notes (creates).
- Editing the slug column triggers **rename detection** (file move + wikilink patch), not an update.
