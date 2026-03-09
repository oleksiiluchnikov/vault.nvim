## PRD: Duplicate Review for vault.nvim

*2026-03-09*

### Product statement

Duplicate Review is a Neovim-native workflow for safely resolving duplicate notes in an Obsidian vault after sync or migration failures. It helps the user compare two candidate notes, choose which one survives, merge meaningful metadata, preserve useful body content, rewrite vault links, and move the loser to `.trash/` without leaving the editor.

This feature exists to turn a many-hour cleanup task into a focused review session made of fast, low-friction decisions.

---

### Problem

After an Obsidian Sync failure, the user's vault accumulated roughly 1,100 duplicate notes inside a vault of roughly 18,000 notes. Many duplicates were safe to auto-resolve, but hundreds still require judgment because they differ in frontmatter, body content, or both.

The old workflow was painful:

- open both notes manually
- compare filenames, frontmatter, and body
- decide which note should survive
- merge or preserve any useful content by hand
- update wikilinks across the vault
- move the loser note out of the active vault

At 2-5 minutes per pair, that turns into dozens of hours of high-friction cleanup. The user needs a flow that keeps context on screen, makes repeated decisions cheap, and remains safe when the right answer is not obvious.

---

### Users and jobs

Primary user: a keyboard-first Obsidian + Neovim user cleaning up a large personal vault after sync damage.

Core jobs:

- quickly decide which of two notes should survive
- understand the consequence of that decision before applying it
- preserve semantic metadata and useful note content
- avoid breaking wikilinks across the vault
- pause and resume a review session without losing progress

---

### Product principles

- **Safety first**: Never permanently delete a note as part of review. Losers move to `.trash/`.
- **Links are sacred**: A resolution is incomplete if wikilinks are not rewritten correctly.
- **Do not assume the unsuffixed file is better**: Copy-suffixed notes are candidates, not automatic losers.
- **Optimize for repeated decisions**: The common case should be a glance plus one keystroke.
- **Escalate ambiguity, do not hide it**: If frontmatter cannot be resolved safely, the user must be asked.
- **Interruptions are normal**: The workflow must support quitting and resuming without manual bookkeeping.

---

### Goals

- Reduce common-case duplicate resolution to under 10 seconds per pair.
- Keep the entire review flow inside Neovim.
- Make the result of each decision legible before apply.
- Preserve important metadata and useful body content during merge.
- Rewrite references to the surviving note across the vault.
- Support both immediate decisions and fast batch triage.

### Non-goals for v1

- Fully automatic resolution of all duplicates.
- A generic merge editor for arbitrary note conflicts.
- A perfect detector for every false-positive filename collision.
- A new undo system beyond existing recovery paths such as git and `.trash/`.
- Group-based resolution for 3+ duplicates in one interaction.

---

### User stories

- As a vault owner, I can open a duplicate-review session and immediately see the next pair that needs judgment.
- As a reviewer, I can compare both notes and choose a survivor without manually opening files or running separate link-rewrite steps.
- As a cautious user, I can preview the merged result before applying it.
- As a user reviewing many obvious pairs, I can queue several decisions and apply them in a batch.
- As a user facing conflicting metadata, I am prompted to resolve that conflict instead of having the tool silently guess.
- As a user who gets interrupted, I can quit and later resume from where I left off.

---

### v1 scope

#### Entry

The user starts review from a vault command and receives a live list of duplicate candidates discovered from filename-stem collisions, including common copy-suffix patterns such as `Note 1.md`.

The system prioritizes easier pairs first so the user can clear obvious wins before dealing with harder cases.

#### Review workspace

The review UI presents:

- note A preview
- a central decision panel
- note B preview

The user must be able to:

- see both notes side by side
- identify changed regions quickly
- understand the recommended choice and why it was recommended
- see the expected merge consequences for each choice

#### Decision actions

The workflow must support:

- keep A
- keep B
- apply recommended choice
- preview merged result before apply
- skip this pair for later
- queue the decision for batch apply
- quit and resume later

Default keymaps are part of the interaction design because this is a Neovim-native feature, but the product requirement is the action model above, not a specific implementation.

#### Merge behavior

When the user resolves a pair, the system must:

- preserve the surviving note
- merge non-conflicting metadata from the loser
- preserve the fuller or combined body content according to the pair type
- prompt for unresolved frontmatter conflicts instead of silently guessing
- rewrite links from loser to survivor across the vault
- move the loser to `.trash/`

#### Batch behavior

The workflow must support rapid triage of multiple pairs followed by one batch apply action.

#### Resume behavior

The workflow must restore review context after quitting, including:

- the current pair
- queued but unapplied decisions
- the vault scope for the session

---

### Safety and recovery requirements

- The feature must never permanently delete a note.
- The user must be able to inspect the merged result before apply.
- If unresolved frontmatter conflicts remain, the user must resolve them before the merge completes.
- The loser note must remain recoverable via `.trash/` and normal repository history.
- Batch apply must use the same safety guarantees as single-item apply.

---

### Success metrics

- Common-case decision time: under 10 seconds per pair for obvious duplicates.
- Session continuity: user can quit and resume without external notes or manual tracking.
- Safety: no permanent deletion path exists in-product.
- Link integrity: acceptance testing shows loser-note wikilinks are rewritten to the survivor without breaking aliases or heading links.
- Throughput: batch review materially reduces friction versus resolving each pair with a separate full-vault rewrite cycle.

---

### Known risks and limitations

- Filename-based duplicate detection can produce false positives, especially when titles legitimately end in numbers.
- Multi-way duplicate groups are not a first-class interaction in v1.
- Some note bodies will still require human judgment even with recommendations and preview.
- The feature assumes a single-user review session; concurrent external edits during review are out of scope.

---

### Open questions

- Should skipped items support explicit reasons such as `not duplicates` or `review later`?
- Should repeated field-level decisions become reusable rules or presets?
- Should complex cases allow editing the merged result before apply?
- Should 3+ duplicates be reviewed as a group instead of as pairs?

---

### Acceptance criteria

- The user can start duplicate review and immediately see the next candidate pair.
- The user can compare both candidate notes in one screen without opening files manually.
- The system presents a recommendation and the reason for that recommendation.
- The user can keep either note, skip the pair, preview the result, or queue the decision for batch apply.
- If unresolved metadata conflicts exist, the workflow prompts the user to resolve them before applying the merge.
- Applying a decision rewrites links from loser to survivor and moves the loser to `.trash/`.
- The user can quit review and later resume the same session context.
- The workflow supports user-configured heuristics for preferred folders, ignored metadata, and field normalization.
- The feature is usable on a large vault without requiring a full manual rescan after every individual decision.

---

### Companion technical design

Implementation details, module boundaries, heuristics, keymaps, performance notes, and current limitations live in `docs/duplicate-review-technical-design.md`.
