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
- `f│x` (delete separator char): **Mitigated** by `\x1f` conceal refactor — user types `f│` but the buffer contains `\x1f`, so `f` can't find it. However `J` still merges lines regardless.
- `D` (delete to EOL): Clears the last cell. Acceptable — detected as an update.
- `:%s/pattern/replacement/g`: Works correctly but is a footgun — it can rename slugs (triggering file moves + wikilink patches) if the pattern matches the slug column. Always preview with `:%s/pattern/replacement/gc` (confirm each).
- `ggdG` (clear buffer): Safety cap refuses to delete more than 100 notes. Safe.

### Extmark identity and the diff engine

- Each line in the process buffer has an extmark carrying the note's slug identity. The diff engine compares current cell values against a snapshot (captured at buffer open time) to detect updates, creates, deletes, and renames.
- The **slug column** is the primary identity source (line text matched against snapshot keys). Extmark slug is the secondary fallback. Title-based matching is a last-resort tertiary fallback.
- `ddp` (swap lines) is safe — extmarks follow the lines, no data diff detected.
- `yyp` (paste) creates lines without extmarks → detected as new notes (creates).
- Editing the slug column triggers **rename detection** (file move + wikilink patch), not an update.
- **Create+delete false pairing**: Inserting a new line can cause nearby extmarks to drift. If the diff sees 1 create and 1 delete (counts ≤5 and equal), it pairs them as a rename. This can cause an unrelated note to be renamed. `gu` correctly reverses it, but the save itself is destructive. Be aware when testing creates near other notes.

### Scanner caching after undo/restore

- The vault scanner caches file paths. After `gu` restores a deleted/renamed file, the scanner cache may not include it. The `M.reload(bufnr)` after undo rescans, but the count can be off by 1 if the scanner was stale.
- **Solution**: When testing undo→reopen flows, clear the scanner cache too: `package.loaded["vault.scanner"] = nil` before reopening.
- Clearing ALL `vault.*` modules works but is heavy. Prefer clearing only `vault.bases.editor` + `vault.scanner`.

### nvim_lua tool does not return values

- The `nvim_lua` MCP tool returns `"OK"` on success — the Lua return value is discarded. You cannot `return 42` and read it.
- **Solution**: Write results to `vim.g._test_result` from Lua, then read with `nvim_eval('g:_test_result')`. This is the reliable pattern for extracting data from Lua execution.
- **Gotcha**: If the Lua code errors partway through, `vim.g._test_result` keeps its previous value — making it look like the assignment never ran. Always set a sentinel value (e.g. `vim.g._test_result = "BEFORE"`) at the top to detect silent failures.

### nvim_lua silent failures

- Multi-statement Lua blocks passed to `nvim_lua` abort at the first error, with no error message returned. The tool still reports `"OK"`. The only signal is that `vim.g._test_result` didn't update.
- Common causes: `vim.cmd('normal! f...')` blocks waiting for a character; `vim.fn.search()` errors; `vim.api.nvim_buf_set_lines` triggers a TextChanged autocmd that errors.
- **Solution**: Break multi-step operations into individual `nvim_lua` calls. Set `vim.g._test_result` after each step to identify where it failed.

### Using remote-send for real user motions

- `nvim_lua` with `vim.cmd('normal! h')` does trigger CursorMoved, but chaining multiple operations in one `nvim_lua` block can fail silently if any autocmd errors.
- `nvim --server /tmp/nvim-server.sock --remote-send 'gg0253l'` is more reliable for simulating real user input — it sends keystrokes that process through the full Neovim event loop including all autocmds.
- **Avoid** `--remote-send ':command\r'` — this types into the command line and leaves artifacts. Use normal-mode keystrokes or `nvim_cmd` instead.
- After `--remote-send`, add `sleep 0.3` before querying state — keystrokes are async.

### vim.fn.confirm blocks during :write

- Delete operations trigger `vim.fn.confirm()` during BufWriteCmd. This blocks the entire RPC socket.
- **Solution**: Schedule the write, then answer the dialog:
  ```lua
  vim.schedule(function() pcall(vim.cmd, 'write') end)
  ```
  Then from Bash: `sleep 2 && nvim --server /tmp/nvim-server.sock --remote-send 'Y'`
- The confirm uses `&Yes, trash them\n&No, skip deletes\n&Cancel`. Send `Y` for yes.

### Undo system (gu) architecture

- `gu` is plugin-level undo, NOT vim's `u`. Vim undo doesn't work after `:w` because the buffer is reloaded from disk (all lines replaced).
- `snapshot_for_undo` captures raw file content BEFORE mutations. `M.undo` restores those files + reverses renames + deletes created files.
- Renames: snapshot includes the renamed file AND all files containing wikilinks to the old slug (scanned before rename). Undo reverses the `fs_rename` and restores all patched files.
- Deletes: snapshot captures the file. Undo writes it back to original path. The `.trash/` copy becomes an orphan (harmless).
- Creates: no snapshot needed. Undo deletes the created file.
- `atomic_writefile` adds a trailing newline — undo may introduce a minor whitespace diff on files that lacked a final newline.
