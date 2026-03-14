# Recipes

## Quick Capture

### Open a random note in Obsidian

```lua
require("vault.notes")():get_random():open_in_obsidian()
```

### Append to today's journal from anywhere

```vim
:Vault today append Meeting with team re: launch timeline
```

### Voice capture to daily note

```vim
:Vault today dictate
```

This command only appears when an `ask` binary is found in PATH. It must accept this interface:

```
echo "note context" | ask --dictate --json --context - --placeholder "Say something…"
```

And return JSON on stdout:

```json
{"ok": true, "value": "transcribed text"}
```

The result is appended to today's journal as `- HH:MM:SS <text>`.

To use your own dictation tool, create a wrapper script named `ask` that conforms to this interface. For example, using macOS built-in dictation or Whisper:

```bash
#!/usr/bin/env bash
# ~/bin/ask — minimal wrapper example (implement your own transcription)
# Read --placeholder and --context from args/stdin, present dictation UI,
# output JSON result.
TEXT=$(your-dictation-tool)
echo "{\"ok\": true, \"value\": \"$TEXT\"}"
```

### Extract selection into linked note

Select text in visual mode, then:

```vim
:'<,'>Vault note extract
```

Prompts for a slug, creates the note, replaces selection with a `[[wikilink]]`.

## Triage & Processing

## Task Notes (`:Vault tasks`)

Use `:Vault tasks` for the vault-native task system (task notes in `Tasks/`).

### Create a new task

```vim
:Vault tasks new Implement status transitions
```

Creates `Tasks/T-YYYYMMDDHHmmss Implement status transitions.md` with default frontmatter.

### Promote a daily line into a task

Put cursor on a line like `- [ ] fix command completion`, then:

```vim
:Vault tasks promote
```

The line is replaced with a task wikilink (for example `- [[T-20260306153000 fix command completion]]`).

### Pick the next task

```vim
:Vault tasks pick-next
```

Opens the highest-priority unblocked active task.

### Update task status with transition rules

```vim
:Vault tasks status
:Vault tasks status Status - Todo
```

Without arguments it shows current status and allowed next statuses.
With a status argument it validates and applies the transition.

### Recurring tasks

```vim
:Vault tasks recur preview
:Vault tasks recur now
:Vault tasks recur sweep
```

- `preview` shows the next due date for the current task based on `repeat` rule.
- `now` creates the next recurring instance immediately.
- `sweep` scans completed recurring tasks and creates missing next instances.

Supported `repeat` values include:

- `every day when done`
- `every week when done`
- `every 2 weeks when done`
- `every month when done`
- `every day`
- `every weekday`
- `every week`
- `every other week`
- `every month`

### Open task boards

```vim
:Vault tasks kanban
:Vault tasks backlog
```

These open `Tasks Kanban` and `Tasks Backlog` bases.

### Legacy inline checkboxes

```vim
:Vault actions
```

Use this to browse legacy inline `- [ ]` task lines.

### Process all orphan notes

```vim
:Vault process orphans
```

Opens a spreadsheet view of notes with no inlinks and no outlinks. Edit tags/status inline, `:w` to apply.

### Process notes in a specific folder

```vim
:Vault process dir Projects
```

### Process with custom columns

```vim
:Vault process title,status,tags,file.mtime orphans
```

### Triage empty notes for deletion

```vim
:Vault process empty
```

Scan through, `dd` junk rows, `:w` to trash them.

### Sort by modification time to find stale notes

In the process buffer:

1. Add `file.mtime` to columns: `:Vault process slug,title,tags,file.mtime`
2. `gs` on the `file.mtime` column to sort

### Partial save (selected rows only)

In the process buffer, visually select rows and press `<C-s>` to save only those changes.

## Tags

### Rename a tag across the vault

```vim
:Vault tags rename old-tag new-tag
```

### Merge multiple tags into one

```vim
:Vault tags merge target-tag source-tag-1 source-tag-2
```

### Batch rename tags via Telescope

1. `:Vault tags` to open the tags picker
2. `<Tab>` to multi-select tags
3. `<C-r>` to open the rename popup (NUI float with editable tag names)
4. Edit names, `<CR>` to apply

## Wikilinks

### Find and fix broken links

```vim
:Vault wikilinks unresolved
```

### Batch create notes for unresolved links

1. `:Vault wikilinks unresolved`
2. `<Tab>` to select multiple unresolved wikilinks
3. `<C-a>` to create a note for each selected wikilink

### Batch resolve unresolved links

1. `:Vault wikilinks unresolved`
2. `<Tab>` to select multiple
3. `<C-b>` to step through each one with a resolve picker showing `(1/N)` progress

### Resolve a single wikilink

1. `:Vault wikilinks unresolved`
2. Select a wikilink, press `<C-l>` to open the resolve picker
3. Choose an existing note to rewrite to, create a new note, or skip

## Merging Notes

### Merge adjacent notes in process buffer

In the process buffer, place cursor on a note row and press `J` to merge the next line's note into the current one.

### Merge any note via picker

Press `gJ` in the process buffer to open a Telescope picker of all notes ranked by similarity (slug similarity + tag overlap + wikilink cluster proximity). Select one to merge into the current note.

### Merge workflow

1. Frontmatter fields are unioned (arrays merged, A wins for scalars)
2. If fields conflict, a picker opens for field-by-field A/B choice
3. B's body is appended to A
4. All `[[B]]` wikilinks are rewritten to `[[A]]` across the vault
5. B is trashed

## Calendar

The calendar view places notes on a month grid by a frontmatter date field. It is backed by `vimtable.views.calendar` and works like a visual date picker for your vault.

### Open the calendar

```vim
:Vault calendar
```

Opens a month calendar using the default date field (`due`). Notes with a parseable date in that field appear as cards on the corresponding day cell.

### Choose which date field to use

```vim
:Vault calendar date=created
:Vault calendar date=due
:Vault calendar date=scheduled
```

The `date=` parameter overrides the default `due` field. Any frontmatter key containing an ISO date (`YYYY-MM-DD`) or a daily-note wikilink (`[[2026-03-14 Friday]]`) works.

Built-in virtual fields are also supported:

```vim
:Vault calendar date=file.ctime
:Vault calendar date=file.mtime
:Vault calendar date=file.name
```

- `file.ctime` / `file.mtime` — file creation/modification timestamp
- `file.name` — extracts a date from the filename (useful for daily notes like `2026-03-14.md`)

> **Note:** `file.*` date fields are read-only. You cannot drag cards placed by file timestamps.

### Filter which notes appear

```vim
" Only notes in a specific directory
:Vault calendar dir Projects

" Only notes with a specific tag
:Vault calendar tag meeting

" Only notes matched by a base definition
:Vault calendar base Deadlines

" Combine filters with date override
:Vault calendar date=due tag project
```

### Navigate the calendar

| Key | Action |
|-----|--------|
| `]m` | Next month |
| `[m` | Previous month |
| `H` | Move selected card one day earlier |
| `L` | Move selected card one day later |
| `j` / `k` | Move between cards within a day cell |
| `<CR>` | Open the note under cursor for editing |
| `<C-s>` or `:w` | Save all pending changes |
| `a` | Add a new note on the current day |
| `R` | Reload the calendar from disk |

### Move a note to a different date

1. Navigate to the card you want to move.
2. Press `H` to move it one day earlier or `L` to move it one day later.
3. Press `<C-s>` to save.

The frontmatter date field is rewritten on disk. For fields listed in `link_date_fields` (default: `{ "due" }`), the value is stored as a daily-note wikilink:

```yaml
# Before
due: "[[2026-03-14 Friday]]"

# After pressing L
due: "[[2026-03-15 Saturday]]"
```

For other date fields the value is stored as a plain ISO date:

```yaml
# Before
scheduled: "2026-03-14"

# After pressing L
scheduled: "2026-03-15"
```

### Create a note from the calendar

Press `a` on any day cell. A new note is created with the date field pre-populated:

```yaml
---
title: note-20260314153000
due: "[[2026-03-14 Friday]]"
---
```

The calendar reloads automatically to show the new card.

### Configure the calendar

Add a `calendar` section to your vault setup:

```lua
require("vault").setup({
    calendar = {
        -- Frontmatter key for date placement (or "file.ctime"/"file.mtime"/"file.name")
        date_field = "due",

        -- Fields stored as daily-note wikilinks ([[YYYY-MM-DD Weekday]])
        -- Other date fields are stored as plain ISO dates
        link_date_fields = { "due" },

        -- Optional: end date field for date ranges (shows cards spanning multiple days)
        end_date_field = nil, -- e.g. "end_date"

        -- Field displayed on calendar cards
        primary_field = "title",

        -- Multi-line card fields (nil = primary_field only)
        display_fields = nil, -- e.g. { "title", "status" }

        -- First day of week: 0 = Sunday, 1 = Monday
        first_day = 1,

        -- Max cards shown per day cell before "+N more" overflow
        max_cards_per_cell = 3,

        -- Week/timetable view hour range
        hour_start = 8,
        hour_end = 18,

        -- Override empty cell symbol (nil = use bases.empty_cell)
        empty_cell = nil,

        -- Keymap overrides (set key to false to disable)
        keymaps = {},
    },
})
```

### Use a `.base` file for a calendar view

Create a `.base` file in your vault:

```yaml
# Deadlines.base
views:
  - type: calendar
    name: Deadlines Calendar
    date_field: due
    primary_field: title
    filters:
      and:
        - { property: "due", operator: "is-not-empty" }
```

Then open it:

```vim
:Vault calendar base Deadlines
```

The base filters control which notes appear and the calendar view definition sets the date field and display options.

### Date ranges

If your notes have both a start and end date, configure `end_date_field`:

```lua
require("vault").setup({
    calendar = {
        date_field = "start",
        end_date_field = "end_date",
    },
})
```

Notes will span multiple day cells from `start` to `end_date`.

### Daily notes on a calendar

To see your daily journal entries on a calendar grid:

```vim
:Vault calendar date=file.name dir Journal/Daily
```

This extracts the date from the filename (`2026-03-14.md` -> `2026-03-14`) and shows only notes in the daily journal directory.

### Birthdays and annual recurring dates

For fields like `birthday` or `anniversary` where the event repeats every year, use `annual_fields` to project dates onto the currently viewed year:

```lua
require("vault").setup({
    calendar = {
        annual_fields = { "birthday", "anniversary" },
    },
})
```

Now `:Vault calendar date=birthday` shows a `birthday: "1990-05-15"` card on May 15 of whichever year you're viewing. Navigating to a different year with `]m`/`[m` automatically re-projects.

You can also enable annual mode on-the-fly from the command line:

```vim
:Vault calendar date=birthday annual=true
```

Moving a card with `H`/`L` changes only the month-day on disk — the original year is preserved:

```yaml
# Before pressing L
birthday: "1990-05-15"

# After pressing L
birthday: "1990-05-16"
```

Feb 29 birthdays are clamped to Feb 28 when viewing a non-leap year.

### Suggested keymap

```lua
vim.keymap.set("n", "<leader>vc", "<cmd>Vault calendar<cr>", { desc = "Calendar view" })
vim.keymap.set("n", "<leader>vC", "<cmd>Vault calendar date=file.name dir Journal/Daily<cr>", { desc = "Daily journal calendar" })
```

## Bases

### Create a base for inbox triage

Create `_bases/inbox.base` in your vault:

```yaml
filter:
  not:
    - file.hasTag: "*"
properties:
  slug: {}
  title: {}
  tags: {}
  status: {}
views:
  - type: table
    order: [slug, title, tags, status]
```

Then open it:

```vim
:Vault process base inbox
```

### Create a base with formulas

```yaml
filter:
  file.hasTag: "project"
formulas:
  age: "today() - file.ctime"
  linked: "file.outlinks.length"
properties:
  title: {}
  status: {}
  tags: {}
views:
  - type: table
    order: [title, status, tags, formula.age, formula.linked]
```

## Undo

### Undo the last process buffer save

In the process buffer, press `gu` or run:

```vim
:Vault process undo
```

> Both only work when the current buffer **is** the process buffer. There is no way to undo from a different buffer.

Restores all files to their pre-save state: reverses renames, rewrites originals, deletes created files. Single-level only (last save).

### Smart undo

Press `u` in the process buffer. If vim undo entries exist (edits before `:w`), it uses vim undo. If not, it falls through to plugin undo (`gu`). After `:w`, vim's undo tree is reset because the buffer is reloaded from disk.

## File Watcher

### Enable auto wikilink patching

In your config:

```lua
require("vault").setup({
    features = { watcher = true },
    watcher = {
        auto_update_links = true,
        notify_on_rename = true,
    },
})
```

Now renaming files in Obsidian, Finder, or the terminal will auto-patch wikilinks.

### Manual watcher control

```vim
:Vault watcher start
:Vault watcher stop
:Vault watcher status
```

## Suggested Keymaps

```lua
vim.keymap.set("n", "<leader>vt", "<cmd>Vault today<cr>", { desc = "Today's journal" })
vim.keymap.set("n", "<leader>vf", "<cmd>Vault fleeting<cr>", { desc = "Fleeting note" })
vim.keymap.set("n", "<leader>vn", "<cmd>Vault note<cr>", { desc = "Notes picker" })
vim.keymap.set("n", "<leader>vk", "<cmd>Vault tasks<cr>", { desc = "Task notes picker" })
vim.keymap.set("n", "<leader>vK", "<cmd>Vault tasks pick-next<cr>", { desc = "Pick next task" })
vim.keymap.set("n", "<leader>vp", "<cmd>Vault process<cr>", { desc = "Process all notes" })
vim.keymap.set("n", "<leader>vo", "<cmd>Vault process orphans<cr>", { desc = "Process orphans" })
vim.keymap.set("n", "<leader>vg", "<cmd>Vault grep<cr>", { desc = "Grep vault" })
vim.keymap.set("n", "<leader>vT", "<cmd>Vault tags<cr>", { desc = "Tags picker" })
vim.keymap.set("n", "<leader>vw", "<cmd>Vault wikilinks unresolved<cr>", { desc = "Unresolved links" })
vim.keymap.set("n", "<leader>vr", "<cmd>Vault note random<cr>", { desc = "Random note" })
vim.keymap.set("n", "<leader>vc", "<cmd>Vault calendar<cr>", { desc = "Calendar view" })
vim.keymap.set("n", "<leader>vC", "<cmd>Vault calendar date=file.name dir Journal/Daily<cr>", { desc = "Daily journal calendar" })
```
