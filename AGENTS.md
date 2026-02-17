# AGENTS.md — vault.nvim

Hybrid Lua + Rust Neovim plugin for managing Obsidian-like knowledge vaults.
Lua provides the domain layer and UI; Rust (`vault_core` cdylib) handles
high-performance parallel filesystem scanning via `mlua`/`rayon`.

## Architecture

```
lua/vault/          -- core Lua modules (config, notes, tags, wikilinks, filter, watcher, ...)
lua/vault/core/     -- base abstractions: Object, Collection, State
lua/telescope/_extensions/vault/  -- Telescope pickers, actions, previewers
lua/_cmp/           -- nvim-cmp completion source
src/                -- Rust native module (lib.rs, build.rs)
tests/              -- plenary.nvim test suite
tests/fixtures/     -- demo-vault with sample markdown notes
plugin/             -- Vim plugin loader
```

## Build Commands

Requires a Rust toolchain (cargo) and Neovim 0.10+.

| Command | Description |
|---------|-------------|
| `make build` | Compile Rust module, copy `.dylib`/`.so` to `lua/vault_core.so` |
| `make clean` | `cargo clean` + remove built `.so` |
| `make reload` | Hot-reload plugin in running Neovim via `nvim://cmd` URL scheme |
| `make all` | `build` then `reload` |

## Test Commands

Tests use **plenary.nvim** (busted-style `describe`/`it`) with `tests/minimal_init.lua`
for hermetic isolation. Test targets send commands to a running Neovim instance via
`open "nvim://cmd?run=..."`.

| Command | Description |
|---------|-------------|
| `make test-all` | Run all tests in `tests/` |
| `make test-note` | Run tests in `tests/notes/` only |
| `make test-current` | Run test for the currently open buffer |
| `make test` | `reload` then `test-current` |

To run a **single test file** headlessly (without the Makefile URL scheme):

```bash
nvim --headless -u tests/minimal_init.lua \
  -c "PlenaryBustedFile tests/vault/init_spec.lua"
```

To run a **single test directory**:

```bash
nvim --headless -u tests/minimal_init.lua \
  -c "PlenaryBustedDirectory tests/vault/notes/ {minimal_init = 'tests/minimal_init.lua'}"
```

Test files follow the pattern `tests/vault/**/*_spec.lua`.
Fixtures live in `tests/fixtures/demo-vault/`.
Global helpers `_G.t.read_file(relpath)` and `_G.t.path(relpath)` are available in tests.

## Formatting & Linting

| Tool | Config | Key settings |
|------|--------|-------------|
| **StyLua** | `.stylua.toml` | 4-space indent, 100 col width, double quotes, Unix line endings |
| **EmmyLuaCodeStyle** | `.editorconfig` | 120 max line length, double quotes, alignment rules |

No `.luacheckrc`, `selene.toml`, or CI pipeline is configured.

Format Lua files:

```bash
stylua lua/ tests/
```

## Code Style

### Indentation & Formatting
- **4 spaces**, no tabs.
- Max line length: 100 (StyLua) / 120 (editorconfig). Break long lines.
- **Double quotes** everywhere (`"string"`, never `'string'`).
- Trailing commas in multiline tables.
- Two blank lines between top-level function definitions.

### Naming Conventions
| Kind | Convention | Example |
|------|-----------|---------|
| Local variables, params | `snake_case` | `tag_name`, `full_path` |
| Class/module tables | `PascalCase` | `Note`, `Collection`, `Filter` |
| Private fields | `_` prefix | `self._map`, `Error._templates` |
| Constants / error codes | `SCREAMING_SNAKE_CASE` | `MISSING_PARAMETER`, `FILE_NOT_FOUND` |
| Enum values | `snake_case` | `match_opts.exact` |
| User commands | `Vault` + `PascalCase` | `VaultNotes`, `VaultTags` |

### Imports
- Always `local` at file top: `local config = require("vault.config")`
- Use double-quoted dotted paths: `require("vault.notes.note")`
- For circular dependencies, use a lazy wrapper:
  ```lua
  local function scanner()
      return require("vault.scanner")
  end
  ```

### Type Annotations (LuaCATS)
Heavy use of LuaCATS annotations. All types use the `vault.` namespace prefix.

```lua
--- @class vault.Note: vault.Object
--- @field data vault.Note.Data

--- @param opts? vault.Config.options
--- @return vault.Notes

--- @alias vault.slug string
--- @alias vault.relpath string
```

Use `--- @diagnostic disable-next-line:` for intentional suppressions.

### Module Export Patterns

**OOP class** (domain objects) -- uses custom `Object()` system:
```lua
local Note = Object("VaultNote")
function Note:init(this) end
function Note:write(path, force) end
local VaultNote = Note
state.set_global_key("class.vault.Note", VaultNote)
return VaultNote
```

**Plain table module** (utilities, config):
```lua
local utils = {}
function utils.path_to_slug(path) end
return utils
```

### Function Definitions
- Colon syntax for instance methods: `function Note:write(path)`
- Dot syntax for static/module functions: `function Scanner.paths(opts)`
- `local function` for file-private helpers.

### Error Handling
- Guard clauses with `error()` for type violations:
  ```lua
  if type(path) ~= "string" then
      error("path must be a string, got " .. type(path))
  end
  ```
- `pcall()` for recoverable operations, report via `vim.notify()`:
  ```lua
  local ok, err = pcall(function() note:move(new_path) end)
  if not ok then
      vim.notify("Failed: " .. tostring(err), vim.log.levels.ERROR)
  end
  ```
- Custom `Error` module with structured codes: `Error.MISSING_PARAMETER("key")`

### Neovim API Usage
- Use `vim.api.*`, `vim.fn.*`, `vim.uv` (with `vim.loop` fallback) directly -- no aliases.
- Use `vim.tbl_deep_extend("force", defaults, overrides)` for merging config tables.
- Use `vim.notify(msg, vim.log.levels.{ERROR,WARN,INFO})` for user messages.
- Define autocmds with `vim.api.nvim_create_autocmd()` table form.
- Define user commands with `vim.api.nvim_create_user_command()`.
- No keymaps in plugin code -- left to users.

### Comments
- `---` (triple dash) for LuaCATS doc comments.
- `--` for inline explanations.
- Mark incomplete work: `-- TODO:`, `-- FIXME:`, `-- TEST:`.

## Rust Module (`src/lib.rs`)

- Edition 2021, compiled as `cdylib` named `vault_core`.
- Uses `mlua` 0.9.9 (LuaJIT + module + serialize) to expose functions to Lua.
- Parallel filesystem walking via `rayon`; regex-based markdown parsing.
- Exports: `paths`, `slugs`, `tags`, `wikilinks`, `tasks`, `links`, `fields`,
  `properties`, `dirs`, `scan`.
- Build script (`src/build.rs`) sets macOS/Linux linker flags for dynamic Lua symbols.

## Dependencies

**Required:** plenary.nvim, telescope.nvim, ripgrep (external)
**Optional:** nvim-cmp, nui.nvim, gradient.nvim, dates.nvim, glow (external, for preview)
