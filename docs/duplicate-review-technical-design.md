## Duplicate Review Technical Design

*2026-03-09*

This document captures the current technical design and implementation details for Duplicate Review. It is the companion to `docs/PRD-duplicate-review.md`.

---

### Code locations

- `lua/vault/duplicates/init.lua` - duplicate scan, review UI, queueing, resume state, diff navigation
- `lua/vault/merge.lua` - merge planning, conflict detection, absorb APIs, batch apply
- `lua/vault/config.lua` - defaults for `duplicates.*` and `merge.*`
- `lua/vault/watcher/init.lua` - vault-wide wikilink rewrite for rename and batch rename
- `lua/vault/core/state/init.lua` - persisted review session state
- `lua/vault/commands/init.lua` - `:Vault duplicates review`
- `README.md` - user-facing config documentation

---

### Duplicate detection

#### Grouping

The scanner walks markdown files under the selected root and groups them by normalized stem.

- Grouping is case-insensitive.
- Copy suffixes are normalized with `COPY_SUFFIX_RE = "^(.-) (%d+)$"`.
- This intentionally catches patterns like `Note.md` and `Note 1.md`.

#### Known limitation

This regex also creates false-positive candidate groups for legitimate numeric titles such as `Fusion 360` or `Python 3`. Today these are tolerated as review-time false positives rather than filtered out during scan.

---

### Pair ordering and classification

#### A/B assignment

- If exactly one path has a copy suffix, the unsuffixed path becomes A.
- Otherwise, lexicographic path order decides A and B.
- A/B is a display and decision label only, not a quality judgment.

#### Classification kinds

- `exact` - normalized frontmatter and normalized body are equal
- `metadata` - body is equal, frontmatter differs
- `a_subset` - A body is a subset of B body
- `b_subset` - B body is a subset of A body
- `divergent` - both bodies contain unique content

Pairs are sorted in this order:

1. `exact`
2. `metadata`
3. `a_subset`
4. `b_subset`
5. `divergent`

---

### Recommendation heuristic

Current recommendation order:

1. preferred directory weight
2. richer frontmatter count
3. greater number of meaningful body lines
4. stable lexicographic path tiebreak

Configuration source:

- `config.options.duplicates.preferred_dirs`
- `config.options.duplicates.ignored_frontmatter_keys`
- `config.options.duplicates.frontmatter_normalizers`

---

### Review UI

#### Layout

The UI uses three floating windows:

- left preview: note A
- center decision panel
- right preview: note B

The previews are read-only markdown buffers. The center is a read-only summary buffer.

#### Diff rendering

- changed lines in A use `DiffDelete`
- changed lines in B use `DiffAdd`
- intraline changes use `DiffText`
- hunk navigation synchronizes both preview panes

#### Center panel content

The center panel shows:

- pair kind
- recommendation and reason
- per-choice rewrite / metadata / conflict summary
- merge plan summary
- available choices
- batch queue count

---

### Keymaps

#### Review buffer

- `a` - keep A immediately
- `b` - keep B immediately
- `A` - queue keep A
- `B` - queue keep B
- `<CR>` - apply recommended choice
- `X` - flush queued batch
- `pa` - preview keep-A result
- `pb` - preview keep-B result
- `p` - preview recommended result
- `]c` - next changed region
- `[c` - previous changed region
- `s` - skip current pair
- `]d` - advance to next pair
- `q` - quit and persist session state

#### Preview buffer

- `<CR>` - apply the previewed choice
- `q` / `<Esc>` - close preview and return to review

---

### Merge planning and application

#### Planning API

`merge.plan(path_a, path_b, opts)` returns a plan containing:

- winner and loser paths/slugs
- parsed fields and body lines for both notes
- merged frontmatter
- final merged note lines
- added fields
- extended list fields
- unresolved conflicts
- ignored noisy fields
- body strategy used

#### Conflict handling

- single-item apply calls `merge.merge(...)`
- if `plan.conflicts` is empty, merge proceeds directly
- if conflicts remain, `merge.open_conflict_picker(...)` is shown
- the picker must be resolved before `merge.absorb(...)` runs

This is important: the system does not blindly prefer the winner for every conflicting field.

#### Body strategies

- `exact` / `metadata` -> keep winner body only
- `a_subset` / `b_subset` -> keep the fuller body
- `divergent` -> keep both bodies by appending loser content to winner

Current center-panel wording simplifies this to either "keep winner body only" or "keep both bodies (loser appended)".

#### Apply behavior

After merge content is finalized:

- winner file is written
- loser links are rewritten to winner links across the vault
- loser file is moved to `.trash/`
- related duplicate items are removed from the active review list

---

### Batch apply

Queued items store:

- `target_path`
- `source_path`
- `merged_lines`

Batch flush uses `merge.absorb_many(...)`.

Important properties:

- one vault-wide rewrite pass
- shared path metadata across the session
- avoids per-item full-vault rescans

This change removed an observed hot path of roughly 0.6s per merge caused by repeated rescans.

---

### Session state

Persisted under `vault.duplicates.review`.

Stored values include:

- `root`
- `current_key` for the current pair
- `pending` queued decisions

Resume behavior:

- scan fresh on next start
- restore queue if root matches
- restore current position by stable pair key, not numeric index
- filter out items already covered by queued paths

---

### Configuration

Current defaults in `lua/vault/config.lua`:

```lua
merge = {
  ignored_conflict_fields = { "modified", "committed" },
  field_normalizers = {},
}

duplicates = {
  preferred_dirs = { "Inbox", "Daily", "References" },
  ignored_frontmatter_keys = { "modified", "committed" },
  frontmatter_normalizers = {},
}
```

Personal config used during development also includes:

- legacy assignee alias normalization
- `dates.nvim`-backed date normalization

---

### Safety notes

- loser notes are trashed, not permanently deleted
- preview exists for result inspection before apply
- unresolved field conflicts block direct merge and open a picker
- no dedicated undo UI exists yet

Recovery today depends on:

- `.trash/`
- git history

---

### Known implementation limitations

- false positives from legitimate numeric titles
- pairwise treatment of 3+ duplicate groups
- preview is read-only, not editable
- no skip reasons or persistent labeling for non-duplicates
- no explicit metrics UI
- no dedicated undo action in review flow

---

### Validation references

- `tests/vault/duplicates_spec.lua`
- `tests/vault/merge_plan_spec.lua`
- `tests/vault/merge_batch_spec.lua`

Research context that shaped the design lives in `~/knowledge/Clippings/Research - General Duplicate Review Merge UX.md`.
