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
vim.keymap.set("n", "<leader>vp", "<cmd>Vault process<cr>", { desc = "Process all notes" })
vim.keymap.set("n", "<leader>vo", "<cmd>Vault process orphans<cr>", { desc = "Process orphans" })
vim.keymap.set("n", "<leader>vg", "<cmd>Vault grep<cr>", { desc = "Grep vault" })
vim.keymap.set("n", "<leader>vT", "<cmd>Vault tags<cr>", { desc = "Tags picker" })
vim.keymap.set("n", "<leader>vw", "<cmd>Vault wikilinks unresolved<cr>", { desc = "Unresolved links" })
vim.keymap.set("n", "<leader>vr", "<cmd>Vault note random<cr>", { desc = "Random note" })
```
