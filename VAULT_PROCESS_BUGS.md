---
title: VAULT_PROCESS_BUGS
created: 20260228210036
modified: 20260228210036
committed: 20260228210045
---
# Vault Process API - Live Testing Bug Report

## Session: 2026-02-28
**Vault**: ~/knowledge (8688 notes)  
**Filter**: fuzzy "painting" (~1115 notes)  
**Restore Point**: `dff5e6cf4`  

---

## Test Results Summary

| # | Test | Motions | Result | Status |
|---|---|---|---|---|
| 1 | Delete single line | `dd` | Correctly detected 1 delete | ✅ PASS |
| 2 | Delete 5 lines | `5dd` | Correctly detected 5 deletes | ✅ PASS |
| 3 | Move line down | `ddp` | No phantom writes — reorder is safe | ✅ PASS |
| 4 | Yank + paste line | `yyp` | Pasted line treated as new note | ✅ PASS |
| 5 | Yank 5 + paste | `5yyp` | 5 new notes created | ✅ PASS |
| 6 | Replace line | `cc` then type | Full line replacement | ⚠️ VERIFY |
| 7 | Change word on slug | `cw` | Slug edit detected | ⚠️ VERIFY |
| 8 | Delete char on separator | `f│x` | **SEPARATOR DAMAGE** | 🐛 BUG |
| 9 | Open line below | `o` then type | New note created | ✅ PASS |
| 10 | Join lines | `J` | Two rows merge into garbage line | 🐛 BUG |
| 11 | Visual line delete | `V5jd` | 6 lines deleted, line count correct | ✅ PASS |
| 12 | ddp save | `ddp` `:w` | No files changed (no data diff) | ✅ PASS |
| 13 | Cell edit + save | edit `todo→done` `:w` | Frontmatter updated correctly | ✅ PASS |
| 14 | Delete + save | `dd` `:w` | Confirmation shown, note trashed to .trash/ | ✅ PASS |
| 15 | Join lines | `J` | Merges 2 rows into 1 malformed line | 🐛 BUG |
| 16 | Delete to EOL | `$BD` | Clears last cell — acceptable behavior | ✅ PASS |
| 17 | Visual block | `Ctrl-V` | Skipped (byte position complexity) | ⏭️ SKIP |
| 18 | Global substitute | `:%s/X/Y/g` | Renames + updates applied, wikilinks patched | ✅ PASS (dangerous) |

---

## Critical Bugs Found

### BUG #1: Separator Character Deletion (Test 8)
**Severity**: CRITICAL  
**Motion**: `f│x` (delete single character on `│` separator)  
**Issue**: Deleting a byte of the `│` separator breaks column parsing  
**Impact**: Lines become unparseable; column alignment corrupted  
**Expected**: Should prevent separator deletion or warn user  
**Reproduce**:
```vim
:Vault process
normal 0f│x    " Delete separator char from first line
```
**Result**: First line separator partially/fully destroyed  

**Fix Options**:
1. Protect separator chars with 'readonly' flag on those bytes
2. Add autocmd to reject TextChanged that mangles separators
3. Validate line format on every TextChanged event
4. Add virtual text overlay to "lock" separator columns

---

## Medium-Priority Findings (Needs Verification)

### Finding #3: Move Line Detection (Test 3) — RESOLVED ✅
**Motion**: `ddp`  
**Result**: No phantom writes. ddp produces zero file changes because extmarks follow the lines and diff sees identical data. Safe operation.

### BUG #2: Non-deterministic Column Order
**Severity**: Medium  
**Issue**: Column order changes between process buffer reopens (e.g. `slug,title,tags,status` → `slug,title,status,tags`)  
**Impact**: Confusing UX — user expects consistent layout  
**Fix**: Sort non-slug columns alphabetically or preserve order from base definition  

### BUG #3: vim.fn.confirm() Blocks RPC
**Severity**: Medium  
**Issue**: Delete/create confirmations use `vim.fn.confirm()` which blocks the RPC socket, making automated testing impossible and causing "connection refused" errors  
**Fix**: Consider `vim.ui.select()` or async input methods  

### Finding #6: Line Replacement Behavior (Test 6)
**Motion**: `cc` then type new content  
**Question**: Is this detected as delete+create or update?  
**Impact**: User intent unclear - are they editing cells or replacing entire note?  
**Action**: Need to verify diff output and user experience  

### Finding #7: Slug Column Edits (Test 7)
**Motion**: `0cw[NEWSLUGG]`  
**Question**: Does slug edit correctly trigger RENAME instead of UPDATE?  
**Impact**: If recognized as UPDATE, file move won't happen  
**Action**: Verify rename detection is working correctly  

### Finding #10: Join Lines Behavior (Test 10) — CONFIRMED BUG 🐛
**Motion**: `J` (join line at cursor with next line)  
**Issue**: Two note rows merge into one malformed line with double separators  
**Impact**: Second note detected as "deleted", first note gets garbage appended  
**Fix**: Block `J` in process buffers or add TextChanged validation to detect merged lines  

---

## Tests Not Yet Executed

- [ ] Test 11: Visual block operations (`<C-v>`)
- [ ] Test 12: Substitute with `:s`
- [ ] Test 13: Global substitute `:%s/old/new/g`
- [ ] Test 14: Global delete `:g/pattern/d`
- [ ] Test 15: Undo/redo chains (edit → save → undo)
- [ ] Test 16: Macro recording with line movements
- [ ] Test 17: Delete to end of line (`D`)
- [ ] Test 18: Change to end of line (`C`)
- [ ] Test 19: Replace mode (`R`)
- [ ] Test 20: Clear entire buffer (`ggdG`)

---

## Recommendations

### Immediate (Fix before release)
1. **BUG #1**: Add separator protection or validation
2. **Finding #3, #7, #10**: Verify these patterns don't create corruption

### Short-term (Next iteration)
1. Add comprehensive motion validation on TextChanged
2. Highlight non-editable regions (separators, slug column for non-rename operations)
3. Show preview of what will be created/deleted before save for destructive operations

### Documentation
- Add "Safe Motions" guide to help
- Document which vim patterns are risky or unsupported
- Add warnings for line merges, bulk deletions, etc.

---

## Architecture Decision: Conceal-based Separators (ADR-001)

**Date**: 2026-02-28  
**Status**: Accepted  
**Context**: The process buffer uses real `│` (U+2502, 3-byte UTF-8) characters as column separators. This creates multiple classes of bugs:

1. `│` can appear in real note content (slugs, titles, frontmatter values, markdown tables in body)
2. Users can delete `│` with `f│x`, breaking column parsing
3. `J` (join lines) merges two rows producing double separators
4. `split_cells` can't distinguish data `│` from structural `│`

**Decision**: Replace `│` with `\x1f` (ASCII Unit Separator) as the real delimiter byte, concealed to display as `│`.

### Why `\x1f`
- ASCII 31 (Unit Separator) — literally designed for separating fields in records
- 1 byte (fast parsing, no multi-byte edge cases)
- Never appears in filenames, slugs, titles, frontmatter, or body text
- Cannot be typed accidentally
- `vim.split(line, "\x1f")` is faster than splitting on 3-byte UTF-8

### Buffer layout
```
Real bytes:   cell1 \x1f cell2 \x1f cell3 \x1f cell4
User sees:    cell1 │ cell2 │ cell3 │ cell4
```
- Spaces around `\x1f` are real characters (provide visual padding)
- `\x1f` is concealed via `nvim_buf_set_extmark` with `conceal = "│"`
- Variable-width cells (no fixed padding to column width)

### Footgun mitigations

| Footgun | Solution |
|---------|----------|
| **Yank/paste leaks `\x1f`** | `TextYankPost` autocmd replaces `\x1f` → ` │ ` in register |
| **`/` search across cells** | Non-issue — `\x1f` only between columns, never within content |
| **`w`/`b` word motions** | Desirable — `\x1f` is non-keyword, cells become word boundaries |
| **Replace mode `R` overwrites `\x1f`** | Cursor skip (`CursorMoved` autocmd) + `TextChanged` validation |
| **`conceallevel=0`** | Force `wo.conceallevel=2`, `wo.concealcursor="nv"` on window |
| **External tools see `\x1f`** | Non-issue — `buftype=acwrite`, never on disk |

### Performance estimate
- ~26,000 conceal extmarks (3 per line × 8688 lines) — Neovim handles 100k+ extmarks
- Conceal rendering is O(visible_lines), not O(total_lines)
- `\x1f` split is faster than `│` split (1 byte vs 3 bytes)
- Overall: negligible impact, likely net positive

### Research basis
Studied oil.nvim, vim-table-mode, nvim-dbee, csv.vim, orgmode.nvim, obsidian.nvim. All use real characters (not virtual text overlays). oil.nvim uses space-padding with no separator char. vim-table-mode uses real `|` with no protection. No plugin uses `virt_text_pos="overlay"` for structural separators. Conceal is used by csv.vim and obsidian.nvim for visual replacement of real bytes.

---

## Session 2 Notes (2026-02-28, continued)

### Additional tests verified with sign_text fix
| # | Test | Result |
|---|------|--------|
| 11 | V5jd (visual delete) | PASS |
| 12 | ddp + save (swap) | PASS — no phantom writes |
| 13 | Cell edit todo→done + save | PASS — frontmatter updated |
| 14 | dd + save (delete) | PASS — confirmation, trashed to .trash/ |
| 15 | J (join lines) | BUG — merges rows into garbage |
| 16 | D (delete to EOL) | PASS — clears last cell |
| 18 | :%s/Painting/ART/g | PASS — renames + wikilink patches (dangerous) |
| 19 | :g/paint/d | PASS — 747 lines deleted (after sign_text fix) |
| 20 | ggdG (clear buffer) | PASS — safety cap refused 8688 deletes |
| 23 | 5yyp + save | PASS — 5 notes created with dedup |
| 24 | Slug rename (cw) + save | PASS — file renamed, wikilinks patched |
| Re-2 | 5dd + save (re-verify) | PASS — 5 notes trashed correctly |

### Bugs fixed this session
- **sign_text overflow**: Capped to 2 display cells (`##` for >99)
- **Create slug from title**: Now derives filename from slug column first, title as fallback
- **Timer double-close**: Fixed `~/.config/nvim/lua/config/autocmds.lua:77` handle guard

### Bugs identified
- **Non-deterministic column order**: Columns reorder between buffer reopens
- **J (join lines)**: No protection — merges rows into garbage
- **vim.fn.confirm() blocks RPC**: Interactive prompts block socket for automated testing

