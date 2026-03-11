# Telescope Picker Consolidation Plan

Date: 2026-03-01
Branch: main

## Problem

- `on_input_filter_cb` copy-pasted in 7 pickers (~420 lines of duplication)
- Gradient highlight setup copy-pasted in 9 pickers (~135 lines of duplication)
- `entry_maker.lua` is broken and unused
- `on_input_filter.lua` exists but is never imported
- `mappings.lua` missing sets for: tasks, lines, wikilinks, dates, move_to
- `previewers.lua` missing: properties, tasks, dirs, lines, dates
- `layouts.lua` missing: properties, tasks, dirs, lines, wikilinks, dates
- `dirs` picker has wrong action import (uses vault meta-picker enter instead of directory enter)
- `wikilinks` picker is 695 lines — too large

## Execution chunks

### Chunk 1: Wire shared on_input_filter into all pickers
- Verify `on_input_filter.lua` works as drop-in replacement
- Replace inlined copies in: notes, tags, properties, property_values, dirs, lines, wikilinks
- Commit: <pending>

### Chunk 2: Extract shared gradient highlight setup
- Create `telescope/_ext/vault/highlights.lua` with `setup_gradient(hl_prefix, stops)` + `cleanup(hl_prefix, count)`
- Replace inlined gradient setup in: notes, tags, properties, property_values, tasks, dirs, lines, wikilinks, bases
- Commit: <pending>

### Chunk 3: Fix entry_maker.lua + extract counted entry pattern
- New `entry_maker.lua` with `M.counted()` factory for 2-column (name+count) displayer
- Refactored tags, properties, dirs pickers to use shared entry_maker
- Dirs picker pre-computes counts once instead of per-display-call
- Commit: `6d1f2e0`

### Chunk 4: Complete mappings + fix dirs bug
- Added `M.vault` mapping set to `mappings.lua`
- Wired vault meta-picker `pickers/vault/init.lua` to use shared `M.vault` instead of inline `attach_mappings`
- Commit: `5909e70`

### Chunk 5: Split wikilinks picker
- Extracted merge sub-picker into `pickers/wikilinks/merge.lua` (200 lines)
- `actions.lua` shrunk from 609 → 457 lines
- Commit: `330884d`

---

# Migrate Blocking Prompts to NUI Floating Popups

Date: 2026-03-01
Branch: main

## Problem

12 call sites across the codebase use `vim.fn.confirm` or `vim.ui.select` for user confirmations. These block the Neovim RPC socket, preventing all MCP tool calls (`nvim_eval`, `nvim_lua`, `nvim_screen`) from working until the prompt is dismissed. They also look ugly compared to the rest of the floating UI.

## New module: `lua/vault/ui/confirm.lua`

Shared, reusable NUI-based floating popup module with two functions:

### `M.confirm(opts)` — Yes/No

```lua
require("vault.ui.confirm").confirm({
    message = "Delete note 'foo'?",
    title = "Vault",              -- optional, shown in border
    on_yes = function() ... end,
    on_no = function() ... end,   -- optional, called on n/Esc/q
})
```

### `M.select(opts)` — Multi-choice

```lua
require("vault.ui.confirm").select({
    message = "About to TRASH 3 notes:\n  - foo\n  - bar",
    title = "Vault process",
    choices = {
        { key = "y", label = "Yes, trash them",  action = function() ... end },
        { key = "n", label = "No, skip deletes",  action = function() ... end },
        { key = "c", label = "Cancel",             action = function() ... end },
    },
    on_cancel = function() end,  -- Esc / q
})
```

### Behavior
- Auto-sizes from message content (width = max line + padding, capped at 80)
- Rounded border with optional title
- Single-char hotkeys (case-insensitive), `<CR>` = first choice, `<Esc>`/`q` = cancel
- NUI fallback: if `nui.popup` not available → `vim.ui.select` (async, not blocking)
- Auto-close on `BufLeave`
- Returns `{ close = fun() }` handle for programmatic dismissal

### Highlight groups
- `VaultConfirmBorder` → `FloatBorder`
- `VaultConfirmTitle` → `FloatTitle`
- `VaultConfirmKey` → `Special` (the `[y]` hotkey brackets)
- `VaultConfirmDanger` → `DiagnosticError`

## Migration targets

### Group A: Simple async call sites (no return-value dependency)

| # | File | Line | Current | Replacement |
|---|------|------|---------|-------------|
| 1 | `wikilinks/actions.lua` | 58 | `vim.fn.confirm(msg, "&Yes\n&No", 2)` | `confirm.confirm({ message, on_yes, on_no })` |
| 2 | `wikilinks/actions.lua` | 538 | `vim.ui.select({"Create all", "Resolve", "Cancel"})` | `confirm.select({ choices=[3] })` |
| 3 | `telescope/actions.lua` | 211 | `vim.fn.confirm("Delete N?", "&Trash\n&Perm\n&Cancel", 3)` | `confirm.select({ choices=[3] })` |
| 4 | `commands/init.lua` | 220 | `vim.fn.confirm("Delete note?", "&Yes\n&No", 2)` | `confirm.confirm({ on_yes, on_no })` |
| 5 | `commands/init.lua` | 763 | `vim.fn.confirm("Note: X", "&Restore\n&Delete\n&Cancel", 3)` | `confirm.select({ choices=[3] })` |
| 6 | `watcher/init.lua` | 287 | `vim.fn.confirm("Rename patch N files?", "&Yes\n&No", 2)` | `confirm.confirm()` + move apply logic into `on_yes` callback |

### Group B: Dedup resolver.lua

| # | File | Line | Current | Replacement |
|---|------|------|---------|-------------|
| 7 | `resolver.lua` | 48 | Inline NUI popup (63 lines) | Replace with `confirm.confirm()` import |

### Group C: editor.lua async write guard (hardest)

| # | File | Line | Current | Replacement |
|---|------|------|---------|-------------|
| 8 | `editor.lua` | 2266 | `vim.fn.confirm("CREATE N notes?", 3 choices)` | `confirm.select()` with write guard |
| 9 | `editor.lua` | 2458 | `vim.fn.confirm("TRASH N notes?", 3 choices)` | `confirm.select()` with write guard |

## editor.lua async write guard design

### Problem
`on_save(bufnr)` is called from `BufWriteCmd` (synchronous). The two `vim.fn.confirm` calls
block intentionally — the write can't proceed until the user decides. Making them async means
`:w` returns immediately and the popup appears after.

### Solution: split on_save into sync detection + async confirmation

**Fast path (no confirmation needed):** apply immediately, synchronous. No change to `:w` semantics. This covers 99% of saves.

**Slow path (creates > 5 or any deletes):**

1. Set `st.saving = "confirming"` (existing `st.saving` guard blocks re-entry — string is truthy)
2. Set `vim.bo[bufnr].modified = false` immediately ("write accepted, confirming details")
3. Register one-shot `TextChanged` autocmd → auto-cancel if buffer edited during popup
4. Show NUI popup via `confirm.select()`
5. On choice:
   - **Yes**: apply mutations → `M.reload(bufnr)` → `st.saving = false`
   - **Skip deletes/creates**: modify diff → apply → reload → `st.saving = false`
   - **Cancel**: `vim.bo[bufnr].modified = true` (re-dirty) → `st.saving = false`

### State machine

```
st.saving: false → true → "confirming" → (apply) → false
                                ↓
                             false (cancel / TextChanged)
```

Guard: `if st.saving then return end` — works because strings are truthy in Lua.

### Safety invariants

---

# Great Refactor Plan

Date: 2026-03-11
Branch: main

Reference: `docs/architecture-refactor-blueprint.md`

## Goal

- preserve noun-owned architecture
- keep `grid` as the shared view primitive
- remove central-dispatcher and central-facade drift
- export hardcoded and preferred policy into config
- preserve the intentional `note.data` boundary

## Architectural invariants

- one owning package per noun
- one shared `views/` package
- one command registry
- `note` = behavior
- `note.data` = structured file-backed payload
- `notes` = collection/query layer
- no literal `domain/` tree
- no mirrored `workflows/` or `capabilities/` trees
- no new features added to `vault.api`

## Execution chunks

### Chunk 0: Freeze contracts before moving files
- Add architectural comments and docs around `note` / `note.data` / `notes`
- Define the command registry shape and command spec format
- Define package-owned config reader pattern
- Commit target: contract-only, no behavior change
- Status: done (`aff7668`)

### Chunk 1: Introduce command registry
- Add `lua/vault/commands/registry.lua`
- Add package-local `commands.lua` for one pilot noun, preferably `taxonomy`
- Keep old `:Vault` forms working through aliases
- Remove no behavior yet from the central dispatcher beyond routing
- Status: done (`aff7668`)

### Chunk 2: Introduce package-owned config readers
- Add readers for `taxonomy`, `tasks`, and `views.grid`
- Move hardcoded defaults into normalized config shape without behavior changes
- Resolve duplicated toggles like watcher enablement precedence
- Commit target: config extraction, no UX breakage
- Status: done (`aff7668`)

### Chunk 3: Extract shared views
- Move genuinely generic code from `bases/views/*` into `views/*`
- Start with `grid` and `shared`
- Keep compatibility require shims during migration
- Commit target: generic views no longer owned by `bases`
- Status: done (`90c4e2f`)

### Chunk 4: Split task policy from task workflows
- Extract `tasks/policy.lua` from `tasks/notes.lua`
- Move statuses, aliases, transitions, recurrence grammar, and defaults behind policy/config helpers
- Add `tasks/create.lua` and `tasks/paths.lua`
- Commit target: `tasks/notes.lua` stops being the junk-drawer module
- Status: done (`869c75c`)

### Chunk 5: Split taxonomy by verb while preserving noun ownership
- Create `taxonomy/classify.lua`, `taxonomy/audit.lua`, `taxonomy/plan.lua`, `taxonomy/rename.lua`
- Add `taxonomy/commands.lua`
- Keep `taxonomy/init.lua` as the noun facade
- Commit target: taxonomy owns taxonomy, not a mixed mega-module
- Status: done (`c8e5c7d`)

### Chunk 6: Centralize note creation and path policy
- Add `notes/paths.lua` and `notes/create.lua`
- Replace duplicated `root .. "/" .. slug .. ext` logic with helpers
- Export journal naming and generated slug policy into config
- Commit target: commands/views stop inventing paths independently
- Status: done (`21afdba`)

### Chunk 7: Shrink the old central surfaces
- Make `commands/init.lua` registration + dispatch only
- Keep `vault.api` as compatibility shim only
- Stop adding features to the shim
- Commit target: architecture no longer depends on stale global facades
- Status: done (`4b4970b`)

## Verification summary

- Chunks 0 through 7 have been executed.
- The command suite passes after each structural chunk.
- `vault.api` still exists, but it is now explicitly compatibility-first rather than the architectural center.
- `notes.data` remains intact as the payload boundary.
- Shared views now live behind `vault.views.*` with compatibility shims.
- Task policy, taxonomy verbs, note creation, and note path policy have all been extracted into owning modules.

## Remaining frontier

The original great-refactor plan is materially complete through Chunk 7.

Useful follow-up work now lives in cleanup / convergence rather than core restructuring:

1. Add package-local command specs for more nouns (`notes`, `tags`, `tasks`, `bases`) so the registry owns more of the tree.
2. Export remaining note/journal naming preferences into config if they should be user-tunable.
3. Remove or archive stale planning sections once the new structure is considered stable.

## Post-migration cleanup

- Removed `lua/vault/commands/compat.lua` after the migration proved stable.
- Collapsed command-layer API access to a direct workflow helper instead of compatibility indirection.
- Removed the stale `vault.api.refresh_buffers` dependency from `notes/note/init.lua`.
- Kept `vault.api` itself as a workflow facade because several orchestration call sites still legitimately use it.
- Added package-local command specs for `notes`, `tags`, `properties`, and `bases`.
- Moved `vault.views.shared` to the real owner implementation and kept `bases/views/shared.lua` as the shim.
- Moved merge/promote/retarget workflow bodies out of `vault.api` into noun-owned workflow modules.
- Removed the remaining `bases/views/{grid,list,kanban,calendar,shared}.lua` shims entirely; `vault.views.*` is now the only owner namespace.

## First recommended implementation order

1. Chunk 0
2. Chunk 1 with `taxonomy` as the pilot package
3. Chunk 2 for `taxonomy`, `tasks`, and `views.grid`
4. Chunk 4 for task policy extraction
5. Chunk 3 for shared views extraction

Reason: this creates seams before moving the heaviest code.

## Done means

- command ownership is discoverable from package-local specs
- `note.data` survives and stays clean
- generic views are no longer hidden under `bases`
- task policy is configured and centralized
- taxonomy no longer mixes classify, audit, and rename internals in one file
- the codebase is easier for humans and LLMs to navigate without reading every file

| Scenario | Behavior |
|----------|----------|
| `:w` while popup open | Ignored (`st.saving` guard) |
| `:q` while popup open | Allowed (`modified=false`). Popup auto-closes via BufUnload |
| Buffer edited while popup open | `TextChanged` autocmd auto-cancels, re-marks `modified=true` |
| NUI not available | Fallback to `vim.ui.select` (async, not blocking) |
| Double `:w` rapid fire | Second `:w` hits guard, no-op |

### What stays unchanged
- Diff engine, mutation logic, undo system — untouched
- Fast path (no confirmation needed) — stays synchronous
- `commands/init.lua:758` `vim.ui.select` for trash file list — it's a proper picker, not a confirmation

## Progress

- [x] Create `lua/vault/ui/confirm.lua` — committed `d206f67`
- [x] Migrate Group A (6 simple call sites) — committed `d206f67` + `060af7d`
- [x] Migrate Group B (resolver.lua dedup) — committed `060af7d`
- [x] Migrate Group C (editor.lua async write guard) — committed `0c9eedd`
- [x] Fix popup focus loss + BufLeave cancel bug — committed `931a4d0`
- [x] Live test all migrated call sites — 10/10 stress tests PASSED

## Stress test results (2026-03-02)

| Test | Description | Result |
|------|-------------|--------|
| 1 | Create 6 → Cancel → verify no files + buffer re-dirtied | PASSED |
| 2 | Create 6 → Skip creates → verify only updates applied | PASSED |
| 3 | Create 6 → Yes → verify 6 .md files on disk | PASSED |
| 4 | Delete 3 → Yes → verify trashed + undo restored | PASSED |
| 5 | Delete 3 → No (skip) → verify notes survive | PASSED |
| 6 | Edit buffer while create popup open → auto-cancel via TextChanged | PASSED |
| 7 | :w while popup open → BufLeave cancels first, :w starts fresh save | PASSED |
| 8 | Rapid dd dd dd :w + mash y → popup safely accepts after focus transfer | PASSED |
| 9 | Esc to dismiss popup → cancel path fires, modified re-dirtied | PASSED |
| 10 | Create 6 + delete 2 in same save → SAFETY guard blocks mixed mutations | PASSED |

## Commits

| Hash | Description |
|------|-------------|
| `d206f67` | feat(ui): add shared NUI confirm/select popups, migrate 4 call sites |
| `060af7d` | refactor(ui): migrate 3 more vim.fn.confirm to NUI popups |
| `0c9eedd` | fix(editor): migrate save confirmations to async NUI flow |
| `931a4d0` | fix(ui): fix popup focus loss and BufLeave cancel in confirm.lua |

## Files modified

| File | Changes | Status |
|------|---------|--------|
| `lua/vault/ui/confirm.lua` | **NEW** — shared NUI confirm/select | Done |
| `lua/telescope/_extensions/vault/pickers/wikilinks/actions.lua` | Replace `confirm()` + `vim.ui.select` | Done |
| `lua/telescope/_extensions/vault/actions.lua` | Replace `vim.fn.confirm` in note delete | Done |
| `lua/vault/commands/init.lua` | Replace 2× `vim.fn.confirm` | Done |
| `lua/vault/watcher/init.lua` | Replace `vim.fn.confirm`, extract `apply_rename()` | Done |
| `lua/vault/ui/resolver.lua` | Replace inline `confirm_popup` (90 lines) with import | Done |
| `lua/vault/bases/editor.lua` | Restructure `on_save` into sync/async phases | Done |

## Final verification (2026-03-02)

`grep -r "vim.fn.confirm" lua/` returns **zero runtime matches** — only a doc comment in `confirm.lua`.

**Migration complete.**

---

## Group C: editor.lua implementation recipe

### Overview

`on_save(bufnr)` at line 2175 is called by `BufWriteCmd`. Two `vim.fn.confirm` calls block:
1. **Line 2266**: creates > 5 — 3 choices: "Yes, create them" / "No, skip creates" / "Cancel"
2. **Line 2458**: any deletes — 3 choices: "Yes, trash them" / "No, skip deletes" / "Cancel"

### Step-by-step implementation

#### 1. Upgrade `st.saving` to a state machine

Current: `st.saving` is a `boolean` (`false`/`true`).
New: `false` → `true` → `"confirming"` → `false`.

Guard at line 2182 (`if st.saving then return end`) works unchanged because `"confirming"` is truthy.

#### 2. Split `on_save` at the first confirm point (line 2264)

Everything **before** line 2264 stays synchronous — diff computation, validation warnings,
hard cap refusals, rename processing, and the no-deletes fast path.

At line 2264, instead of the current:

```lua
if #diff.creates > 5 then
    local choice = vim.fn.confirm(...)
    if choice == 3 or choice == 0 then ... return end
    if choice == 2 then diff.creates = {} end
end
```

Replace with:

```lua
if #diff.creates > 5 then
    st.saving = "confirming"
    vim.bo[bufnr].modified = false
    local cancel_id = register_textchanged_cancel(bufnr, st)
    require("vault.ui.confirm").select({
        message = string.format(
            "About to CREATE %d new notes. This seems unusual.\n\nProceed?",
            #diff.creates
        ),
        title = "Vault Process",
        choices = {
            { key = "y", label = "Yes, create them", action = function()
                cleanup_cancel(cancel_id)
                continue_save_after_creates(bufnr, st, diff, n_renamed, n_patched)
            end },
            { key = "n", label = "No, skip creates", action = function()
                cleanup_cancel(cancel_id)
                diff.creates = {}
                continue_save_after_creates(bufnr, st, diff, n_renamed, n_patched)
            end },
            { key = "c", label = "Cancel", action = function()
                cleanup_cancel(cancel_id)
                vim.bo[bufnr].modified = true
                st.saving = false
            end },
        },
        on_cancel = function()
            cleanup_cancel(cancel_id)
            vim.bo[bufnr].modified = true
            st.saving = false
        end,
    })
    return  -- async now, on_save returns here
end
```

#### 3. Extract `continue_save_after_creates(bufnr, st, diff, n_renamed, n_patched)`

This function contains all the logic that currently runs **after** the creates confirm:
- create+delete false pairing (line 2288)
- no-deletes fast path (line 2404)
- hard cap on deletes (line 2426)
- delete confirm prompt (line 2440)

The delete confirm at line 2458 gets the same treatment:

```lua
local function continue_save_after_creates(bufnr, st, diff, n_renamed, n_patched)
    -- ... create+delete pairing logic (lines 2288-2339) ...
    -- ... no-deletes fast path (lines 2404-2422) ...
    -- ... hard cap on deletes (lines 2426-2438) ...

    -- Delete confirmation
    st.saving = "confirming"
    vim.bo[bufnr].modified = false
    local cancel_id = register_textchanged_cancel(bufnr, st)
    require("vault.ui.confirm").select({
        message = prompt,  -- built from diff.deletes preview
        title = "Vault Process",
        choices = {
            { key = "y", label = "Yes, trash them", action = function()
                cleanup_cancel(cancel_id)
                local n_u, n_d, n_c = apply_mutations(diff, st)
                vim.notify(...)
                vim.schedule(function() M.reload(bufnr); st.saving = false end)
            end },
            { key = "n", label = "No, skip deletes", action = function()
                cleanup_cancel(cancel_id)
                apply_safe_and_reload(bufnr, st, diff)
            end },
            { key = "c", label = "Cancel", action = function()
                cleanup_cancel(cancel_id)
                vim.notify("[vault] Save cancelled", vim.log.levels.INFO)
                vim.bo[bufnr].modified = true
                st.saving = false
            end },
        },
        on_cancel = function()
            cleanup_cancel(cancel_id)
            vim.bo[bufnr].modified = true
            st.saving = false
        end,
    })
end
```

#### 4. TextChanged auto-cancel helper

```lua
local function register_textchanged_cancel(bufnr, st)
    return vim.api.nvim_create_autocmd("TextChanged", {
        buffer = bufnr,
        once = true,
        callback = function()
            if st.saving == "confirming" then
                vim.notify("[vault] Buffer changed — save cancelled", vim.log.levels.INFO)
                st.saving = false
                vim.bo[bufnr].modified = true
            end
        end,
    })
end

local function cleanup_cancel(id)
    pcall(vim.api.nvim_del_autocmd, id)
end
```

#### 5. Edge cases to test

| Scenario | Expected |
|----------|----------|
| `:w` with 0 deletes, ≤5 creates | Fast path, no popup, immediate apply |
| `:w` with 6 creates, 0 deletes | Popup: Yes/No/Cancel. "Yes" applies all. "No" skips creates. "Cancel" re-dirties buffer |
| `:w` with 3 deletes | Popup: Yes/No/Cancel. Identical behavior to current |
| `:w` then `:w` while popup open | Second `:w` hits `st.saving` guard → no-op |
| Edit buffer while popup open | `TextChanged` fires → popup auto-cancels, buffer re-dirtied |
| `:q` while popup open | `modified=false` so no save prompt. Popup auto-closes via BufLeave/BufUnload |
| Both popups (creates + deletes) | Creates popup → user picks "Yes" → continue_save_after_creates → deletes popup |
| NUI not available | Fallback to `vim.ui.select` (async, no RPC block) |

#### 6. What stays unchanged

- `diff_buffer()`, `apply_mutations()`, `apply_safe_and_reload()` — untouched
- Undo system (`snapshot_for_undo`, `M.undo`) — untouched
- Rename processing (lines 2330-2402) — stays synchronous before any popup
- Fast paths (no deletes, ≤5 creates) — still synchronous, no popup
- `M.reload()` — untouched
