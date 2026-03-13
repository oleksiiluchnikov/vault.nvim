# Vault.nvim

Plugin to manage [Obsidian](https://obsidian.md)-compatible vaults in Neovim.

> **Note:** This plugin is under active development. Breaking changes may occur.

## Features

- **Capture** -- fleeting notes, daily journal, extract-to-note, voice dictation
- **Process buffer** -- spreadsheet-style batch editing of note metadata (tags, status, properties) with `:w` to apply
- **Telescope integration** -- pickers for notes, tags, properties, wikilinks, directories, dates, tasks, bases
- **Wikilink management** -- resolve unresolved links, batch create, merge notes, rewrite links on rename
- **Bases** -- Obsidian Bases-compatible `.base` files with filters, formulas, and views
- **Autocompletion** -- nvim-cmp source for tags (`#`), dates (`20`), and weekdays
- **File watcher** -- auto-patches wikilinks when files are renamed externally
- **Merge** -- absorb one note into another with frontmatter conflict resolution and wikilink rewrite

## Installation

See [docs/installation.md](docs/installation.md).

## Testing

- Unit and integration tests live under `tests/vault/`.
- End-to-end tests live under `tests/e2e/`.
- Run the E2E suite with `bash ./scripts/run_e2e.sh`.
- E2E always runs in a separate Neovim process against a disposable cloned vault, never the live `~/knowledge` root.
- See `docs/e2e-testing.md` for safety rules and artifact debugging.

## Configuration

Duplicate review and merge heuristics are user-configurable rather than hardcoded.

```lua
require("vault").setup({
  duplicates = {
    preferred_dirs = { "Inbox", "Daily", "References" },
    ignored_frontmatter_keys = { "modified", "committed" },
    stem_suffix_patterns = {
      [[\s\+\d\+$]],
      [[_\d\+$]],
    },
    review_excluded_dirs = { "Ai" },
    review_excluded_files = { "README.md" },
    review_excluded_patterns = { [[^Ai/]], [[README\.md$]] },
    related_excluded_dirs = { "Daily", "Ai" },
    related_excluded_files = { "README.md" },
    related_excluded_patterns = { [[^Daily/]], [[^Ai/]], [[README\.md$]] },
    presets = {
      easy = {
        description = "Metadata and subset duplicates first",
        kind = { "metadata", "subset" },
      },
      inbox = {
        description = "Pairs touching Inbox",
        dirs = { "Inbox" },
      },
    },
    frontmatter_normalizers = {
      title = function(value)
        return value
      end,
    },
  },
  merge = {
    ignored_conflict_fields = { "modified", "committed" },
    field_normalizers = {
      assignee = function(value)
        return tostring(value)
      end,
    },
    conflict_biases = {
      created = "earliest",
    },
    conflict_bias_behavior = "auto_apply",
    learned_conflict_biases = {
      enabled = true,
      path = nil,
      behavior = "auto_apply",
    },
  },
})
```

- `duplicates.preferred_dirs` controls which folders are favored when recommending keep `A` vs `B`
- `duplicates.ignored_frontmatter_keys` removes noisy frontmatter keys from duplicate similarity checks
- `duplicates.stem_suffix_patterns` strips configurable suffix regexes before same-stem duplicate grouping, so names like `note 1` and `note_1772142561` can land in normal review
- `duplicates.review_excluded_dirs` removes whole directories such as `Ai` from same-stem `:Vault duplicates review ...` suggestions
- `duplicates.review_excluded_files` removes noisy basenames such as `README.md` from same-stem `:Vault duplicates review ...` suggestions
- `duplicates.review_excluded_patterns` applies regex-style exclusions against relpaths and basenames for same-stem review
- `duplicates.related_excluded_dirs` removes whole directories such as `Daily` or `Ai` from Rust-backed `:Vault duplicates related ...` suggestions
- `duplicates.related_excluded_files` removes noisy basenames such as `README.md` from Rust-backed `:Vault duplicates related ...` suggestions
- `duplicates.related_excluded_patterns` applies regex-style exclusions against relpaths and basenames for related suggestions
- `duplicates.presets` defines named review sessions for `:Vault duplicates review preset`; each preset can set `root`, `dirs`, `tags`, `kind`, and `description`
- `duplicates.frontmatter_normalizers[key]` can normalize a frontmatter value before duplicate comparison
- `merge.ignored_conflict_fields` suppresses conflict prompts for fields you consider noise
- `merge.field_normalizers[key]` can normalize metadata values before conflict detection
- `merge.conflict_biases[key]` preselects a side in the conflict picker; supports `"a"`, `"b"`, `"earliest"`, `"latest"`, or a custom function returning `"a"`/`"b"`
- `merge.conflict_bias_behavior` controls how explicit config biases behave: `"preselect"` keeps them in the picker with the preferred choice selected, `"auto_apply"` resolves them without prompting
- `merge.learned_conflict_biases` stores remembered picker choices in an editable Lua file under `stdpath("data")` by default
- `merge.learned_conflict_biases.behavior` controls whether learned rules only preselect or auto-apply
- In the conflict picker, `<CR>` applies the current choices only; `r` applies and remembers them for future conflicts
- If every conflicting field is covered by explicit or learned biases, the merge skips the conflict picker entirely

## Commands

All commands live under a single `:Vault` entry point. Running `:Vault` with no arguments opens a meta-picker (picker of pickers).

### Capture

| Command | Description |
|---------|-------------|
| `:Vault fleeting [text]` | Open fleeting note popup. First line becomes title. Saves to inbox on `<Esc>`. |
| `:Vault note new [slug]` | Create a named note (or open it if it exists). No slug = fleeting popup. |
| `:Vault note merge [source-slug] [target-slug]` | Merge one note into another. With no args, uses the current note and opens the combined target picker. With one arg, uses the current note if present, otherwise treats the arg as source and opens the target picker. The target can be a note, resolved wikilink, or unresolved wikilink. |
| `:'<,'>Vault note extract [slug]` | Extract visual selection into a new note, replace with `[[wikilink]]`. |
| `:Vault today` | Open/create today's daily journal note. |
| `:Vault today append <text>` | Append `- <text>` to today's journal without opening it. |
| `:Vault today dictate` | Voice capture via external `ask` tool, appends with timestamp. See note below. |
| `:Vault yesterday` | Open yesterday's journal note. |

> **`:Vault today dictate`** requires an external `ask` binary in PATH that accepts `--dictate --json --context - --placeholder "..."` and returns `{"ok": true, "value": "transcribed text"}` on stdout. This command is only registered when `ask` is detected. The default implementation uses a private tool; to use your own dictation solution, create a wrapper script named `ask` that conforms to this interface, or override `callbacks.today_dictate` in your config.

### Browse & Search

| Command | Description |
|---------|-------------|
| `:Vault` | Meta-picker: choose from all available pickers. |
| `:Vault note` | Telescope notes picker (all notes). |
| `:Vault notes` | Same as above. |
| `:Vault notes linked` | Notes with at least one inlink. |
| `:Vault notes orphans` | Notes with zero inlinks and zero outlinks. |
| `:Vault notes leaves` | Notes with inlinks but no outlinks. |
| `:Vault notes internals` | Notes with both inlinks and outlinks. |
| `:Vault notes dangling` | Notes containing unresolved outlinks. |
| `:Vault notes resolved` | Notes where all outlinks resolve to existing notes. |
| `:Vault notes status <tag>` | Notes with a matching tag name. **Note:** this filters by tag name, not frontmatter `status` field. Legacy behavior; may change in the future. |
| `:Vault notes dir [dir]` | Notes in a directory. No arg = root-level notes only. |
| `:Vault notes empty` | Notes with blank or whitespace-only body. |
| `:Vault notes no-frontmatter` | Notes not starting with `---`. |
| `:Vault notes empty-property [prop] [val]` | Notes where a frontmatter property has an empty value. |
| `:Vault tags` | Telescope tags picker (tag name + note count). |
| `:Vault tags <name>` | Notes with a specific tag. |
| `:Vault properties` | Telescope properties picker (all frontmatter keys). |
| `:Vault properties <name>` | Drill into values for that property. |
| `:Vault properties <name> <val>` | Notes with that specific property value. |
| `:Vault dirs [dir]` | Telescope directory picker. Enter drills into notes. |
| `:Vault wikilinks` | Telescope wikilinks picker (all). |
| `:Vault wikilinks unresolved` | Wikilinks with no matching note. |
| `:Vault wikilinks resolved` | Wikilinks pointing to existing notes. |
| `:Vault tasks` | Task note picker from `Tasks/` (frontmatter-based task system). |
| `:Vault tasks new <name>` | Create `Tasks/T-YYYYMMDDHHmmss <name>.md` and open it. |
| `:Vault tasks status [status]` | Show current status and valid transitions, or apply a transition. |
| `:Vault tasks pick-next` | Open the highest-priority unblocked active task. |
| `:Vault tasks promote [text]` | Promote current line (or arg text) into a task note and replace line with a wikilink. |
| `:Vault tasks kanban` | Open `Tasks Kanban` base in board view. |
| `:Vault tasks backlog` | Open `Tasks Backlog` base in process/grid view. |
| `:Vault tasks recur preview` | Show next due date for current recurring task. |
| `:Vault tasks recur now` | Spawn next recurring task instance for current task immediately. |
| `:Vault tasks recur sweep` | Scan completed recurring tasks and spawn missing next instances. |
| `:Vault tasks doctor [--fix]` | Diagnose task frontmatter status issues; optionally auto-fix canonical forms. |
| `:Vault actions` | Legacy inline-checkbox task picker (`- [ ]` lines). |

Task Kanban column order, card sorting, and empty-column behavior are task-specific and configured via `task_notes`:

```lua
require("vault").setup({
  task_notes = {
    status_order = {
      "Status - Backlog",
      "Status - Todo",
      "Status - In-Progress",
      "Status - In-Review",
      "Status - Done",
      "Status - Failed",
      "Status - Deprecated",
      "Status - Archived",
    },
    -- Sort cards within each column (applied in order).
    -- Prefix with "-" for descending. Default: {} (sort by slug).
    kanban_sort = { "priority", "-created" },
    -- Empty-column behavior:
    --   "always"    — show all status columns even when empty (default)
    --   "non-empty" — show only columns with at least one card
    --   "hide"      — same as non-empty
    kanban_empty_columns = "always",
  },
})
```

These controls only affect `:Vault tasks kanban`; other kanban boards are not changed.
| `:Vault dates` | Telescope picker for dates found in notes. |
| `:Vault lines` | Telescope picker for dash-prefixed lines from journal notes. |
| `:Vault bases` | Telescope picker for `.base` files. |
| `:Vault bases <name>` | Telescope notes matched by that base's filters. |
| `:Vault inbox` | Telescope notes picker filtered to inbox directory. |
| `:Vault grep [query]` | Live ripgrep across vault. Supports visual selection as initial query. |

### Current Note Operations

| Command | Description |
|---------|-------------|
| `:Vault note inlinks` | Telescope picker of notes that link TO current note. |
| `:Vault note outlinks` | Telescope picker of notes current note links TO. |
| `:Vault note tags [tag]` | Notes sharing same tags as current note. |
| `:Vault note properties` | Current note's frontmatter properties. |
| `:Vault note cluster` | Notes reachable via wikilink graph BFS from current note. |
| `:Vault note rename [slug]` | Rename note. No arg = interactive prompt. Patches all wikilinks. |
| `:Vault note delete [slug] [--permanent]` | Delete note (trash by default, `--permanent` for hard delete). |
| `:Vault note preview` | Markdown preview via Glow. |
| `:Vault note obsidian` | Open current note in Obsidian. |
| `:Vault note random [filter]` | Open a random note. Optional arg is a fuzzy filter on slug. |
| `:Vault move [slug]` | Move note to a different directory via Telescope picker. |
| `:Vault toggle-link` | Toggle between bare URL and `[title](url)` markdown link under cursor. |

#### Merge, retarget, and promote flows

- `:Vault note merge` uses the current note as source and opens the combined target picker
- `:Vault note merge <source> <target>` merges directly without opening the target picker
- picker targets can resolve to existing notes, resolved wikilinks, or unresolved wikilinks
- when a bare unresolved slug uniquely matches an existing note by basename, vault.nvim canonicalizes it to that existing note before merge/promotion runs
- in the notes picker, single-note `<C-r>` is a smart retarget flow: picking an existing target merges into it, while choosing the create row renames the source note to the current query
- in the combined resolve UI, pressing `<CR>` with an empty filtered result list creates a target from the typed query
- in the combined resolve UI, pressing `<C-n>` forces create from the current query even if matching results still exist
- in the tags picker, `<C-p>` and `:Vault tags promote <tag>` use the same combined target picker

### Tags & Properties

| Command | Description |
|---------|-------------|
| `:Vault tags rename <old> <new>` | Rename tag across all notes. |
| `:Vault tags merge <target> <s1> [s2 ...]` | Merge multiple tags into target. |
| `:Vault tags doc <tag>` | Open/create tag documentation note. |
| `:Vault tags promote <tag> [note-slug] [--frontmatter]` | Promote a hashtag into a canonical note link. With no slug, opens a combined target picker with all notes plus resolved and unresolved wikilinks. Rewrites inline `#tag` uses to `[[note]]` and keeps frontmatter `tags:` unchanged by default; pass `--frontmatter` to rewrite those too. |
| `:Vault properties rename <old> <new>` | Rename frontmatter property across all notes. |

To migrate a property value across the vault, use the property values picker:

- `:Vault properties`
- select a property like `status`
- press `<CR>` to open its values
- select `todo`
- press `<C-r>` to batch rename that value across all matching notes

For YAML/frontmatter wikilinks, prefer quoted values such as `'[[Status - Todo]]'`.
The batch rename popup for property values uses a plain text buffer, so typing `[[...]]` is literal.

### Utilities

| Command | Description |
|---------|-------------|
| `:Vault duplicates review [vault\|root <dir>\|dir <dir>\|tags <tag...>\|kind <set...>]` | Review duplicate-note candidates across the whole vault by default, or intentionally narrow by directory, tag set, or duplicate kind (`exact`, `metadata`, `subset`, `body`, `divergent`, etc.). |
| `:Vault duplicates review preset [name]` | Open a Telescope picker of duplicate-review presets, or run a named preset directly. |
| `:Vault duplicates related [likely\|maybe\|weak] [vault\|root <dir>\|dir <dir>\|tags <tag...>\|kind <set...>]` | Review Rust-ranked near-duplicate candidates where titles are strongly related even when filenames are not exact suffix copies. |
| `:Vault trash` | Browse trashed notes. Restore or permanently delete. |
| `:Vault merge biases` | Open the learned merge-bias file for editing. |
| `:Vault watcher start\|stop\|status` | Control the file watcher. |
| `:Vault api <function> [args...]` | Raw dispatch to any `vault.api` function. |

## Telescope Picker Keymaps

Each Telescope picker has buffer-local keymaps for actions. These work in both insert and normal mode.

### Notes Picker

| Key | Action |
|-----|--------|
| `<CR>` | Edit selected note |
| `<C-j>` | Merge selected note into another target chosen from notes and wikilinks |
| `<C-r>` | Smart retarget for one note (resolve UI: merge to existing target or create from query); batch rename for multi-select |
| `<C-s>` | Re-sort results |
| `<C-a>` | Select all entries |
| `<C-d>` | Deselect all entries |
| `<C-c>` | Close picker |

> **Note:** Delete is available via `:Vault note delete` but is not mapped in the notes Telescope picker.
>
> Notes picker rows now show compact link counts on the right:
> `out` = outgoing wikilinks, `in` = backlinks, `dang` = unresolved outgoing wikilinks.

### Tags Picker

| Key | Action |
|-----|--------|
| `<CR>` | Drill into notes with this tag |
| `<C-r>` | Batch rename selected tags |
| `<C-m>` | Merge selected tags into one |
| `<C-e>` | Edit tag documentation note |
| `<C-p>` | Promote selected tag into a canonical target chosen from notes and wikilinks |
| `<C-s>` | Re-sort results |
| `<C-a>` / `<C-d>` | Select all / deselect all |

### Properties Picker

| Key | Action |
|-----|--------|
| `<CR>` | Drill into values for this property |
| `<C-r>` | Batch rename selected properties |
| `<C-s>` | Re-sort results |
| `<C-a>` / `<C-d>` | Select all / deselect all |

### Property Values Picker

| Key | Action |
|-----|--------|
| `<CR>` | Show notes with this property value |
| `<C-r>` | Rename selected property values |
| `<C-s>` | Re-sort results |
| `<C-a>` / `<C-d>` | Select all / deselect all |

### Directories Picker

| Key | Action |
|-----|--------|
| `<CR>` | Show notes in this directory |
| `<C-r>` | Rename directory |
| `<C-s>` | Re-sort results |
| `<C-a>` / `<C-d>` | Select all / deselect all |

### Bases Picker

| Key | Action |
|-----|--------|
| `<CR>` | Open process buffer for this base |
| `<C-n>` | Open Telescope notes picker for matched notes |
| `<C-e>` | Edit the `.base` file |
| `<C-s>` | Re-sort results |
| `<C-a>` / `<C-d>` | Select all / deselect all |

### Wikilinks Picker

| Key | Action |
|-----|--------|
| `<CR>` | Open target note (resolved) or resolve/create (unresolved) |
| `<C-l>` | Resolve: open resolve picker for selected wikilink |
| `<C-b>` | Batch resolve: step through selected wikilinks one by one |
| `<C-a>` | Batch create: create notes for all selected unresolved wikilinks |
| `<C-j>` | Compare/merge: open side-by-side resolver UI |

## Process Buffer

The process buffer is a spreadsheet-style view of vault note metadata. Open it with `:Vault process`, edit cells inline, and `:w` to apply all changes at once.

### Opening

```vim
:Vault process                          " all notes
:Vault process orphans                  " orphan notes only
:Vault process leaves                   " leaf notes only
:Vault process empty                    " empty notes only
:Vault process no-frontmatter           " notes without frontmatter
:Vault process dir <dir>                " notes in a directory
:Vault process tag <tag>                " notes with a specific tag
:Vault process base <name>              " notes matched by a .base file
:Vault process <fuzzy-query>            " fuzzy slug filter
:Vault process title,status,tags        " custom column spec
:Vault process title,status,tags orphans " custom columns + filter
:Vault process undo                     " undo the last process buffer save (must be in the process buffer)
```

> **Caveat:** `:Vault process empty-property` appears in tab-completion but opens a **Telescope picker**, not a process buffer. Use `:Vault notes empty-property` instead for the same behavior.

### Column Types

- **Editable:** `slug`, `title`, `status`, `tags`, any frontmatter property
- **Read-only (computed):** `file.path`, `file.ext`, `file.ctime`, `file.mtime`, `file.size`, `file.inlinks`, `file.outlinks`, `file.headings`
- **Aliases:** `note.*` is interchangeable with `file.*`; `dir` = `file.folder`; `body` = `file.body`; `name` = `file.name`
- **Base formulas:** When opened via `:Vault process base <name>`, formula columns from the `.base` file are computed and displayed as read-only

Empty cells show `∅`. Tags are formatted as `#tag1 #tag2`.

### Keymaps

| Key | Action |
|-----|--------|
| `:w` | Diff against snapshot, apply mutations (update frontmatter, rename files, create notes, trash deletions). |
| `gs` | Cycle sort on column under cursor: none -> asc -> desc -> none. |
| `gS` | Add/cycle secondary sort key on column under cursor (multi-column sort). |
| `gR` | Reload buffer from disk (re-scan vault, refresh all data). |
| `gu` | Plugin-level undo: restore files from pre-save snapshot. |
| `u` | Smart undo: vim undo if available, otherwise falls through to `gu`. |
| `J` | Merge: absorb next line's note into current line's note (frontmatter union, body append, wikilink rewrite, trash source). |
| `gJ` | Merge via picker: Telescope picker of all notes ranked by similarity (Rust slug sim + tag Jaccard + cluster proximity). |
| `g>` / `g<` | Widen / narrow column under cursor by 5 chars. |
| `g}` / `g{` | Move column right / left. |
| `<C-s>` (visual) | Partial save: apply changes for visually selected rows only. |

### Editing Semantics

| Action | Detected as | Result on `:w` |
|--------|-------------|----------------|
| Edit a cell value | Update | Frontmatter rewritten |
| Edit the slug cell | Rename | File moved + wikilinks patched across vault |
| `dd` (delete line) | Delete | Note moved to `.trash/` (with confirmation) |
| `o` / `O` (new line) | Create | New note created with frontmatter from cell values |
| `yyp` (paste) | Create | Pasted line has no extmark = new note |
| `ddp` (swap) | No change | Extmarks follow lines, no diff |
| Clear cell to `∅` | Remove field | Frontmatter key removed entirely |

### Safety

- **Delete hard cap:** refuses to delete more than 100 notes per save.
- **Create hard cap:** refuses to create more than 100 notes per save.
- **Create+delete pairing:** small equal counts (<=5) auto-convert to updates (handles extmark drift).
- **Path validation:** refuses operations that escape vault root.
- **Mtime conflict detection:** warns if file changed on disk since buffer opened.
- **Integrity check:** validates extmarks vs line count, rejects save if inconsistent.
- **TextChanged auto-cancel:** editing buffer while confirmation popup is open cancels the save.

### Undo

The process buffer has a two-tier undo system:

1. **Vim undo (`u`)** -- works for edits before `:w`. After save, the buffer is reloaded so vim's undo tree is reset.
2. **Plugin undo (`gu`)** -- restores all files to their pre-save state. Reverses renames, rewrites original files, deletes files that were created. Single-level (last save only).

`:Vault process undo` is a shortcut for `gu` but only works when the current buffer is the process buffer.

## Wikilink Resolution

The wikilinks picker provides tools for managing link integrity across the vault.

### Resolve Picker

When resolving an unresolved wikilink, a Telescope picker shows:

- **Suggestion matches** (fuzzy/edit-distance from wikilink slug) -- sorted first
- **All notes** in the vault
- **All wikilinks** (resolved and unresolved)
- **"Create new note"** and **"Skip"** special entries

### Note Merge

Merge absorbs one note into another:

1. Parses both notes' frontmatter and body
2. Detects field conflicts and opens a conflict picker (field-by-field A/B choice)
3. Merges frontmatter: A wins by default, arrays are unioned, resolved overrides apply
4. Appends B's body to A
5. Rewrites all `[[B]]` wikilinks to `[[A]]` across the vault
6. Trashes B

Available from the process buffer (`J` / `gJ`) or the wikilinks picker (`<C-j>`).

## Batch Rename

Multi-select items in any Telescope picker with `<Tab>`, then press `<C-r>` to open the rename popup. A NUI floating popup opens with all selected names as editable lines. Edit the names and press `<CR>` to apply all renames at once.

Works for:
- **Notes** -- file move + wikilink patch
- **Tags** -- rewrite across all notes
- **Properties** -- rewrite across all notes

## Bases (Obsidian Bases Compatibility)

Vault.nvim supports `.base` files compatible with [Obsidian Bases](https://help.obsidian.md/bases).

### Base File Structure

```yaml
filter:
  and:
    - file.hasTag: "project"
    - not:
      - file.inFolder: "Archive"
formulas:
  age: "today() - file.ctime"
properties:
  slug: {}
  title: {}
  status:
    displayName: "Status"
  tags: {}
views:
  - type: table
    order: [slug, title, status, tags, formula.age]
```

### Filter Functions

`file.hasTag`, `file.hasLink`, `file.hasProperty`, `file.inFolder`, `file.asLink`, and logical operators (`and:`, `or:`, `not:`).

### Formula Evaluator

Full expression evaluator supporting:
- **Arithmetic:** `+`, `-`, `*`, `/`, `%`
- **Comparison:** `==`, `!=`, `>`, `<`, `>=`, `<=`
- **Logic:** `&&`, `||`, `!`
- **String methods:** `.contains`, `.startsWith`, `.endsWith`, `.lower`, `.split`, `.replace`, `.trim`, `.title`, `.slice`, `.isEmpty`, `.length`
- **Date methods:** `.format`, `.date`, `.time`, `.relative`, `.year`, `.month`, `.day`
- **List methods:** `.contains`, `.join`, `.sort`, `.unique`, `.reverse`, `.slice`, `.length`, `.isEmpty`
- **Global functions:** `date()`, `today()`, `now()`, `if()`, `max()`, `min()`, `link()`, `list()`, `number()`, `duration()`

## Autocompletion

nvim-cmp source providing:
- **Tags** -- triggered by `#`, fuzzy completion of all tags in the vault
- **Dates** -- triggered by `20` (century prefix)
- **Weekdays** -- triggered after a date string

## File Watcher

Watches the vault root for external file changes (e.g., renames in Obsidian or the OS). When a rename is detected (delete + create within a 2-second window), it automatically patches all wikilinks across the vault.

```vim
:Vault watcher start    " start watching
:Vault watcher stop     " stop watching
:Vault watcher status   " check if active
```

Off by default. Enable in config:

```lua
features = { watcher = true }
```

## Configuration

See [docs/installation.md](docs/installation.md) for full configuration reference.

## API

The Lua API is available for scripting and custom integrations. Note that these are Lua-only -- they don't have `:Vault` command equivalents unless listed in the commands section above.

```lua
local vault = require("vault")
vault.setup(opts)               -- setup with options
vault.checkhealth()             -- run :checkhealth vault

-- Direct API access (opens Telescope pickers)
local api = require("vault.api")
api.open_picker_notes_with_tag("project")
api.open_picker_property_values("status")
api.open_picker_notes_with_empty_content()
api.open_picker_notes_without_frontmatter()
api.open_picker_bases()
api.open_picker_base_notes("My Base")
api.open_picker_notes_in_directory("Projects")

-- Vault-wide operations (modify files)
api.rename_tag("old-tag", "new-tag")
api.move_note("old-slug", "new-slug")

-- Note object (operate on a single note)
local Note = require("vault.notes.note")
local note = Note("/path/to/note.md")
note:edit()                     -- open in buffer
note:preview()                  -- glow preview
note:rename("new-name")         -- rename + patch wikilinks
note:move("/new/path.md")       -- move + patch wikilinks
note:delete()                   -- trash
note:delete(true)               -- permanent delete
note:append("- new line")       -- append line to file (no command equivalent)
note:open_in_obsidian()         -- open in Obsidian

-- Collections
local notes = require("vault.notes")()
notes:orphans()                 -- notes with no links
notes:leaves()                  -- notes with inlinks but no outlinks
notes:internals()               -- notes with both in and out links
notes:linked()                  -- notes with at least one inlink
notes:to_cluster(note, 0)       -- BFS wikilink graph from a note
notes:get_random()              -- random note from collection
-- Filter: notes:filter(key, value, match_opt, case_sensitive)
notes:filter("slug", "query", "fuzzy", false)
notes:filter("relpath", "Projects", "startswith", false)

local tags = require("vault.tags")()
tags:filter("name", "project", "startswith")

local bases = require("vault.bases")()
bases:get("My Base"):match_notes(notes.map)
```

## Similar Plugins

- [obsidian.nvim](https://github.com/epwalsh/obsidian.nvim)

## License

[MIT](https://choosealicense.com/licenses/mit/)
