-- lua/vault/bases/editor.lua
-- Obsidian Bases-style editable buffer for vault note metadata.
--
-- Architecture:
--   1. Each data line always starts with the slug cell, even when "hidden".
--      When slug_hidden=true the slug prefix is fully concealed (invisible to user).
--   2. Slug identity comes from slug cell text in the buffer (PRIMARY path).
--      Extmarks are used only for header virt_lines and diff/validation signs.
--   3. buftype=acwrite so :w fires BufWriteCmd instead of touching disk.
--   4. On BufWriteCmd: diff buffer lines against snapshot → mutations.
--   5. Mutations rewrite YAML frontmatter, move/rename, delete, or create.
--   6. After mutations complete, re-scan and re-render.
--
-- Hidden slug design:
--   When user omits slug from their column spec, st.slug_hidden = true.
--   Buffer line format: "<slug>\x1f<vis_cell_1> \x1f <vis_cell_2> ..."
--   The slug prefix is concealed with conceal="" extmarks (NS_CONCEAL namespace).
--   CursorMoved snaps cursor past the concealed prefix so users never land there.
--   reconcile_extmarks PRIMARY path reads cells[1] as slug — always reliable.
--
-- Extmark design (display-only):
--   NS namespace — one extmark per data line at col 0 for header virt_lines.
--   NS_DIFF — diff signs (changes, adds, deletes).
--   NS_CONCEAL — conceal \x1f separators as │, and hidden slug prefix.

local M = {}

-- ─── Highlight groups ─────────────────────────────────────────────────────────
-- Define once on module load; users can override in their colorscheme.
-- Use link-fallback so we work with any theme.
-- Link to standard groups so the colorscheme controls the look.
-- Users can override by defining these groups AFTER loading the plugin.
vim.api.nvim_set_hl(0, "VaultProcessHeader",      { link = "Visual",          default = true })
vim.api.nvim_set_hl(0, "VaultProcessSlug",        { link = "Title",           default = true })
vim.api.nvim_set_hl(0, "VaultProcessFormula",      { link = "Comment",         default = true })
vim.api.nvim_set_hl(0, "VaultProcessFormulaCell",  { link = "DiagnosticHint",  default = true })
vim.api.nvim_set_hl(0, "VaultProcessSep",          { link = "NonText",         default = true })
vim.api.nvim_set_hl(0, "VaultProcessValidationErr", { link = "DiagnosticUnderlineError", default = true })

-- ─── Constants ────────────────────────────────────────────────────────────────

local SEP          = " \x1f "       -- real delimiter: SPACE + Unit Separator (0x1f) + SPACE
local SEP_DISPLAY  = " │ "         -- visual replacement shown via conceal
local SEP_CHAR     = "\x1f"        -- bare delimiter byte (for split_cells)
local SEP_DISPLAY_WIDTH = 3        -- display columns of " │ " (space + pipe + space)
local EMPTY_CELL   = "∅"
local NS           = vim.api.nvim_create_namespace("vault_bases_editor")
local NS_DIFF      = vim.api.nvim_create_namespace("vault_oil_diff")
local NS_ERR       = vim.api.nvim_create_namespace("vault_bases_errors")
local NS_FORMULA   = vim.api.nvim_create_namespace("vault_bases_formula")
local NS_VALID     = vim.api.nvim_create_namespace("vault_bases_validation")
local NS_CONCEAL   = vim.api.nvim_create_namespace("vault_bases_conceal")

-- ─── Per-buffer state ─────────────────────────────────────────────────────────

---@class vault.OilEditState
---@field bufnr              integer
---@field winid              integer
---@field columns            string[]         ALL column names (always includes "slug" first)
---@field col_widths         integer[]        display width per column (all columns)
---@field visible_columns    string[]         columns the user requested (may omit "slug")
---@field visible_col_widths integer[]        display width for visible columns only
---@field slug_hidden        boolean          true when slug not in user's column spec
---@field snapshot           table<string, table<string, string>>  slug → {col → value}
---@field note_paths         table<string, string>  slug → absolute path
---@field mark_to_slug       table<integer, string>  extmark_id → slug  (display-only, not for identity)
---@field slug_to_mark       table<string, integer>  slug → extmark_id
---@field note_mtimes        table<string, integer>  slug → mtime at snapshot time
---@field filter_desc        string           human description of the filter used
---@field saving             boolean
---@field base?              vault.Base       the Base object (if opened via base)
---@field display_names      table<string, string>  col → header display name
---@field formula_cols       string[]         formula column names (read-only)
---@field sort_by?           { col: string, dir: "asc"|"desc" }  primary sort (legacy)
---@field sort_keys?         { col: string, dir: "asc"|"desc" }[]  multi-column sort

local buf_states = {}  -- [bufnr] = vault.OilEditState

-- ─── Undo/rollback storage ────────────────────────────────────────────────────
-- Before each save, we snapshot the raw file contents of all files that will be
-- mutated.  If the user calls M.undo(bufnr), we restore those files.
-- Only the LAST save's snapshot is kept (single-level undo).

---@class vault.ProcessUndoSnapshot
---@field files table<string, string[]>  path → original file lines
---@field created_paths string[]         paths of files created by this save
---@field renames { old_path: string, new_path: string }[]  renames to reverse on undo
---@field timestamp integer              os.time() when snapshot was taken
---@field description string             human-readable summary

local undo_snapshots = {}  -- [bufnr] = vault.ProcessUndoSnapshot

-- ─── Safety utilities ─────────────────────────────────────────────────────────

--- Resolve a path and verify it lives inside the vault root.
--- Returns the resolved absolute path, or nil + error message.
---@param path string
---@return string|nil resolved_path
---@return string|nil error
local function validate_path_in_vault(path)
  local config = require("vault.config")
  local root = vim.fn.resolve(vim.fn.expand(config.options.root))
  local resolved = vim.fn.resolve(vim.fn.expand(path))
  if resolved:sub(1, #root) ~= root then
    return nil, string.format("Path escapes vault root: %s (root: %s)", resolved, root)
  end
  return resolved, nil
end

--- Get file mtime (seconds since epoch). Returns 0 if file doesn't exist.
---@param path string
---@return integer
local function get_mtime(path)
  local stat = vim.uv.fs_stat(path)
  if stat then return stat.mtime.sec end
  return 0
end

--- Quote a YAML scalar value if it contains special characters.
--- Prevents YAML injection from user-edited cell values.
---@param value string
---@return string
local function yaml_quote(value)
  -- Values that YAML would interpret as non-strings must be quoted
  local dominated = value:lower()
  if dominated == "true" or dominated == "false"
    or dominated == "yes" or dominated == "no"
    or dominated == "on" or dominated == "off"
    or dominated == "null" or dominated == "~"
    or value:match("^[%d%.eE%+%-]+$")  -- looks like a number
    or value:match("^[%d]")             -- starts with digit (YAML date/number)
    or value:match("[:#{}%[%]|>%%@`]")  -- contains YAML special chars
    or value:match("^%s") or value:match("%s$")  -- leading/trailing whitespace
    or value:match("^[?&*!]")           -- YAML indicators
    or value == ""
  then
    -- Double-quote and escape internal quotes/backslashes
    return '"' .. value:gsub('\\', '\\\\'):gsub('"', '\\"') .. '"'
  end
  return value
end

--- Write file atomically: write to temp, then rename.
--- Falls back to direct write if rename fails (cross-device).
---@param path string
---@param lines string[]
---@return boolean ok
---@return string|nil error
local function atomic_writefile(path, lines)
  local tmp = path .. ".vault_tmp"
  local ok = pcall(vim.fn.writefile, lines, tmp)
  if not ok then
    return false, "Failed to write temp file: " .. tmp
  end
  -- Rename is atomic on same filesystem
  local rename_ok, rename_err = vim.uv.fs_rename(tmp, path)
  if not rename_ok then
    -- Fallback: direct write (non-atomic but functional)
    pcall(vim.fn.delete, tmp)
    ok = pcall(vim.fn.writefile, lines, path)
    if not ok then
      return false, "Failed to write file: " .. path
    end
  end
  return true, nil
end

-- ─── Default columns ──────────────────────────────────────────────────────────

local DEFAULT_COLUMNS = { "slug", "title", "status", "tags" }

-- ─── Implicit file.* / note.* properties ─────────────────────────────────────

--- Read-only file.* columns (file metadata that cannot be edited in-place).
local READONLY_FILE_COLS = {
  ["file.path"]     = true,
  ["file.ext"]      = true,
  ["file.ctime"]    = true,
  ["file.mtime"]    = true,
  ["file.size"]     = true,
  ["file.inlinks"]  = true,
  ["file.outlinks"] = true,
  ["file.headings"] = true,
}

--- All known file.* implicit property names.
local FILE_IMPLICIT_PROPS = {
  "file.name", "file.folder", "file.path", "file.ext",
  "file.ctime", "file.mtime", "file.size",
  "file.body", "file.slug",
  "file.inlinks", "file.outlinks", "file.headings",
}

--- Normalize column name: note.* → file.*, legacy aliases.
--- Called on user-supplied column specs so internally we always use file.* form.
---@param col string
---@return string
local function normalize_col(col)
  -- note.* → file.* (interchangeable prefixes)
  if col:match("^note%.") then
    col = "file." .. col:sub(6)
  end
  -- Legacy aliases
  if col == "dir"  then return "file.folder" end
  if col == "body" then return "file.body"   end
  if col == "name" then return "file.name"   end
  return col
end

-- ─── Base property key mapping ────────────────────────────────────────────────

--- Map a base property key (e.g. "file.name") to the internal column name
--- used by the editor. Returns the internal name and whether the column is
--- a formula (computed, read-only).
---@param key string  Base property key like "file.name", "formula.x", "tags"
---@return string col_name  Internal column name for build_records
---@return boolean is_formula
local function base_key_to_col(key)
  -- Normalize note.* → file.* first
  key = normalize_col(key)
  if key:match("^formula%.") then return key, true end
  if READONLY_FILE_COLS[key] then return key, true end
  -- Everything else maps directly (file.name, file.folder, file.body, slug, title, tags, etc.)
  return key, false
end

--- Extract columns and display names from a Base object.
--- Uses the first view's order if available, otherwise properties keys.
--- Slug is included only if explicitly listed in the order; otherwise it
--- will be added internally but kept hidden (metadata-only identity).
---@param base vault.Base
---@return string[] columns  Internal column names (always includes "slug")
---@return table<string, string> display_names  col → display name
---@return string[] formula_cols  List of formula column names (read-only)
---@return string[] visible_columns  Columns the user actually wants rendered
local function columns_from_base(base)
  local columns = {}
  local display_names = {}
  local formula_cols = {}

  -- Determine column order: first view's order > properties keys > default
  local order = nil
  if base.data.views and base.data.views[1] and base.data.views[1].order then
    order = base.data.views[1].order
  end
  if not order then
    order = base.data.properties and vim.tbl_keys(base.data.properties) or {}
  end
  if #order == 0 then
    return DEFAULT_COLUMNS, {}, {}, DEFAULT_COLUMNS
  end

  -- Get display name map from base
  local base_display = base:display_names()

  local seen = {}
  local has_slug = false

  for _, key in ipairs(order) do
    local col, is_formula = base_key_to_col(key)
    if col == "slug" then has_slug = true end
    if not seen[col] then
      seen[col] = true
      table.insert(columns, col)
      display_names[col] = base_display[key] or col
      if is_formula then
        table.insert(formula_cols, col)
      end
    end
  end

  -- visible_columns = what the user specified (preserving their order)
  local visible_columns = vim.list_slice(columns, 1)

  -- Ensure slug is always in the internal columns list (for identity)
  if not has_slug then
    table.insert(columns, 1, "slug")
  end

  return columns, display_names, formula_cols, visible_columns
end

-- ─── Value formatting ─────────────────────────────────────────────────────────

---@param value any
---@param col_name? string  column name for context-aware formatting
---@return string
local function fmt_value(value, col_name)
  if value == nil or value == "" then return EMPTY_CELL end
  if type(value) == "boolean" then return value and "true" or "false" end
  if type(value) == "table" then
    -- Date wrapper from evaluator
    if value._type == "date" then
      return os.date("%Y-%m-%d", value.epoch) or EMPTY_CELL
    end
    -- Duration wrapper
    if value._type == "duration" then
      return tostring(value.seconds) .. "s"
    end
    -- Tag list (tags column or list of strings)
    if col_name == "tags" then
      local parts = {}
      for _, v in ipairs(value) do
        if type(v) == "string" and v ~= "" then
          table.insert(parts, v:match("^#") and v or ("#" .. v))
        end
      end
      return #parts > 0 and table.concat(parts, " ") or EMPTY_CELL
    end
    -- Generic list
    if #value > 0 then
      local parts = {}
      for _, v in ipairs(value) do
        table.insert(parts, tostring(v))
      end
      return table.concat(parts, ", ")
    end
    return EMPTY_CELL
  end
  return tostring(value)
end

--- Parse a cell's display text back into a value for frontmatter.
--- Returns nil for empty/cleared cells — this causes set_frontmatter_field
--- to REMOVE the key from frontmatter entirely (intentional: clearing = deleting).
---@param text string
---@param col_name string
---@return any
local function parse_value(text, col_name)
  if text == EMPTY_CELL or text == "" then return nil end
  if col_name == "tags" then
    local tags = {}
    for tag in text:gmatch("#([^%s#]+)") do
      table.insert(tags, tag)
    end
    return #tags > 0 and tags or nil
  end
  return text
end

-- ─── Column width calculation ─────────────────────────────────────────────────

---@param columns string[]
---@param records table[]  list of {slug, fields={col→value}}
---@return integer[]
local function calc_col_widths(columns, records)
  -- Each column gets exactly the width of its longest value (natural fit).
  -- No artificial capping or scaling — columns are as wide as they need to be.
  -- The buffer scrolls horizontally for overflow; winbar clips.
  -- slug column always scans ALL records — truncated slugs break identity.
  local widths = {}
  for i, col in ipairs(columns) do
    local w = vim.fn.strdisplaywidth(col)  -- at least as wide as the header
    local sample = (col == "slug") and #records or math.min(200, #records)
    for j = 1, sample do
      local cell = fmt_value(records[j].fields[col], col)
      w = math.max(w, vim.fn.strdisplaywidth(cell))
    end
    widths[i] = math.max(w, 8)
  end
  return widths
end

-- ─── String helpers ───────────────────────────────────────────────────────────

---@param s string
---@param width integer
---@return string
local function pad(s, width)
  local dw = vim.fn.strdisplaywidth(s)
  if dw > width then
    -- Only truncate when STRICTLY wider than column
    local r = s
    local chars = width - 1
    while vim.fn.strdisplaywidth(r) > width - 1 and chars > 0 do
      r = vim.fn.strcharpart(s, 0, chars)
      chars = chars - 1
    end
    return r .. "…"
  end
  return s .. string.rep(" ", width - dw)
end

---@param text string
---@return string[]
local function split_cells(text)
  local raw = vim.split(text, SEP_CHAR, { plain = true })
  local cells = {}
  for i, v in ipairs(raw) do
    cells[i] = vim.trim(v)
  end
  return cells
end

-- ─── Extmark slug helpers ─────────────────────────────────────────────────────

--- Get the slug for a buffer row by reading the NS extmark.
---@param bufnr integer
---@param row integer  0-indexed
---@param st vault.OilEditState
---@return string|nil slug
local function get_line_slug(bufnr, row, st)
  local marks = vim.api.nvim_buf_get_extmarks(bufnr, NS, { row, 0 }, { row, -1 }, {})
  for _, mark in ipairs(marks) do
    local slug = st.mark_to_slug[mark[1]]
    if slug then return slug end
  end
  return nil
end

--- Get slug from buffer text (reliable — doesn't depend on extmarks).
--- When slug_hidden, slug is the concealed first cell. When visible, slug is
--- at its vis_cols position. Falls back to extmark if text-based fails.
---@param bufnr integer
---@param row integer  0-indexed
---@param st vault.OilEditState
---@return string|nil slug
local function get_row_slug(bufnr, row, st)
  local line = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1]
  if not line or vim.trim(line) == "" then return nil end
  local cells = split_cells(line)
  if st.slug_hidden then
    -- Slug is always cells[1] when hidden (concealed prefix)
    local s = vim.trim(cells[1] or "")
    if s ~= "" and st.snapshot[s] then return s end
  else
    -- Find slug column in visible columns
    local vis_cols = st.visible_columns or st.columns
    for i, col in ipairs(vis_cols) do
      if col == "slug" then
        local s = vim.trim(cells[i] or "")
        if s ~= "" and st.snapshot[s] then return s end
        break
      end
    end
  end
  -- Fallback to extmark
  return get_line_slug(bufnr, row, st)
end

--- Place a slug identity extmark on a data row.
---@param bufnr integer
---@param row integer  0-indexed
---@param slug string
---@param st vault.OilEditState
---@return integer mark_id
local function set_line_slug(bufnr, row, slug, st)
  local mark_id = vim.api.nvim_buf_set_extmark(bufnr, NS, row, 0, {
    right_gravity = true,
  })
  st.mark_to_slug[mark_id] = slug
  st.slug_to_mark[slug] = mark_id
  return mark_id
end

-- ─── Extmark drift reconciliation ────────────────────────────────────────────
--
-- Problem: nvim_buf_set_lines (used by dd, cc, visual paste, etc.) uses
-- delete+insert semantics that shift extmarks on neighboring rows. This causes
-- slug identity to drift: extmark N may end up on the wrong row, so the diff
-- engine applies changes to the wrong note.
--
-- Solution: before diffing, verify each row's extmark slug by cross-checking
-- the title cell against the snapshot. If drift is detected, reconcile by
-- matching line content (title) to find the true slug for each row.

--- Build a reconciled slug-per-row map.
--- Slug is ALWAYS present in buffer text as cells[1] (when slug_hidden, it's
--- the concealed prefix; when visible, it's the user-visible first column or
--- wherever slug appears in vis_cols).  This PRIMARY path reads slug from
--- buffer text — no extmark dependency.
---@param bufnr integer
---@param st vault.OilEditState
---@param lines string[]  buffer lines (already read)
---@return table<integer, string|nil>  row → slug (nil = genuinely new line)
---@return integer drift_count  number of rows where slug text didn't match extmark
---@return integer reconciled_count  number of drifted rows successfully fixed
local function reconcile_extmarks(bufnr, st, lines)
  local vis_cols = st.visible_columns or st.columns
  local vis_widths = st.visible_col_widths or st.col_widths

  -- When slug_hidden, the raw slug is always cells[1] (the concealed prefix).
  -- When slug is visible, find its index in vis_cols.
  local slug_col_idx
  if st.slug_hidden then
    slug_col_idx = 1  -- concealed prefix = first cell after split on \x1f
  else
    for i, col in ipairs(vis_cols) do
      if col == "slug" then slug_col_idx = i; break end
    end
  end

  -- Build reverse lookup: slug text → true (for fast membership check)
  local snapshot_slugs = {}
  for slug, _ in pairs(st.snapshot) do
    snapshot_slugs[slug] = true
  end

  -- Title index in visible columns (for fallback when slug column text is new/empty)
  local title_col_idx = nil
  -- Cell offset: when slug_hidden, cells[1]=slug, cells[2..]=vis_cols[1..]
  local cell_offset = st.slug_hidden and 1 or 0
  for i, col in ipairs(vis_cols) do
    if col == "title" then title_col_idx = i + cell_offset; break end
  end

  -- Build title reverse lookup as last-resort fallback
  local title_to_slugs = {}
  if title_col_idx then
    for slug, snap in pairs(st.snapshot) do
      local ti = title_col_idx - cell_offset  -- vis_cols index for title
      local title_rendered = vim.trim(pad(fmt_value(snap.title), vis_widths[ti]))
      if not title_to_slugs[title_rendered] then
        title_to_slugs[title_rendered] = {}
      end
      table.insert(title_to_slugs[title_rendered], slug)
    end
  end

  local row_to_slug = {}
  local drift_count = 0
  local reconciled_count = 0
  local claimed_slugs = {}
  local line_count = #lines

  for row = 0, line_count - 1 do
    local line = lines[row + 1]
    if vim.trim(line) == "" then goto continue end

    local cells = split_cells(line)
    local extmark_slug = get_line_slug(bufnr, row, st)

    -- PRIMARY: slug column text (always present — either visible or concealed prefix)
    if slug_col_idx then
      local cell_slug = vim.trim(cells[slug_col_idx] or "")
      if cell_slug ~= "" and snapshot_slugs[cell_slug] and not claimed_slugs[cell_slug] then
        -- Slug text matches a known note — use it directly
        if extmark_slug and extmark_slug ~= cell_slug then
          drift_count = drift_count + 1
          reconciled_count = reconciled_count + 1
        end
        row_to_slug[row] = cell_slug
        claimed_slugs[cell_slug] = true
        goto continue
      end
      -- Slug was edited (rename) or is new text — fall back to extmark
      if extmark_slug and st.snapshot[extmark_slug] and not claimed_slugs[extmark_slug] then
        row_to_slug[row] = extmark_slug
        claimed_slugs[extmark_slug] = true
        goto continue
      end
    end

    -- FALLBACK: title-based matching (for edge cases, e.g. yyp lines)
    if extmark_slug and st.snapshot[extmark_slug] and not claimed_slugs[extmark_slug] then
      row_to_slug[row] = extmark_slug
      claimed_slugs[extmark_slug] = true
    elseif title_col_idx then
      local actual_title = vim.trim(cells[title_col_idx] or "")
      local candidates = title_to_slugs[actual_title]
      if candidates then
        for _, cand_slug in ipairs(candidates) do
          if not claimed_slugs[cand_slug] then
            row_to_slug[row] = cand_slug
            claimed_slugs[cand_slug] = true
            reconciled_count = reconciled_count + 1
            drift_count = drift_count + 1
            break
          end
        end
      end
    end
    -- If still unidentified, row_to_slug[row] stays nil → CREATE

    ::continue::
  end

  return row_to_slug, drift_count, reconciled_count
end

-- ─── Data extraction ──────────────────────────────────────────────────────────

--- Read note frontmatter fields for the given columns.
---@param path string
---@param columns string[]
---@return table<string, any>
local function read_frontmatter_fields(path, columns)
  local fields = {}
  local ok, lines = pcall(vim.fn.readfile, path, "", 50)
  if not ok then return fields end

  if not lines[1] or not lines[1]:match("^%-%-%-") then return fields end
  local fm_lines = {}
  for i = 2, #lines do
    if lines[i]:match("^%-%-%-") then break end
    table.insert(fm_lines, lines[i])
  end

  local current_key = nil
  local current_list = nil
  for _, l in ipairs(fm_lines) do
    local list_item = l:match("^%s+%-%s+(.+)")
    if list_item and current_key and current_list then
      list_item = list_item:gsub('^"(.*)"$', '%1'):gsub("^'(.*)'$", '%1')
      table.insert(current_list, list_item)
    else
      local key, value = l:match("^([%w_%-]+):%s*(.*)")
      if key then
        if current_key and current_list and #current_list > 0 then
          fields[current_key] = current_list
        end
        current_key = key
        current_list = nil

        value = vim.trim(value or "")
        if value == "" then
          current_list = {}
        elseif value:match("^%[") then
          local items = {}
          for item in value:gmatch("[%w/_%-%.]+") do
            table.insert(items, item)
          end
          fields[key] = items
          current_key = nil
        else
          value = value:gsub('^"(.*)"$', '%1'):gsub("^'(.*)'$", '%1')
          value = value:gsub("^%[%[(.-)%]%]$", "%1")
          fields[key] = value
          current_key = nil
        end
      end
    end
  end
  if current_key and current_list and #current_list > 0 then
    fields[current_key] = current_list
  end

  return fields
end

--- Build records from vault scanner data.
---@param notes_map table  slug → Note object (or paths map)
---@param columns string[]
---@param base? vault.Base  optional Base for formula evaluation
---@return table[]  list of {slug, path, fields={col→value}}
local function build_records(notes_map, columns, base)
  local records = {}
  local skipped = 0
  for slug, note in pairs(notes_map) do
    -- pcall: one malformed note must not crash the entire process buffer
    local ok, rec = pcall(function()
      local path = note.data and note.data.path or note.path
      if not path then return nil end

      local fm = read_frontmatter_fields(path, columns)
      local fields = {}

      -- Evaluate formulas once per note if base has them
      local formula_results = {}
      if base and base:has_formulas() then
        formula_results = base:evaluate_formulas(note)
      end

      for _, col in ipairs(columns) do
        if col == "slug" then
          fields.slug = slug

        -- ── file.* / note.* implicit properties ──────────────
        elseif col == "file.name" then
          fields[col] = note.data and note.data.stem
            or (slug:match("[^/]+$") or slug)
        elseif col == "file.slug" then
          fields[col] = slug
        elseif col == "file.folder" then
          local relpath = note.data and note.data.relpath or ""
          local dir = relpath:match("^(.-/)[^/]*$") or ""
          fields[col] = dir ~= "" and dir or "/"
        elseif col == "file.path" then
          fields[col] = note.data and note.data.relpath or ""
        elseif col == "file.ext" then
          fields[col] = "md"
        elseif col == "file.ctime" then
          local t = note.data and note.data.ctime
          fields[col] = t and t > 0 and os.date("%Y-%m-%d %H:%M", t) or ""
        elseif col == "file.mtime" then
          local t = note.data and note.data.mtime
          fields[col] = t and t > 0 and os.date("%Y-%m-%d %H:%M", t) or ""
        elseif col == "file.size" then
          fields[col] = path and vim.fn.getfsize(path) or 0
        elseif col == "file.body" then
          -- Read a limited preview (first 4 KB) to avoid full-file I/O for large vaults.
          -- Skips the YAML frontmatter block, then flattens to a single line.
          local body = ""
          local f = path and io.open(path, "r")
          if f then
            local chunk = f:read(4096) or ""
            f:close()
            -- Strip leading frontmatter (--- ... ---\n)
            local after_fm = chunk:match("^%-%-%-.-\n%-%-%-\n(.*)") or chunk
            body = after_fm
          end
          fields[col] = body:gsub("\r?\n", " "):gsub("%s+", " "):match("^%s*(.-)%s*$") or ""
        elseif col == "file.inlinks" then
          local links = note.data and note.data.inlinks
          if links then
            local slugs = {}
            for s, _ in pairs(links) do table.insert(slugs, s) end
            table.sort(slugs)
            fields[col] = table.concat(slugs, ", ")
          else
            fields[col] = ""
          end
        elseif col == "file.outlinks" then
          local links = note.data and note.data.outlinks
          if links then
            local slugs = {}
            for s, _ in pairs(links) do table.insert(slugs, s) end
            table.sort(slugs)
            fields[col] = table.concat(slugs, ", ")
          else
            fields[col] = ""
          end
        elseif col == "file.headings" then
          local hdgs = note.data and note.data.headings
          if hdgs and #hdgs > 0 then
            fields[col] = hdgs[1].text or hdgs[1][2] or ""
          else
            fields[col] = ""
          end

        -- ── Legacy columns (kept for backward compat) ────────
        elseif col == "title" then
          local basename = slug:match("[^/]+$") or slug
          fields.title = fm.title or (note.data and note.data.stem) or basename
        elseif col == "dir" then
          local relpath = note.data and note.data.relpath or ""
          local dir = relpath:match("^(.-/)[^/]*$") or ""
          fields.dir = dir ~= "" and dir or "/"
        elseif col == "tags" then
          fields.tags = fm.tags or (note.data and note.data.frontmatter and note.data.frontmatter.tags) or nil

        -- ── Formula columns ──────────────────────────────────
        elseif col:match("^formula%.") then
          local formula_name = col:match("^formula%.(.+)")
          fields[col] = formula_results[formula_name]

        -- ── Generic frontmatter key ──────────────────────────
        else
          fields[col] = fm[col]
        end
      end
      return { slug = slug, path = path, fields = fields }
    end)

    if ok and rec then
      table.insert(records, rec)
    else
      skipped = skipped + 1
    end
  end
  if skipped > 0 then
    vim.notify(
      string.format("[vault] Warning: %d notes skipped due to parse errors", skipped),
      vim.log.levels.WARN
    )
  end
  table.sort(records, function(a, b) return a.slug < b.slug end)
  return records
end

-- ─── Sorting ──────────────────────────────────────────────────────────────────

--- Sort records by one or more columns.
--- Supports both single sort_by (legacy) and multi-column sort_keys.
---@param records table[]
---@param sort_by? { col: string, dir: "asc"|"desc" }  primary sort (single column)
---@param sort_keys? { col: string, dir: "asc"|"desc" }[]  multi-column sort
---@return table[]  same table, sorted in place
local function sort_records(records, sort_by, sort_keys)
  -- Build effective sort key list
  local keys = sort_keys
  if not keys or #keys == 0 then
    if sort_by and sort_by.col then
      keys = { sort_by }
    else
      table.sort(records, function(a, b) return a.slug < b.slug end)
      return records
    end
  end

  -- Pre-compute sort values per column per record
  local precomputed = {}  -- [col] = { [slug] = sort_val }
  for _, sk in ipairs(keys) do
    if not precomputed[sk.col] then
      local col_keys = {}
      for _, rec in ipairs(records) do
        local v = rec.fields[sk.col]
        if v == nil or v == "" then
          col_keys[rec.slug] = nil
        elseif type(v) == "table" then
          col_keys[rec.slug] = fmt_value(v, sk.col):lower()
        else
          col_keys[rec.slug] = tostring(v):lower()
        end
      end
      precomputed[sk.col] = col_keys
    end
  end

  table.sort(records, function(a, b)
    for _, sk in ipairs(keys) do
      local va = precomputed[sk.col][a.slug]
      local vb = precomputed[sk.col][b.slug]
      local is_desc = sk.dir == "desc"

      -- Nil sorts last (regardless of direction)
      if va == nil and vb == nil then goto next_key end
      if va == nil then return false end
      if vb == nil then return true end

      -- Numeric comparison
      local na, nb = tonumber(va), tonumber(vb)
      if na and nb then
        if na ~= nb then
          if is_desc then return na > nb else return na < nb end
        end
      else
        -- String comparison
        if va ~= vb then
          if is_desc then return va > vb else return va < vb end
        end
      end

      ::next_key::
    end
    return a.slug < b.slug  -- tiebreaker
  end)

  return records
end

--- Extract sort_by from a base view definition.
---@param base vault.Base
---@return { col: string, dir: "asc"|"desc" }|nil
local function sort_from_base(base)
  if not base.data.views or not base.data.views[1] then return nil end
  local view = base.data.views[1]
  if not view.sort_by then return nil end

  local sort = view.sort_by
  local key = sort.key or sort[1]
  if not key then return nil end

  local col = base_key_to_col(key)
  local dir = sort.direction or sort.dir or "asc"
  return { col = col, dir = dir }
end

-- ─── Snapshot ─────────────────────────────────────────────────────────────────

---@param records table[]
---@param columns string[]
---@return table<string, table<string, any>>
local function build_snapshot(records, columns)
  local snap = {}
  for _, rec in ipairs(records) do
    local row = {}
    for _, col in ipairs(columns) do
      row[col] = rec.fields[col]
    end
    snap[rec.slug] = row
  end
  return snap
end

-- ─── Rendering ────────────────────────────────────────────────────────────────

---@param rec table
---@param columns string[]  visible columns only
---@param widths integer[]  widths matching visible columns
---@param slug_hidden? boolean  when true, prepend raw slug + SEP_CHAR before visible cells
---@return string
local function render_record_line(rec, columns, widths, slug_hidden, slug_width)
  -- When slug is hidden, prepend the raw slug padded to slug_width as the first
  -- (concealed) cell.  Fixed-width padding is critical: without it, horizontal
  -- scrolling misaligns rows because Neovim offsets by bytes, and different slug
  -- lengths would shift the visible content start.
  local prefix = ""
  if slug_hidden then
    local padded_slug = slug_width and pad(rec.slug, slug_width) or rec.slug
    prefix = padded_slug .. SEP_CHAR
  end
  local cells = {}
  for i, col in ipairs(columns) do
    local cell = fmt_value(rec.fields[col], col)
    table.insert(cells, pad(cell, widths[i]))
  end
  return prefix .. table.concat(cells, SEP)
end

--- Build the header virt_lines chunks for display above row 0.
---@param st vault.OilEditState
---@return table[] virt_lines  list of {chunks} for nvim_buf_set_extmark virt_lines
local function build_header_virt_lines(st)
  -- Separator row only (header is now in winbar)
  local vis_widths = st.visible_col_widths or st.col_widths
  local vis_cols = st.visible_columns or st.columns
  local sep_parts = {}
  for i, _ in ipairs(vis_cols) do
    table.insert(sep_parts, string.rep("─", vis_widths[i]))
  end
  local sep_text = table.concat(sep_parts, "─┼─")

  return {
    { { sep_text, "Comment" } },
  }
end

--- Compute the gutter width (number column + sign column) for a window.
---@param winid integer
---@return integer textoff  number of screen columns used by gutter
local function get_textoff(winid)
  local textoff = 0
  local wo = vim.wo[winid]
  if wo.number or wo.relativenumber then
    local bufnr_w = vim.api.nvim_win_get_buf(winid)
    local line_count = vim.api.nvim_buf_line_count(bufnr_w)
    local num_digits = math.max(wo.numberwidth or 4, #tostring(line_count) + 1)
    textoff = textoff + num_digits
  end
  if wo.signcolumn == "yes" or wo.signcolumn == "auto" then
    textoff = textoff + 2
  end
  return textoff
end

--- Build the full header as a list of {text, hl_group} chunks.
--- Each chunk represents one cell label (padded) or a separator.
--- The chunks are NOT escaped for winbar — they are plain text + hl names.
---@param st vault.OilEditState
---@return {text:string, hl:string}[]
local function build_header_chunks(st)
  local vis_cols = st.visible_columns or st.columns
  local vis_widths = st.visible_col_widths or st.col_widths
  local chunks = {}
  local formula_set = {}
  if st.formula_cols then
    for _, fc in ipairs(st.formula_cols) do formula_set[fc] = true end
  end
  for i, col in ipairs(vis_cols) do
    local label = (st.display_names and st.display_names[col]) or col
    -- Add lock icon for formula (read-only) columns
    if formula_set[col] then
      label = label .. " 🔒"
    end
    -- Show sort indicators (support multi-column sort)
    if st.sort_keys and #st.sort_keys > 0 then
      for si, sk in ipairs(st.sort_keys) do
        if sk.col == col then
          local arrow = sk.dir == "asc" and "▲" or "▼"
          label = label .. " " .. arrow .. (#st.sort_keys > 1 and tostring(si) or "")
        end
      end
    elseif st.sort_by and st.sort_by.col == col then
      label = label .. (st.sort_by.dir == "asc" and " ▲" or " ▼")
    end
    local padded = pad(label, vis_widths[i])
    local hl = col == "slug" and "VaultProcessSlug"
           or formula_set[col] and "VaultProcessFormula"
           or "VaultProcessHeader"
    table.insert(chunks, { text = padded, hl = hl })
    if i < #vis_cols then
      table.insert(chunks, { text = SEP_DISPLAY, hl = "VaultProcessSep" })
    end
  end
  return chunks
end

--- Build and set the winbar for the given window, respecting horizontal scroll.
--- Called on open, reload, sort change, and WinScrolled/CursorMoved.
---@param winid integer
---@param st vault.OilEditState
local function set_winbar(winid, st)
  if not vim.api.nvim_win_is_valid(winid) then return end

  local textoff = get_textoff(winid)
  -- leftcol: how many virtual columns the buffer has scrolled right.
  -- Neovim computes leftcol in virtcol space, which counts concealed bytes.
  -- When slug_hidden, the concealed prefix (slug + \x1f) adds phantom width
  -- to leftcol that has no corresponding header content.  Subtract it so the
  -- header aligns with the visible buffer content.
  local leftcol = vim.api.nvim_win_call(winid, function()
    return vim.fn.winsaveview().leftcol
  end)
  -- When slug_hidden, leftcol includes the concealed prefix's virtual width
  -- (Neovim counts concealed bytes in leftcol space).  Subtract the phantom
  -- width to get the real scroll offset within the visible columns.
  -- When leftcol < phantom the cursor is in the phantom zone — the concealed
  -- region has 0 display width so the visible data is still at screen col 0.
  -- In both cases: clamp to 0, never add leading spaces.
  if st.slug_hidden and st._slug_phantom_vcol then
    leftcol = math.max(0, leftcol - st._slug_phantom_vcol)
  end

  -- Build full header chunks then skip/trim based on adjusted leftcol
  local chunks = build_header_chunks(st)

  -- Walk chunks, skipping characters before leftcol
  local skip = leftcol   -- screen columns still to skip
  local winbar_parts = {}
  for _, chunk in ipairs(chunks) do
    local text = chunk.text
    local w = vim.fn.strdisplaywidth(text)
    if skip >= w then
      -- entire chunk is off-screen to the left — skip it
      skip = skip - w
    elseif skip > 0 then
      -- partial skip: trim leading characters
      -- advance char-by-char until we've consumed `skip` display columns
      local char_idx = 0
      local consumed = 0
      while consumed < skip do
        char_idx = char_idx + 1
        local ch = vim.fn.strcharpart(text, char_idx - 1, 1)
        consumed = consumed + vim.fn.strdisplaywidth(ch)
      end
      text = vim.fn.strcharpart(text, char_idx)
      skip = 0
      local esc = text:gsub("%%", "%%%%")
      table.insert(winbar_parts, "%#" .. chunk.hl .. "#" .. esc .. "%*")
    else
      local esc = text:gsub("%%", "%%%%")
      table.insert(winbar_parts, "%#" .. chunk.hl .. "#" .. esc .. "%*")
    end
  end

  local prefix = string.rep(" ", textoff)
  local cells_str = table.concat(winbar_parts)
  local winbar_str = "%#VaultProcessHeader#" .. prefix .. cells_str .. "%#VaultProcessHeader#%="

  vim.wo[winid].winbar = winbar_str
end

--- Build data lines (no header — header is virtual).
--- Uses visible_columns for rendering (slug may be hidden).
---@param st vault.OilEditState
---@param records table[]
---@return string[]
local function build_data_lines(st, records)
  local vis_cols = st.visible_columns or st.columns
  local vis_widths = st.visible_col_widths or st.col_widths
  local lines = {}
  for _, rec in ipairs(records) do
    table.insert(lines, render_record_line(rec, vis_cols, vis_widths, st.slug_hidden, st.col_widths[1]))
  end
  return lines
end

-- ─── Buffer management ────────────────────────────────────────────────────────

---@param bufnr integer
---@param lines string[]
local function set_buffer_lines(bufnr, lines)
  local saved_ul = vim.bo[bufnr].undolevels
  local saved_ei = vim.o.eventignore
  vim.o.eventignore = "TextChanged,TextChangedI,TextChangedP"
  vim.bo[bufnr].undolevels = -1
  vim.bo[bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.bo[bufnr].modified   = false
  vim.bo[bufnr].undolevels = saved_ul
  vim.o.eventignore = saved_ei
end

--- Apply all extmarks: slug identity on data lines + header virt_lines on row 0.
---@param bufnr integer
---@param st vault.OilEditState
---@param records table[]
local function apply_extmarks(bufnr, st, records)
  vim.api.nvim_buf_clear_namespace(bufnr, NS, 0, -1)
  st.mark_to_slug = {}
  st.slug_to_mark = {}

  -- Header as virtual lines above row 0
  if #records > 0 then
    local virt_lines = build_header_virt_lines(st)
    vim.api.nvim_buf_set_extmark(bufnr, NS, 0, 0, {
      virt_lines_above = true,
      virt_lines = virt_lines,
    right_gravity = true,
      -- This extmark is just for the header; don't track it as a slug
    })
  end

  -- Slug identity extmark on each data line
  for i, rec in ipairs(records) do
    local row = i - 1  -- 0-indexed (no header lines in buffer)
    set_line_slug(bufnr, row, rec.slug, st)
  end
end

-- ─── Conceal separators ───────────────────────────────────────────────────────

--- Conceal the hidden slug prefix on a single line.
--- When slug_hidden=true, each line starts with "<slug>\x1f" which must be
--- fully concealed (empty replacement text).  The first \x1f is the slug/visible
--- separator — conceal it as "" (invisible).  Subsequent \x1f are visible
--- column separators and get the normal "│" conceal.
---@param bufnr integer
---@param row integer  0-indexed
---@param line string
---@param slug_hidden boolean
local function conceal_line(bufnr, row, line, slug_hidden)
  local start = 1
  local first_sep = true  -- track whether we're at the slug/visible separator
  while true do
    local pos = line:find(SEP_CHAR, start, true)
    if not pos then break end
    if slug_hidden and first_sep then
      -- Conceal the entire slug prefix: bytes 0 through pos (inclusive of \x1f)
      -- This makes the slug text + separator completely invisible.
      pcall(vim.api.nvim_buf_set_extmark, bufnr, NS_CONCEAL, row, 0, {
        end_col = pos,  -- covers slug text + \x1f byte
        conceal = "",   -- empty = fully hidden
        right_gravity = false,
      })
      first_sep = false
    else
      pcall(vim.api.nvim_buf_set_extmark, bufnr, NS_CONCEAL, row, pos - 1, {
        end_col = pos,  -- single byte
        conceal = "│",
        right_gravity = false,
      })
    end
    start = pos + 1
  end
end

--- Apply conceal extmarks on every \x1f byte so it displays as │.
--- When slug_hidden, also conceal the slug prefix on each line.
---@param bufnr integer
---@param slug_hidden? boolean
local function apply_conceal(bufnr, slug_hidden)
  vim.api.nvim_buf_clear_namespace(bufnr, NS_CONCEAL, 0, -1)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  for row, line in ipairs(lines) do
    conceal_line(bufnr, row - 1, line, slug_hidden or false)
  end
end

--- Incrementally apply conceal on a single line (for TextChanged).
---@param bufnr integer
---@param row integer  0-indexed
---@param slug_hidden? boolean
local function apply_conceal_line(bufnr, row, slug_hidden)
  -- Clear conceal extmarks on this row only
  local existing = vim.api.nvim_buf_get_extmarks(bufnr, NS_CONCEAL, {row, 0}, {row, -1}, {})
  for _, mark in ipairs(existing) do
    vim.api.nvim_buf_del_extmark(bufnr, NS_CONCEAL, mark[1])
  end
  local line = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1]
  if not line then return end
  conceal_line(bufnr, row, line, slug_hidden or false)
end

-- ─── Formula cell highlighting ────────────────────────────────────────────────

--- Apply dim highlights on formula (read-only) column cells so they are
--- visually distinct from editable cells.  Also adds a 🔒 virtual text
--- indicator at the end of each formula cell.
---@param bufnr integer
---@param st vault.OilEditState
local function highlight_formula_cells(bufnr, st)
  vim.api.nvim_buf_clear_namespace(bufnr, NS_FORMULA, 0, -1)
  if not st.formula_cols or #st.formula_cols == 0 then return end

  local formula_set = {}
  for _, fc in ipairs(st.formula_cols) do formula_set[fc] = true end

  -- Compute byte offsets for each formula column (visible columns only)
  local vis_cols = st.visible_columns or st.columns
  local vis_widths = st.visible_col_widths or st.col_widths
  -- Relative offsets within the visible region (after slug prefix if hidden)
  local formula_rel_ranges = {}  -- list of { col_idx, rel_start, rel_end }
  for i, col in ipairs(vis_cols) do
    if formula_set[col] then
      local rel_start = 0
      for j = 1, i - 1 do
        rel_start = rel_start + vis_widths[j] + #SEP
      end
      local rel_end = rel_start + vis_widths[i]
      table.insert(formula_rel_ranges, { idx = i, rel_start = rel_start, rel_end = rel_end })
    end
  end

  if #formula_rel_ranges == 0 then return end

  local line_count = vim.api.nvim_buf_line_count(bufnr)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  for row = 0, line_count - 1 do
    -- When slug_hidden, compute the slug prefix byte length for this line
    local prefix_len = 0
    if st.slug_hidden then
      local line = lines[row + 1] or ""
      local first_sep = line:find(SEP_CHAR, 1, true)
      if first_sep then prefix_len = first_sep end  -- includes the \x1f byte
    end
    for _, range in ipairs(formula_rel_ranges) do
      pcall(vim.api.nvim_buf_set_extmark, bufnr, NS_FORMULA, row, prefix_len + range.rel_start, {
        end_row = row,
        end_col = prefix_len + range.rel_end,
        hl_group = "VaultProcessFormulaCell",
      })
    end
  end
end

-- ─── Inline validation ────────────────────────────────────────────────────────

--- Validate buffer cells on TextChanged.  Highlights cells that contain
--- values which would be rejected on save (formula edits, truncated values).
---@param bufnr integer
---@param st vault.OilEditState
local function update_validation(bufnr, st)
  vim.api.nvim_buf_clear_namespace(bufnr, NS_VALID, 0, -1)
  if not st.formula_cols or #st.formula_cols == 0 then
    -- No formula columns → nothing special to validate
  end

  local formula_set = {}
  if st.formula_cols then
    for _, fc in ipairs(st.formula_cols) do formula_set[fc] = true end
  end

  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local row_to_slug = reconcile_extmarks(bufnr, st, lines)

  for row = 0, #lines - 1 do
    local line = lines[row + 1]
    if vim.trim(line) == "" then goto continue end
    local slug = row_to_slug[row]
    if not slug then goto continue end

    local orig = st.snapshot[slug]
    if not orig then goto continue end

    local cells = split_cells(line)
    local co = st.slug_hidden and 1 or 0
    -- When slug_hidden, byte_offset starts after the concealed slug prefix
    local byte_offset = 0
    if st.slug_hidden then
      -- Skip slug cell bytes + SEP_CHAR byte
      local slug_cell = cells[1] or ""
      byte_offset = #slug_cell + #SEP_CHAR
    end
    local vis_cols = st.visible_columns or st.columns
    local vis_widths = st.visible_col_widths or st.col_widths

    for i, col in ipairs(vis_cols) do
      local cell_text = cells[i + co] or ""
      local old_rendered = vim.trim(pad(fmt_value(orig[col], col), vis_widths[i]))
      local sep_len = (i > 1) and #SEP or 0
      local col_start = byte_offset + sep_len
      local col_end = col_start + vis_widths[i]

      if old_rendered ~= cell_text then
        if formula_set[col] then
          -- Formula column edited — highlight as error
          pcall(vim.api.nvim_buf_set_extmark, bufnr, NS_VALID, row, col_start, {
            end_row = row, end_col = math.min(col_end, #line),
            hl_group = "VaultProcessValidationErr",
            virt_text = { { " read-only", "DiagnosticError" } },
            virt_text_pos = "inline",
          })
        elseif cell_text:match("…$") and old_rendered:match("…$") then
          -- Truncated column edited — highlight as warning
          pcall(vim.api.nvim_buf_set_extmark, bufnr, NS_VALID, row, col_start, {
            end_row = row, end_col = math.min(col_end, #line),
            hl_group = "DiagnosticUnderlineWarn",
            virt_text = { { " truncated", "DiagnosticWarn" } },
            virt_text_pos = "inline",
          })
        end
      end

      byte_offset = col_end + sep_len
    end
    ::continue::
  end
end

-- ─── Diff signs ───────────────────────────────────────────────────────────────

---@param bufnr integer
---@param st vault.OilEditState
local function update_diff_signs(bufnr, st)
  vim.api.nvim_buf_clear_namespace(bufnr, NS_DIFF, 0, -1)
  local line_count = vim.api.nvim_buf_line_count(bufnr)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local seen = {}

  -- Use reconciled slugs for diff signs (consistent with save logic)
  local row_to_slug = reconcile_extmarks(bufnr, st, lines)

  for row = 0, line_count - 1 do
    local line = lines[row + 1]
    if vim.trim(line) == "" then goto continue end

    local slug = row_to_slug[row]
    if not slug then
      -- No identity → new note
      local cells = split_cells(line)
      local has_content = false
      for _, c in ipairs(cells) do
        if vim.trim(c) ~= "" and vim.trim(c) ~= EMPTY_CELL then has_content = true; break end
      end
      if has_content then
        vim.api.nvim_buf_set_extmark(bufnr, NS_DIFF, row, 0, {
          sign_text = "+", sign_hl_group = "DiffAdd", priority = 30,
        })
      end
    else
      seen[slug] = true
      local orig = st.snapshot[slug]
      if orig then
        local cells = split_cells(line)
        local changed = false
        local vis_cols_d = st.visible_columns or st.columns
        local vis_widths_d = st.visible_col_widths or st.col_widths
        local co = st.slug_hidden and 1 or 0
        for i, col in ipairs(vis_cols_d) do
          local old_rendered = vim.trim(pad(fmt_value(orig[col], col), vis_widths_d[i]))
          if old_rendered ~= (cells[i + co] or "") then changed = true; break end
        end
        if changed then
          vim.api.nvim_buf_set_extmark(bufnr, NS_DIFF, row, 0, {
            sign_text = "~", sign_hl_group = "DiffChange", priority = 30,
          })
        end
      end
    end
    ::continue::
  end

  -- Count deletes
  local deleted = 0
  for slug, _ in pairs(st.snapshot) do
    if not seen[slug] then deleted = deleted + 1 end
  end
  if deleted > 0 and line_count > 0 then
    local del_text = deleted > 99 and "##" or tostring(deleted)
    -- sign_text must be 1-2 display cells; truncate for large numbers
    if #del_text > 2 then del_text = del_text:sub(1, 2) end
    vim.api.nvim_buf_set_extmark(bufnr, NS_DIFF, 0, 0, {
      sign_text = del_text, sign_hl_group = "DiffDelete", priority = 30,
    })
  end
end

-- ─── Diff engine ──────────────────────────────────────────────────────────────

---@class vault.OilEditDiff
---@field updates table[]  {slug: string, fields: table<string, any>}
---@field deletes string[]  slugs
---@field creates table[]  {fields: table<string, any>}
---@field _integrity_error? boolean  true if extmark integrity check failed

---@param bufnr integer
---@param st vault.OilEditState
---@param silent? boolean  if true, suppress drift notifications (used during on_save)
---@return vault.OilEditDiff
local function diff_buffer(bufnr, st, silent)
  local diff = { updates = {}, deletes = {}, creates = {}, renames = {}, errors = {} }
  local line_count = vim.api.nvim_buf_line_count(bufnr)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local seen = {}

  -- ── Reconcile extmark drift before diffing ──────────────────────────────
  local row_to_slug, drift_count, reconciled_count = reconcile_extmarks(bufnr, st, lines)

  -- Drift during a save is expected (user edited a slug cell — the cell text
  -- changed but extmarks still hold the old slug until reload).  Suppress the
  -- notification in that case; only surface it during background diff checks.
  if drift_count > 0 and not silent then
    vim.notify(
      string.format(
        "[vault] %d row%s lost identity tracking — %d recovered. If data looks wrong, reopen with :Vault process",
        drift_count, drift_count == 1 and "" or "s", reconciled_count
      ),
      drift_count > reconciled_count and vim.log.levels.WARN or vim.log.levels.INFO
    )
  end

  -- Count non-empty lines and identified lines for integrity check
  local non_empty_lines = 0
  local identified_lines = 0

  for row = 0, line_count - 1 do
    local line = lines[row + 1]
    if vim.trim(line) == "" then goto continue end
    non_empty_lines = non_empty_lines + 1

    local slug = row_to_slug[row]  -- use reconciled slug, not raw extmark
    local cells = split_cells(line)

    -- Cell offset: when slug_hidden, cells[1]=slug prefix, cells[2..]=vis_cols
    local co = st.slug_hidden and 1 or 0

    if slug then
      identified_lines = identified_lines + 1
      seen[slug] = true
      local orig = st.snapshot[slug]
      if orig then
        local changed_fields = {}
        local has_changes = false
        -- Build formula set for quick lookup
        local formula_set = {}
        if st.formula_cols then
          for _, fc in ipairs(st.formula_cols) do formula_set[fc] = true end
        end
        -- Compare visible columns (what's in the buffer) against snapshot
        local vis_cols = st.visible_columns or st.columns
        local vis_widths = st.visible_col_widths or st.col_widths
        for i, col in ipairs(vis_cols) do
          local old_rendered = vim.trim(pad(fmt_value(orig[col], col), vis_widths[i]))
          local new_text = cells[i + co] or ""
          if old_rendered ~= new_text then
            -- Formula columns are read-only — warn but skip
            if formula_set[col] then
              table.insert(diff.errors, {
                row = row, col_idx = i,
                message = string.format("Column '%s' is read-only (computed formula) — edit ignored", col),
              })
              goto next_col
            end
            -- Slug or file.slug column → rename operation
            if col == "slug" or col == "file.slug" then
              local new_slug = vim.trim(new_text)
              if new_slug ~= "" and new_slug ~= slug then
                table.insert(diff.renames, {
                  old_slug = slug,
                  new_slug = new_slug,
                  row = row,
                })
              end
              goto next_col
            end
            -- file.name → rename (change filename stem, keep dir)
            if col == "file.name" then
              local new_stem = vim.trim(new_text)
              local old_stem = (slug:match("[^/]+$") or slug)
              if new_stem ~= "" and new_stem ~= old_stem then
                local dir_prefix = slug:match("^(.-/)[^/]*$") or ""
                table.insert(diff.renames, {
                  old_slug = slug,
                  new_slug = dir_prefix .. new_stem,
                  row = row,
                })
              end
              goto next_col
            end
            -- file.folder → move to different directory
            if col == "file.folder" then
              changed_fields["dir"] = parse_value(new_text, "dir")
              has_changes = true
              goto next_col
            end
            -- Truncated values cannot be reliably saved — warn but skip
            if old_rendered:match("…$") or new_text:match("…$") then
              table.insert(diff.errors, {
                row = row, col_idx = i,
                message = string.format("Column '%s' is truncated — edit ignored (widen column or edit note directly)", col),
              })
              goto next_col
            end
            changed_fields[col] = parse_value(new_text, col)
            has_changes = true
          end
          ::next_col::
        end
        if has_changes then
          table.insert(diff.updates, { slug = slug, fields = changed_fields })
        end
      end
    else
      -- No identity → new note
      local fields = {}
      local has_content = false
      local formula_set = {}
      if st.formula_cols then
        for _, fc in ipairs(st.formula_cols) do formula_set[fc] = true end
      end
      local vis_cols = st.visible_columns or st.columns
      for i, col in ipairs(vis_cols) do
        if formula_set[col] then goto next_create_col end  -- skip formula columns
        local text = cells[i + co] or ""
        if text ~= "" and text ~= EMPTY_CELL then
          fields[col] = parse_value(text, col)
          has_content = true
        end
        ::next_create_col::
      end
      if has_content then
        table.insert(diff.creates, { fields = fields })
      end
    end
    ::continue::
  end

  -- ── SAFETY: Identity integrity check ─────────────────────────────────────
  -- After reconciliation, if we still can't identify most lines, something
  -- is seriously wrong. Refuse operations accordingly.
  local snapshot_size = vim.tbl_count(st.snapshot)

  if snapshot_size > 0 and non_empty_lines > 0 and identified_lines == 0 then
    -- TOTAL identity loss even after reconciliation. Refuse ALL operations.
    vim.notify(
      "[vault] Something went wrong with this buffer — refusing to save. "
        .. "Please close and reopen with :Vault process",
      vim.log.levels.ERROR
    )
    return { updates = {}, deletes = {}, creates = {}, _integrity_error = true }
  end

  if snapshot_size > 0 and identified_lines < non_empty_lines * 0.5 then
    -- PARTIAL identity loss: many lines unidentifiable. Refuse deletes.
    vim.notify(
      string.format(
        "[vault] Only %d of %d rows could be matched to notes — "
          .. "deletes skipped for safety (updates still applied)",
        identified_lines, non_empty_lines
      ),
      vim.log.levels.WARN
    )
    -- Return updates/creates only — no deletes
    return diff
  end

  -- Deletes: in snapshot but not seen on any line
  for slug, _ in pairs(st.snapshot) do
    if not seen[slug] then
      table.insert(diff.deletes, slug)
    end
  end

  return diff
end

-- ─── Mutation engine ──────────────────────────────────────────────────────────

--- Rewrite a single YAML frontmatter field in a file.
---@param path string
---@param key string
---@param value any
local function set_frontmatter_field(path, key, value)
  -- Safety: verify path is inside vault root
  local safe_path, path_err = validate_path_in_vault(path)
  if not safe_path then
    vim.notify("[vault] SAFETY: " .. path_err, vim.log.levels.ERROR)
    return
  end

  local ok, lines = pcall(vim.fn.readfile, safe_path)
  if not ok then return end

  local has_frontmatter = lines[1] and lines[1]:match("^%-%-%-$")
  local fm_end = nil

  if has_frontmatter then
    for i = 2, math.min(#lines, 100) do
      if lines[i]:match("^%-%-%-$") then fm_end = i; break end
    end
    if not fm_end then return end
  else
    -- No frontmatter: create one with just this field
    local new_lines = { "---" }
    if type(value) == "table" then
      table.insert(new_lines, key .. ":")
      for _, v in ipairs(value) do
        table.insert(new_lines, "  - " .. yaml_quote(tostring(v)))
      end
    elseif value ~= nil then
      table.insert(new_lines, key .. ": " .. yaml_quote(tostring(value)))
    end
    table.insert(new_lines, "---")
    for _, l in ipairs(lines) do table.insert(new_lines, l) end
    local write_ok, write_err = atomic_writefile(safe_path, new_lines)
    if not write_ok then
      vim.notify("[vault] SAFETY: " .. write_err, vim.log.levels.ERROR)
    end
    return
  end

  local body_line_count = #lines - fm_end

  local fm_lines = {}
  for i = 2, fm_end - 1 do
    table.insert(fm_lines, lines[i])
  end

  -- Remove existing key and any continuation lines (list items OR nested objects).
  -- Track the original position so we can insert the new value there (preserving order).
  local new_fm = {}
  local skip = false
  local insert_pos = nil
  for _, l in ipairs(fm_lines) do
    if skip then
      if l:match("^%s") then
        goto continue
      else
        skip = false
      end
    end
    if l:match("^" .. vim.pesc(key) .. ":") then
      insert_pos = #new_fm + 1
      skip = true
      goto continue
    end
    table.insert(new_fm, l)
    ::continue::
  end

  -- Build the new value lines (with YAML-safe quoting)
  local new_lines = {}
  if value ~= nil then
    if type(value) == "table" then
      table.insert(new_lines, key .. ":")
      for _, v in ipairs(value) do
        table.insert(new_lines, "  - " .. yaml_quote(tostring(v)))
      end
    else
      table.insert(new_lines, key .. ": " .. yaml_quote(tostring(value)))
    end
  end

  -- Insert at original position (preserving field order) or append if new key
  if #new_lines > 0 then
    if insert_pos then
      for i = #new_lines, 1, -1 do
        table.insert(new_fm, insert_pos, new_lines[i])
      end
    else
      for _, nl in ipairs(new_lines) do
        table.insert(new_fm, nl)
      end
    end
  end

  local result = { "---" }
  for _, l in ipairs(new_fm) do table.insert(result, l) end
  table.insert(result, "---")
  for i = fm_end + 1, #lines do table.insert(result, lines[i]) end

  -- Safety: verify body content is preserved (same number of lines after frontmatter)
  local new_body_count = #result - (#new_fm + 2)  -- +2 for the two "---" lines
  if new_body_count ~= body_line_count then
    vim.notify(
      string.format("[vault] SAFETY: Aborting frontmatter write to %s — body line count mismatch (%d vs %d)",
        vim.fn.fnamemodify(safe_path, ":t"), new_body_count, body_line_count),
      vim.log.levels.ERROR
    )
    return
  end

  local write_ok, write_err = atomic_writefile(safe_path, result)
  if not write_ok then
    vim.notify("[vault] SAFETY: " .. write_err, vim.log.levels.ERROR)
  end
end

--- Batch-set multiple YAML frontmatter fields in a single read-modify-write.
--- Reads the file once, applies all field changes in memory, writes once.
--- This is O(1) file I/O per note regardless of how many fields changed.
---@param path string
---@param fields table<string, any>  key → value (nil value = delete key)
local function set_frontmatter_fields(path, fields)
  if not next(fields) then return end

  -- Safety: verify path is inside vault root
  local safe_path, path_err = validate_path_in_vault(path)
  if not safe_path then
    vim.notify("[vault] SAFETY: " .. path_err, vim.log.levels.ERROR)
    return
  end

  local ok, lines = pcall(vim.fn.readfile, safe_path)
  if not ok then return end

  local has_frontmatter = lines[1] and lines[1]:match("^%-%-%-$")
  local fm_end = nil

  if has_frontmatter then
    for i = 2, math.min(#lines, 100) do
      if lines[i]:match("^%-%-%-$") then fm_end = i; break end
    end
    if not fm_end then
      -- Malformed frontmatter — fall back to per-field writes
      for key, value in pairs(fields) do
        set_frontmatter_field(safe_path, key, value)
      end
      return
    end
  else
    -- No frontmatter: create one with all fields at once
    local new_lines = { "---" }
    for key, value in pairs(fields) do
      if value ~= nil then
        if type(value) == "table" then
          table.insert(new_lines, key .. ":")
          for _, v in ipairs(value) do
            table.insert(new_lines, "  - " .. yaml_quote(tostring(v)))
          end
        else
          table.insert(new_lines, key .. ": " .. yaml_quote(tostring(value)))
        end
      end
    end
    table.insert(new_lines, "---")
    for _, l in ipairs(lines) do table.insert(new_lines, l) end
    local write_ok, write_err = atomic_writefile(safe_path, new_lines)
    if not write_ok then
      vim.notify("[vault] SAFETY: " .. write_err, vim.log.levels.ERROR)
    end
    return
  end

  local body_line_count = #lines - fm_end

  -- Parse existing frontmatter lines
  local fm_lines = {}
  for i = 2, fm_end - 1 do
    table.insert(fm_lines, lines[i])
  end

  -- Process each field: remove old key, track insert position
  local remaining_fields = vim.deepcopy(fields)
  local new_fm = {}
  local skip = false
  local insert_positions = {}  -- key → position where old key was

  for _, l in ipairs(fm_lines) do
    if skip then
      if l:match("^%s") then
        goto continue
      else
        skip = false
      end
    end

    local matched_key = nil
    for key, _ in pairs(remaining_fields) do
      if l:match("^" .. vim.pesc(key) .. ":") then
        matched_key = key
        break
      end
    end

    if matched_key then
      insert_positions[matched_key] = #new_fm + 1
      skip = true
      goto continue
    end

    table.insert(new_fm, l)
    ::continue::
  end

  -- Insert new values at their original positions (preserving order),
  -- or append if the key is new. Process in reverse order of position
  -- to avoid index shifting.
  local inserts = {}  -- { pos, lines[] } sorted by pos descending
  local appends = {}  -- lines to append (new keys)

  for key, value in pairs(remaining_fields) do
    local value_lines = {}
    if value ~= nil then
      if type(value) == "table" then
        table.insert(value_lines, key .. ":")
        for _, v in ipairs(value) do
          table.insert(value_lines, "  - " .. yaml_quote(tostring(v)))
        end
      else
        table.insert(value_lines, key .. ": " .. yaml_quote(tostring(value)))
      end
    end

    if #value_lines > 0 then
      if insert_positions[key] then
        table.insert(inserts, { pos = insert_positions[key], lines = value_lines })
      else
        for _, vl in ipairs(value_lines) do
          table.insert(appends, vl)
        end
      end
    end
  end

  -- Sort inserts by position descending so earlier inserts don't shift later ones
  table.sort(inserts, function(a, b) return a.pos > b.pos end)
  for _, ins in ipairs(inserts) do
    for i = #ins.lines, 1, -1 do
      table.insert(new_fm, ins.pos, ins.lines[i])
    end
  end
  for _, l in ipairs(appends) do
    table.insert(new_fm, l)
  end

  -- Reconstruct file
  local result = { "---" }
  for _, l in ipairs(new_fm) do table.insert(result, l) end
  table.insert(result, "---")
  for i = fm_end + 1, #lines do table.insert(result, lines[i]) end

  -- Safety: verify body content is preserved
  local new_body_count = #result - (#new_fm + 2)
  if new_body_count ~= body_line_count then
    vim.notify(
      string.format("[vault] SAFETY: Aborting batch frontmatter write to %s — body line count mismatch (%d vs %d)",
        vim.fn.fnamemodify(safe_path, ":t"), new_body_count, body_line_count),
      vim.log.levels.ERROR
    )
    return
  end

  local write_ok, write_err = atomic_writefile(safe_path, result)
  if not write_ok then
    vim.notify("[vault] SAFETY: " .. write_err, vim.log.levels.ERROR)
  end
end

--- Snapshot files that will be mutated (for undo support).
--- For renames, also snapshots files across the vault that contain wikilinks
--- to the old slug, since those will be patched by watcher:handle_rename.
---@param diff vault.OilEditDiff
---@param st vault.OilEditState
---@param bufnr integer
local function snapshot_for_undo(diff, st, bufnr)
  local files = {}
  -- Snapshot files that will be updated
  for _, upd in ipairs(diff.updates) do
    local path = st.note_paths[upd.slug]
    if path and vim.fn.filereadable(path) == 1 then
      files[path] = vim.fn.readfile(path)
    end
  end
  -- Snapshot files that will be deleted
  for _, slug in ipairs(diff.deletes) do
    local path = st.note_paths[slug]
    if path and vim.fn.filereadable(path) == 1 then
      files[path] = vim.fn.readfile(path)
    end
  end
  -- (Creates don't need snapshot — undo just deletes the created files)

  -- Snapshot files that contain wikilinks to renamed slugs.
  -- These will be patched by watcher:handle_rename during Note:move.
  if diff.renames and #diff.renames > 0 then
    local scanner = require("vault.scanner")
    local paths = scanner.paths()
    for _, ren in ipairs(diff.renames) do
      local old_path = st.note_paths[ren.old_slug]
      if old_path and vim.fn.filereadable(old_path) == 1 then
        files[old_path] = vim.fn.readfile(old_path)
      end
      -- Find all files that reference the old slug in wikilinks
      local old_stem = vim.fn.fnamemodify(old_path or "", ":t:r")
      local escaped_slug = vim.pesc(ren.old_slug)
      local escaped_stem = vim.pesc(old_stem)
      for _, entry in pairs(paths) do
        local note_path = entry.path
        if not files[note_path] and vim.fn.filereadable(note_path) == 1 then
          local f = io.open(note_path, "r")
          if f then
            local content = f:read("*all")
            f:close()
            -- Check if this file contains wikilinks to the old slug or stem
            if content:match("%[%[" .. escaped_slug) or content:match("%[%[" .. escaped_stem) then
              files[note_path] = vim.split(content, "\n", { plain = true })
            end
          end
        end
      end
    end
  end

  local n_ops = #diff.updates + #diff.deletes + #diff.creates + (#diff.renames or 0)
  undo_snapshots[bufnr] = {
    files = files,
    created_paths = {},  -- will be populated after creates
    renames = {},        -- will be populated during rename processing
    timestamp = os.time(),
    description = string.format(
      "%d updates, %d deletes, %d creates, %d renames",
      #diff.updates, #diff.deletes, #diff.creates, #diff.renames
    ),
  }
end

--- Apply all mutations from a diff.
--- When total operations exceed `ASYNC_THRESHOLD`, mutations are applied
--- in batches via `vim.schedule` so the UI stays responsive and the user
--- sees a progress notification.
---@param diff vault.OilEditDiff
---@param st vault.OilEditState
---@param on_done? fun(n_updates: integer, n_deletes: integer, n_creates: integer)  callback for async mode
---@return integer updates, integer deletes, integer creates  (sync mode only)
local function apply_mutations(diff, st, on_done)
  local n_updates, n_deletes, n_creates = 0, 0, 0
  local ASYNC_THRESHOLD = 10  -- go async when total ops > this

  local total_ops = #diff.updates + #diff.deletes + #diff.creates
  local is_async = total_ops > ASYNC_THRESHOLD and on_done ~= nil

  --- Progress reporter (throttled to avoid notification spam)
  local progress_last = 0
  local progress_done = 0
  local function report_progress(phase)
    progress_done = progress_done + 1
    local now = vim.uv.now()
    if now - progress_last > 200 then  -- at most every 200ms
      vim.notify(
        string.format("[vault] %s… %d/%d", phase, progress_done, total_ops),
        vim.log.levels.INFO
      )
      progress_last = now
    end
  end

  -- Updates: process dir moves FIRST so subsequent field writes target the new path
  for _, upd in ipairs(diff.updates) do
    local path = st.note_paths[upd.slug]
    if not path then goto continue end

    -- Safety: verify path is inside vault root
    local safe_path, path_err = validate_path_in_vault(path)
    if not safe_path then
      vim.notify("[vault] SAFETY: Skipping update — " .. path_err, vim.log.levels.ERROR)
      goto continue
    end
    path = safe_path

    -- Safety: check file hasn't been modified externally since snapshot
    local snap_mtime = st.note_mtimes and st.note_mtimes[upd.slug] or 0
    if snap_mtime > 0 then
      local current_mtime = get_mtime(path)
      if current_mtime > snap_mtime then
        vim.notify(
          string.format("[vault] SAFETY: Skipping %s — file modified externally since snapshot", upd.slug),
          vim.log.levels.WARN
        )
        goto continue
      end
    end

    -- Phase 1: dir move
    if upd.fields.dir ~= nil then
      local config = require("vault.config")
      local new_dir = upd.fields.dir or ""
      if new_dir == "/" then new_dir = "" end
      -- Safety: reject paths that escape the vault root
      if new_dir:match("%.%.") then
        vim.notify("[vault] SAFETY: Refusing to move note to path with '..': " .. new_dir, vim.log.levels.ERROR)
        goto continue
      end
      local basename = vim.fn.fnamemodify(path, ":t")
      local new_path = config.options.root .. "/" .. new_dir .. basename
      if new_path ~= path then
        local move_ok = pcall(function()
          local Note = require("vault.notes.note")
          local note = Note(path)
          note:move(new_path, false, false, { silent = true })
        end)
        if move_ok then
          st.note_paths[upd.slug] = new_path
          path = new_path
        end
      end
    end

    -- Phase 2: file.body write (replace content after frontmatter)
    if upd.fields["file.body"] ~= nil then
      local new_body = upd.fields["file.body"] or ""
      local ok_read, file_lines = pcall(vim.fn.readfile, path)
      if ok_read and file_lines then
        -- Find end of frontmatter
        local fm_end = 0
        if file_lines[1] and file_lines[1]:match("^%-%-%-") then
          for i = 2, #file_lines do
            if file_lines[i]:match("^%-%-%-") then
              fm_end = i
              break
            end
          end
        end
        -- Rebuild: frontmatter lines + new body
        local new_lines = {}
        for i = 1, fm_end do
          table.insert(new_lines, file_lines[i])
        end
        -- The body was flattened (newlines → spaces), write it back as-is
        -- (user edited a single-line representation)
        table.insert(new_lines, new_body)
        table.insert(new_lines, "")  -- trailing newline
        atomic_writefile(path, new_lines)
      end
    end

    -- Phase 3: all other field writes (batched to minimize I/O)
    local fm_fields = {}
    for col, new_val in pairs(upd.fields) do
      if col ~= "dir" and col ~= "file.body" then
        fm_fields[col] = new_val
      end
    end
    if next(fm_fields) then
      set_frontmatter_fields(path, fm_fields)
    end
    n_updates = n_updates + 1
    if is_async then report_progress("Updating") end
    ::continue::
  end

  -- Deletes
  for _, slug in ipairs(diff.deletes) do
    local path = st.note_paths[slug]
    if path then
      -- Safety: verify path is inside vault root before deleting
      local safe_del, del_err = validate_path_in_vault(path)
      if not safe_del then
        vim.notify("[vault] SAFETY: Skipping delete — " .. del_err, vim.log.levels.ERROR)
        goto del_continue
      end
      pcall(function()
        local Note = require("vault.notes.note")
        local note = Note(safe_del)
        note:delete(false, false)
      end)
      n_deletes = n_deletes + 1
      if is_async then report_progress("Deleting") end
    end
    ::del_continue::
  end

  -- Creates
  for _, create in ipairs(diff.creates) do
    -- Derive filename from slug column first (primary identity), then title, then "untitled"
    local raw_slug = create.fields.slug
    local title = create.fields.title
    local source = raw_slug and raw_slug ~= "" and raw_slug ~= EMPTY_CELL and raw_slug
      or title and title ~= "" and title ~= EMPTY_CELL and title
      or nil
    if not source then goto continue end
    local slug = source:lower():gsub("%s+", "-"):gsub("[%c%[%]#|^]", "")
    if slug == "" then slug = "untitled" end
    local config = require("vault.config")
    local dir = create.fields.dir or ""
    if dir == "/" then dir = "" end
    -- Safety: reject paths that escape the vault root (e.g., "../" in dir)
    if dir:match("%.%.") then
      vim.notify("[vault] SAFETY: Refusing to create note with '..' in path: " .. dir, vim.log.levels.ERROR)
      goto continue
    end
    local base_slug = slug
    local path = config.options.root .. "/" .. dir .. slug .. config.options.ext
    local counter = 1
    while vim.fn.filereadable(path) == 1 do
      slug = base_slug .. "-" .. counter
      path = config.options.root .. "/" .. dir .. slug .. config.options.ext
      counter = counter + 1
      if counter > 100 then
        vim.notify("[vault] Too many slug collisions for: " .. base_slug, vim.log.levels.ERROR)
        goto continue
      end
    end

    -- Safety: validate final path is inside vault
    local safe_create, create_err = validate_path_in_vault(path)
    if not safe_create then
      vim.notify("[vault] SAFETY: Skipping create — " .. create_err, vim.log.levels.ERROR)
      goto continue
    end

    -- Build frontmatter from ALL editable fields (not just title/status/tags)
    local fm = { "---" }
    -- Title first (conventional order)
    if create.fields.title then
      table.insert(fm, "title: " .. yaml_quote(create.fields.title))
    end
    -- All other scalar fields (skip slug, dir, title — handled separately)
    local skip_fields = { slug = true, title = true, dir = true, tags = true }
    for col, val in pairs(create.fields) do
      if not skip_fields[col] and val ~= nil then
        if type(val) == "table" then
          table.insert(fm, col .. ":")
          for _, v in ipairs(val) do
            table.insert(fm, "  - " .. yaml_quote(tostring(v)))
          end
        else
          table.insert(fm, col .. ": " .. yaml_quote(tostring(val)))
        end
      end
    end
    if create.fields.tags and type(create.fields.tags) == "table" then
      table.insert(fm, "tags:")
      for _, t in ipairs(create.fields.tags) do
        table.insert(fm, "  - " .. yaml_quote(t))
      end
    end
    table.insert(fm, "---")
    table.insert(fm, "")

    local parent = vim.fn.fnamemodify(safe_create, ":h")
    if vim.fn.isdirectory(parent) == 0 then
      vim.fn.mkdir(parent, "p")
    end
    local write_ok, write_err = atomic_writefile(safe_create, fm)
    if not write_ok then
      vim.notify("[vault] SAFETY: " .. write_err, vim.log.levels.ERROR)
      goto continue
    end
    -- Track created path for undo
    if st.bufnr and undo_snapshots[st.bufnr] then
      table.insert(undo_snapshots[st.bufnr].created_paths, safe_create)
    end
    n_creates = n_creates + 1
    if is_async then report_progress("Creating") end
    ::continue::
  end

  if on_done then
    on_done(n_updates, n_deletes, n_creates)
  end
  return n_updates, n_deletes, n_creates
end

-- ─── Save handler ─────────────────────────────────────────────────────────────

--- Hard limit: refuse to delete more than this many notes in a single save.
--- Catches catastrophic extmark-loss scenarios that slip past integrity checks.
local DELETE_HARD_CAP = 100

--- Hard limit: refuse to create more than this many notes in a single save.
--- Catches phantom extmark-loss scenarios where existing lines lose identity.
local CREATE_HARD_CAP = 100

--- Apply safe mutations (updates + creates only) and reload.
---@param bufnr integer
---@param st vault.OilEditState
---@param diff vault.OilEditDiff
local function apply_safe_and_reload(bufnr, st, diff)
  -- Also cap creates in the "safe" path — they can be phantom too
  local safe_creates = diff.creates
  if #safe_creates > CREATE_HARD_CAP then
    vim.notify(
      string.format("[vault] SAFETY: Also refusing %d creates (cap %d)", #safe_creates, CREATE_HARD_CAP),
      vim.log.levels.ERROR
    )
    safe_creates = {}
  end
  local safe_diff = { updates = diff.updates, deletes = {}, creates = safe_creates }
  local n_u, _, n_c = apply_mutations(safe_diff, st)
  local msg = string.format("[vault] Applied: %d updated, %d created", n_u, n_c)
  if #diff.deletes > 0 then
    msg = msg .. string.format(" (%d deletes skipped)", #diff.deletes)
  end
  vim.notify(msg, vim.log.levels.INFO)
  vim.schedule(function()
    M.reload(bufnr)
    st.saving = false
  end)
end

---@param bufnr integer
local function on_save(bufnr)
  local st = buf_states[bufnr]
  if not st then
    vim.notify("[vault] Process buffer state lost — please reopen with :Vault process", vim.log.levels.WARN)
    vim.bo[bufnr].modified = false
    return
  end
  if st.saving then return end
  st.saving = true

  local diff = diff_buffer(bufnr, st, true)  -- silent: drift during save is expected

  -- Integrity error — diff_buffer already notified the user
  if diff._integrity_error then
    vim.bo[bufnr].modified = false
    st.saving = false
    return
  end

  -- ── Validation warnings (formula/truncated edits) — show but proceed ──
  if #diff.errors > 0 then
    vim.api.nvim_buf_clear_namespace(bufnr, NS_ERR, 0, -1)
    for _, err in ipairs(diff.errors) do
      -- Place warning highlights on ignored cells
      local line = vim.api.nvim_buf_get_lines(bufnr, err.row, err.row + 1, false)[1] or ""
      local col_byte = 0
      -- When slug_hidden, skip past the concealed slug prefix first
      if st.slug_hidden then
        local first_sep = line:find(SEP_CHAR, 1, true)
        if first_sep then col_byte = first_sep end  -- start after slug\x1f
      end
      local sep_count = 0
      for byte_pos = col_byte + 1, #line do
        if line:sub(byte_pos, byte_pos + #SEP - 1) == SEP then
          sep_count = sep_count + 1
          if sep_count == err.col_idx - 1 then
            col_byte = byte_pos + #SEP - 1
            break
          end
        end
      end
      pcall(vim.api.nvim_buf_set_extmark, bufnr, NS_ERR, err.row, col_byte, {
        end_row = err.row,
        end_col = #line,
        hl_group = "DiagnosticUnderlineWarn",
      })
    end
    vim.notify(
      string.format("[vault] %d edit(s) ignored: %s (line %d)",
        #diff.errors, diff.errors[1].message, diff.errors[1].row + 1),
      vim.log.levels.WARN
    )
  else
    vim.api.nvim_buf_clear_namespace(bufnr, NS_ERR, 0, -1)
  end

  local total = #diff.updates + #diff.deletes + #diff.creates + #diff.renames
  if total == 0 then
    vim.bo[bufnr].modified = false
    st.saving = false
    vim.notify("[vault] No changes", vim.log.levels.INFO)
    return
  end

  -- ── Snapshot for undo (before any mutations) ─────────────────────────────
  snapshot_for_undo(diff, st, bufnr)

  -- ── Hard cap on creates ──────────────────────────────────────────────────
  if #diff.creates > CREATE_HARD_CAP then
    vim.notify(
      string.format(
        "[vault] SAFETY: Refusing to create %d notes (cap is %d). "
          .. "This likely indicates extmark identity loss (lines without extmarks "
          .. "are treated as new notes). Applying updates only. "
          .. "Please close and reopen the process buffer.",
        #diff.creates, CREATE_HARD_CAP
      ),
      vim.log.levels.ERROR
    )
    local updates_only = { updates = diff.updates, deletes = {}, creates = {} }
    local n_u = apply_mutations(updates_only, st)
    vim.notify(string.format("[vault] Applied: %d updated (creates refused)", n_u), vim.log.levels.INFO)
    vim.schedule(function()
      M.reload(bufnr)
      st.saving = false
    end)
    return
  end

  -- ── Confirmation for creates > 5 ───────────────────────────────────────
  if #diff.creates > 5 then
    local choice = vim.fn.confirm(
      string.format(
        "Vault process: About to CREATE %d new notes. This seems unusual.\n\nProceed?",
        #diff.creates
      ),
      "&Yes, create them\n&No, skip creates\n&Cancel (no changes)"
    )
    if choice == 3 or choice == 0 then
      vim.bo[bufnr].modified = true
      st.saving = false
      return
    end
    if choice == 2 then
      diff.creates = {}
    end
  end

  -- ── Safety: if creates ≈ deletes, it's likely extmark identity loss ──────
  -- (lines lost their slug → flagged as "delete original + create new")
  -- However, small numbers (e.g. 1 create + 1 delete) usually mean the user
  -- edited a title, causing the old slug to appear as "deleted" and the new
  -- title as "created". In that case, try to pair them as renames/updates.
  if #diff.creates > 0 and #diff.deletes > 0 then
    -- Try to pair creates with deletes by matching row proximity.
    -- If counts are small (≤5), attempt to convert create+delete pairs into
    -- updates by assigning the deleted slug to the created row's fields.
    if #diff.creates <= 5 and #diff.deletes <= 5 and #diff.creates == #diff.deletes then
      -- Pair them: each "create" is really an edit of the corresponding "delete"
      -- (the extmark drifted, so the slug was lost for that row)
      local n_paired = #diff.creates
      -- Build formula set to filter out read-only columns
      local formula_set = {}
      if st.formula_cols then
        for _, fc in ipairs(st.formula_cols) do formula_set[fc] = true end
      end
      for i, cr in ipairs(diff.creates) do
        local del_slug = diff.deletes[i]
        if del_slug then
          -- Filter out formula columns from the paired update
          local fields = {}
          for k, v in pairs(cr.fields) do
            if not formula_set[k] then fields[k] = v end
          end
          table.insert(diff.updates, { slug = del_slug, fields = fields })
        end
      end
      diff.creates = {}
      diff.deletes = {}
      vim.notify(
        string.format("[vault] Paired %d create+delete as title edits", n_paired),
        vim.log.levels.INFO
      )
    else
      vim.notify(
        string.format(
          "[vault] SAFETY: Found %d creates AND %d deletes — likely extmark identity loss. "
            .. "Applying %d updates only. Please close and reopen the process buffer.",
          #diff.creates, #diff.deletes, #diff.updates
        ),
        vim.log.levels.WARN
      )
      local updates_only = { updates = diff.updates, deletes = {}, creates = {} }
      local n_u = apply_mutations(updates_only, st)
      vim.notify(string.format("[vault] Applied: %d updated", n_u), vim.log.levels.INFO)
      vim.schedule(function()
        M.reload(bufnr)
        st.saving = false
      end)
      return
    end
  end

  -- ── Process renames (slug column edits → file move + wikilink update) ───
  local n_renamed = 0
  local n_patched = 0  -- total wikilink files patched across all renames
  if #diff.renames > 0 then
    local Note = require("vault.notes.note")
    local config = require("vault.config")
    local vault_root = vim.fn.expand(config.options.root)
    for _, ren in ipairs(diff.renames) do
      local old_path = st.note_paths[ren.old_slug]
      if not old_path then goto continue_rename end
      local new_path = vault_root .. "/" .. ren.new_slug .. ".md"
      -- Safety: refuse path escape
      if ren.new_slug:match("%.%.") then
        vim.notify(
          string.format("[vault] SAFETY: Refusing rename '%s' — contains '..'", ren.new_slug),
          vim.log.levels.ERROR
        )
        goto continue_rename
      end
      -- Safety: refuse collision
      if vim.fn.filereadable(new_path) == 1 and old_path ~= new_path then
        vim.notify(
          string.format("[vault] SAFETY: Cannot rename to '%s' — file already exists", ren.new_slug),
          vim.log.levels.ERROR
        )
        goto continue_rename
      end
      -- Execute rename via Note:move (handles wikilink patching).
      -- verbose=false: suppress per-rename notify from note/init.lua.
      -- Watcher notify is also suppressed via the silent flag set below.
      local ok, note = pcall(Note, old_path)
      if ok and note then
        local move_ok, move_result = pcall(note.move, note, new_path, false, false, { silent = true })
        if move_ok then
          n_patched = n_patched + (move_result or 0)
          -- Track rename for undo
          if undo_snapshots[bufnr] then
            table.insert(undo_snapshots[bufnr].renames, {
              old_path = old_path,
              new_path = new_path,
            })
          end
          -- Update state maps
          st.note_paths[ren.new_slug] = new_path
          st.note_paths[ren.old_slug] = nil
          if st.note_mtimes then
            st.note_mtimes[ren.new_slug] = st.note_mtimes[ren.old_slug]
            st.note_mtimes[ren.old_slug] = nil
          end
          n_renamed = n_renamed + 1
        else
          vim.notify(
            string.format("[vault] Failed to rename '%s': %s", ren.old_slug, tostring(move_result)),
            vim.log.levels.ERROR
          )
        end
      else
        vim.notify(
          string.format("[vault] Failed to load note '%s' for rename", ren.old_slug),
          vim.log.levels.ERROR
        )
      end
      ::continue_rename::
    end
  end

  -- ── No deletes: apply immediately ────────────────────────────────────────
  if #diff.deletes == 0 then
    local n_u, _, n_c = apply_mutations(diff, st)
    -- Single consolidated summary notification
    local parts = {}
    if n_renamed > 0 then
      local rename_msg = string.format("%d renamed", n_renamed)
      if n_patched > 0 then rename_msg = rename_msg .. string.format(" (%d files patched)", n_patched) end
      table.insert(parts, rename_msg)
    end
    if n_u      > 0 then table.insert(parts, string.format("%d updated", n_u))        end
    if n_c      > 0 then table.insert(parts, string.format("%d created", n_c))        end
    if #parts == 0 then parts = { "no changes" } end
    vim.notify("[vault] Saved: " .. table.concat(parts, ", "), vim.log.levels.INFO)
    vim.schedule(function()
      M.reload(bufnr)
      st.saving = false
    end)
    return
  end

  -- ── Hard cap on deletes ──────────────────────────────────────────────────
  if #diff.deletes > DELETE_HARD_CAP then
    vim.notify(
      string.format(
        "[vault] SAFETY: Refusing to delete %d notes (cap is %d). "
          .. "This likely indicates a bug. Applying updates/creates only. "
          .. "Please close and reopen the process buffer.",
        #diff.deletes, DELETE_HARD_CAP
      ),
      vim.log.levels.ERROR
    )
    apply_safe_and_reload(bufnr, st, diff)
    return
  end

  -- ── Confirmation prompt for deletes ──────────────────────────────────────
  local preview_slugs = {}
  for i = 1, math.min(10, #diff.deletes) do
    table.insert(preview_slugs, "  - " .. diff.deletes[i])
  end
  if #diff.deletes > 10 then
    table.insert(preview_slugs, string.format("  ... and %d more", #diff.deletes - 10))
  end

  local prompt = string.format(
    "Vault process: About to TRASH %d note%s:\n%s\n\nAlso: %d updated, %d created.\n\nProceed with deletes?",
    #diff.deletes,
    #diff.deletes == 1 and "" or "s",
    table.concat(preview_slugs, "\n"),
    #diff.updates,
    #diff.creates
  )

  local choice = vim.fn.confirm(prompt, "&Yes, trash them\n&No, skip deletes\n&Cancel (no changes)")

  if choice == 1 then
    -- Apply everything including deletes
    local n_u, n_d, n_c = apply_mutations(diff, st)
    vim.notify(
      string.format("[vault] Applied: %d updated, %d trashed, %d created", n_u, n_d, n_c),
      vim.log.levels.INFO
    )
    vim.schedule(function()
      M.reload(bufnr)
      st.saving = false
    end)
  elseif choice == 2 then
    -- Apply updates + creates only, skip deletes
    apply_safe_and_reload(bufnr, st, diff)
  else
    -- Cancel entirely
    vim.notify("[vault] Save cancelled", vim.log.levels.INFO)
    st.saving = false
  end
end

-- ─── Public API ───────────────────────────────────────────────────────────────

--- Open a vault process buffer.
---@param opts? { notes?: vault.Notes, columns?: string[], filter_desc?: string, base?: vault.Base }
function M.open(opts)
  opts = opts or {}

  -- Clear winfixbuf so we can switch buffers (e.g. after Telescope closes)
  local win = vim.api.nvim_get_current_win()
  if vim.wo[win].winfixbuf then
    vim.wo[win].winfixbuf = false
  end

  local base = opts.base
  local display_names = {}
  local formula_cols = {}
  local filter_desc = opts.filter_desc or "all notes"
  local visible_columns  -- what the user wants rendered in the buffer

  -- Determine columns via fallback chain:
  -- 1. opts.columns (inline CLI spec or programmatic)
  -- 2. base file's view order (if base provided)
  -- 3. config.options.process.columns (user setup default)
  -- 4. DEFAULT_COLUMNS (hardcoded fallback)
  local columns
  if base then
    local vis
    columns, display_names, formula_cols, vis = columns_from_base(base)
    visible_columns = opts.columns or vis
    filter_desc = opts.filter_desc or ("base:" .. (base.data.name or "unnamed"))
  else
    local cfg = require("vault.config")
    local cfg_cols = cfg.options and cfg.options.process and cfg.options.process.columns
    visible_columns = opts.columns or cfg_cols or DEFAULT_COLUMNS
    -- Normalize all column names (note.* → file.*, dir → file.folder)
    for i, c in ipairs(visible_columns) do
      visible_columns[i] = normalize_col(c)
    end
    -- Detect read-only file.* columns
    for _, c in ipairs(visible_columns) do
      if READONLY_FILE_COLS[c] then
        table.insert(formula_cols, c)
      end
    end
    -- Internal columns = visible + slug if not already present
    local has_slug = false
    for _, c in ipairs(visible_columns) do
      if c == "slug" then has_slug = true; break end
    end
    columns = vim.list_slice(visible_columns, 1)
    if not has_slug then
      table.insert(columns, 1, "slug")
    end
  end

  -- Prevent duplicate process buffers: if one exists, switch to it
  for bufnr, st in pairs(buf_states) do
    if vim.api.nvim_buf_is_valid(bufnr) then
      if st.filter_desc == filter_desc then
        vim.api.nvim_set_current_buf(bufnr)
        vim.notify("[vault] Switched to existing process buffer (" .. filter_desc .. ")", vim.log.levels.INFO)
        return
      end
    else
      buf_states[bufnr] = nil
    end
  end

  -- Get notes: if base has filters, use them to select matching notes
  local notes
  if opts.notes then
    notes = opts.notes
  else
    notes = require("vault.notes")()
  end

  local notes_map = notes.map or {}
  if base and base:has_filters() then
    notes_map = base:match_notes(notes_map)
  end

  if not next(notes_map) then
    vim.notify("[vault] No notes match" .. (base and (" base '" .. base.data.name .. "'") or ""), vim.log.levels.INFO)
    return
  end

  -- Build records (pass base for formula evaluation)
  local records = build_records(notes_map, columns, base)

  -- Apply sort (from base view or default)
  local initial_sort = base and sort_from_base(base) or nil
  sort_records(records, initial_sort, nil)

  -- Create buffer
  local bufnr = vim.api.nvim_create_buf(true, false)
  local buf_name = "vault://process/" .. filter_desc:gsub("%s+", "-")
  pcall(vim.api.nvim_buf_set_name, bufnr, buf_name)
  vim.bo[bufnr].buftype = "acwrite"
  vim.bo[bufnr].filetype = "vault_process"
  vim.bo[bufnr].swapfile = false

  -- Compute layout: widths for all internal columns (needed for snapshot comparison)
  -- and for visible columns (needed for rendering)
  local col_widths = calc_col_widths(columns, records)
  local visible_col_widths = calc_col_widths(visible_columns, records)

  -- Build state
  -- Determine if slug is hidden (not in user's visible column spec)
  local slug_hidden = true
  for _, c in ipairs(visible_columns) do
    if c == "slug" then slug_hidden = false; break end
  end

  local st = {
    bufnr              = bufnr,
    columns            = columns,            -- ALL columns (always includes slug)
    col_widths         = col_widths,          -- widths for all internal columns
    visible_columns    = visible_columns,     -- columns rendered in the buffer
    visible_col_widths = visible_col_widths,  -- widths for visible columns
    slug_hidden        = slug_hidden,         -- true when slug not in user's column spec
    snapshot           = build_snapshot(records, columns),
    note_paths         = {},
    note_mtimes        = {},
    mark_to_slug       = {},
    slug_to_mark       = {},
    filter_desc        = filter_desc,
    saving             = false,
    base               = base,
    display_names      = display_names,
    formula_cols       = formula_cols,
    sort_by            = initial_sort,
  }
  for _, rec in ipairs(records) do
    st.note_paths[rec.slug] = rec.path
    st.note_mtimes[rec.slug] = get_mtime(rec.path)
  end
  buf_states[bufnr] = st

  -- Render data lines (no header — header is virt_lines)
  local lines = build_data_lines(st, records)
  set_buffer_lines(bufnr, lines)
  vim.bo[bufnr].modifiable = true

  -- Precompute concealed slug prefix virtcol offset for winbar alignment.
  -- Neovim's leftcol is in virtcol space (doesn't account for concealment).
  -- The concealed prefix adds phantom virtual columns that the header must skip.
  if slug_hidden and lines[1] then
    local first_sep = lines[1]:find(SEP_CHAR, 1, true)
    if first_sep then
      -- Prefix = bytes 0..first_sep-1 (slug) + byte first_sep (\x1f)
      -- Use strdisplaywidth to match what virtcol counts
      st._slug_phantom_vcol = vim.fn.strdisplaywidth(lines[1]:sub(1, first_sep))
    end
  end

  -- Open in current window
  vim.api.nvim_set_current_buf(bufnr)
  local winid = vim.api.nvim_get_current_win()
  st.winid = winid
  st._last_line_count = #records

  -- Disable auto-formatters for this buffer.
  -- formatter.nvim checks vim.b.formatter_skip_buf (format.lua:69).
  vim.b[bufnr].formatter_skip_buf  = true   -- formatter.nvim
  vim.b[bufnr].autoformat          = false  -- conform.nvim

  -- Window options
  vim.wo[winid].signcolumn = "yes"
  vim.wo[winid].number = true
  vim.wo[winid].relativenumber = true
  vim.wo[winid].wrap = false
  vim.wo[winid].conceallevel = 2       -- fully conceal \x1f, show │ replacement
  vim.wo[winid].concealcursor = "nvic" -- conceal in normal + visual + insert + command-line mode

  -- Apply extmarks: separator virt_line + slug identity on each data line
  apply_extmarks(bufnr, st, records)

  -- Conceal \x1f separators as │ (and conceal hidden slug prefix when slug_hidden)
  apply_conceal(bufnr, st.slug_hidden)

  -- Highlight formula cells as read-only
  highlight_formula_cells(bufnr, st)

  -- Sticky winbar header (always visible, even when scrolled down)
  set_winbar(winid, st)

  -- BufWriteCmd autocmd
  vim.api.nvim_create_autocmd("BufWriteCmd", {
    buffer = bufnr,
    callback = function() on_save(bufnr) end,
  })

  -- Scroll-sync: update winbar when the buffer scrolls horizontally.
  -- WinScrolled fires on any scroll (vertical or horizontal).
  vim.api.nvim_create_autocmd("WinScrolled", {
    buffer = bufnr,
    callback = function()
      local s = buf_states[bufnr]
      if s and s.winid and vim.api.nvim_win_is_valid(s.winid) then
        set_winbar(s.winid, s)
      end
    end,
  })

  -- Live diff signs + inline validation on TextChanged
  -- Also refresh conceal extmarks on changed lines
  vim.api.nvim_create_autocmd({ "TextChanged", "InsertLeave" }, {
    buffer = bufnr,
    callback = function()
      local ok, err = pcall(function()
        local s = buf_states[bufnr]
        if s and not s.saving then
          -- Conceal refresh strategy:
          --   Insert mode → current line only (fast, no lag during typing)
          --   Normal mode (TextChanged/InsertLeave) → full refresh (catches all drift)
          -- With right_gravity=false, in-place edits only destroy extmarks on
          -- the current line; other lines stay stable.
          -- Full conceal + diff + validation refresh (only fires in normal mode
          -- via TextChanged/InsertLeave — no lag during insert-mode typing)
          apply_conceal(bufnr, s.slug_hidden)
          update_diff_signs(bufnr, s)
          update_validation(bufnr, s)
        end
      end)
      if not ok then
        local f = io.open("/tmp/nvim_notify.txt", "a")
        if f then f:write(os.date() .. " [TextChanged err] " .. tostring(err) .. "\n"); f:close() end
      end
    end,
  })

  -- NOTE: We intentionally do NOT sanitize \x1f in yank registers.
  -- The \x1f chars are concealed as │ in the buffer. Sanitizing would break
  -- internal paste (yyp) because the pasted line would have real │ (3 bytes)
  -- instead of \x1f (1 byte), breaking split_cells and conceal.

  -- Cursor skip: prevent cursor from landing on \x1f byte or in concealed slug prefix
  -- Track previous cursor position for direction detection
  local prev_cursor = { 1, 0 }
  vim.api.nvim_create_autocmd({ "CursorMoved" }, {
    buffer = bufnr,
    callback = function()
      local ok, err = pcall(function()
        local s = buf_states[bufnr]
        if not s then return end
        local row, col = unpack(vim.api.nvim_win_get_cursor(0))
        local line = vim.api.nvim_get_current_line()

        -- When slug is hidden, snap cursor past the concealed slug prefix.
        -- The prefix is everything before (and including) the first \x1f.
        if s.slug_hidden then
          local first_sep = line:find(SEP_CHAR, 1, true)
          if first_sep and col <= first_sep then
            -- Cursor is inside the hidden slug prefix (or on the \x1f) — snap to
            -- first visible column (byte AFTER the \x1f separator).
            vim.api.nvim_win_set_cursor(0, { row, first_sep })
            -- Also align the viewport so the first visible column is at screen col 0.
            -- Without this, Neovim positions the cursor at the rightmost visible
            -- column (virtcol ~254 with leftcol=70), hiding the column data.
            if s._slug_phantom_vcol then
              local v = vim.fn.winsaveview()
              v.leftcol = s._slug_phantom_vcol  -- scroll right past the phantom prefix
              vim.fn.winrestview(v)
            end
            prev_cursor = { row, first_sep }
            return
          end
        end

        if col < #line and line:byte(col + 1) == 0x1f then
          -- Determine movement direction to skip the right way
          local prev_row, prev_col = prev_cursor[1], prev_cursor[2]
          local moving_left = (row == prev_row and col < prev_col)
              or (row < prev_row)
          if moving_left and col > 0 then
            vim.api.nvim_win_set_cursor(0, { row, col - 1 })
          else
            vim.api.nvim_win_set_cursor(0, { row, col + 1 })
          end
        end
        prev_cursor = { row, col }

        -- Update winbar to sync header with new leftcol after cursor movement.
        -- WinScrolled handles scroll events but misses cursor-driven leftcol changes.
        if s.winid and vim.api.nvim_win_is_valid(s.winid) then
          set_winbar(s.winid, s)
        end
      end)
    end,
  })

  -- Allow :q without "no write" error when there are no real changes
  -- Also allow quit if state is lost (nothing to save anyway)
  vim.api.nvim_create_autocmd("QuitPre", {
    buffer = bufnr,
    callback = function()
      local s = buf_states[bufnr]
      if not s then
        vim.bo[bufnr].modified = false
        return
      end
      local d = diff_buffer(bufnr, s, true)  -- silent: quit check, no need to surface drift
      if d._integrity_error or (#d.updates == 0 and #d.deletes == 0 and #d.creates == 0) then
        vim.bo[bufnr].modified = false
      end
    end,
  })

  -- Cleanup on buffer delete
  vim.api.nvim_create_autocmd("BufDelete", {
    buffer = bufnr,
    callback = function() buf_states[bufnr] = nil end,
  })

  -- Buffer-local keymaps
  local kopts = { buffer = bufnr, silent = true }
  vim.keymap.set("n", "gs", function() M.sort_by_cursor(bufnr) end,
    vim.tbl_extend("force", kopts, { desc = "Vault: cycle sort on column" }))
  vim.keymap.set("n", "gS", function()
    local cn = col_under_cursor(bufnr)
    if cn then M.cycle_sort(bufnr, cn, true) end
  end, vim.tbl_extend("force", kopts, { desc = "Vault: add secondary sort on column" }))
  vim.keymap.set("n", "gR", function() M.reload(bufnr) end,
    vim.tbl_extend("force", kopts, { desc = "Vault: reload buffer" }))
  vim.keymap.set("n", "gu", function() M.undo(bufnr) end,
    vim.tbl_extend("force", kopts, { desc = "Vault: undo last save" }))
  vim.keymap.set("n", "u", function()
    -- Smart undo: vim undo if entries exist, otherwise plugin undo (gu)
    -- Note: seq_cur stays non-zero after buffer re-render (undolevels=-1),
    -- but entries is emptied. So check entries, not seq_cur.
    local tree = vim.fn.undotree()
    if #tree.entries > 0 then
      vim.cmd("undo")
      -- Schedule conceal refresh after undo — must be deferred so
      -- Neovim finishes processing the undo before we re-apply extmarks.
      vim.schedule(function()
        local s = buf_states[bufnr]
        if s then
          local view = vim.fn.winsaveview()
          apply_conceal(bufnr, s.slug_hidden)
          update_diff_signs(bufnr, s)
          vim.fn.winrestview(view)
        end
      end)
    elseif undo_snapshots[bufnr] then
      M.undo(bufnr)
    else
      vim.notify("[vault] Nothing to undo", vim.log.levels.INFO)
    end
  end, vim.tbl_extend("force", kopts, { desc = "Vault: smart undo" }))
  vim.keymap.set("n", "J", function()
    -- Merge: absorb next line's note into current line's note
    local st = buf_states[bufnr]
    if not st then return end
    local row = vim.api.nvim_win_get_cursor(0)[1] - 1  -- 0-indexed
    local line_count = vim.api.nvim_buf_line_count(bufnr)
    if row + 1 >= line_count then
      vim.notify("[vault] No next line to merge with", vim.log.levels.WARN)
      return
    end
    local slug_a = get_row_slug(bufnr, row, st)
    local slug_b = get_row_slug(bufnr, row + 1, st)
    if not slug_a or not slug_b then
      vim.notify("[vault] Cannot determine note identity for merge", vim.log.levels.WARN)
      return
    end
    local path_a = st.note_paths[slug_a]
    local path_b = st.note_paths[slug_b]
    if not path_a or not path_b then
      vim.notify("[vault] Cannot find note paths for merge", vim.log.levels.WARN)
      return
    end
    require("vault.merge").merge(path_a, path_b, {
      bufnr = bufnr,
      on_done = function()
        M.reload(bufnr)
      end,
    })
  end, vim.tbl_extend("force", kopts, { desc = "Vault: merge next note into current" }))
  vim.keymap.set("n", "gJ", function()
    -- Merge: pick any note as target via telescope, absorb it into current line's note
    local st = buf_states[bufnr]
    if not st then return end
    local row = vim.api.nvim_win_get_cursor(0)[1] - 1  -- 0-indexed
    local slug_a = get_row_slug(bufnr, row, st)
    if not slug_a then
      vim.notify("[vault] Cannot determine note identity on current line", vim.log.levels.WARN)
      return
    end
    local path_a = st.note_paths[slug_a]
    if not path_a then
      vim.notify("[vault] Cannot find path for current note", vim.log.levels.WARN)
      return
    end

    -- Score candidates using Rust engine + optional cluster proximity
    local scoring = require("vault.scoring")

    -- Extract current note's tags from snapshot
    local snap_a = st.snapshot and st.snapshot[slug_a]
    local tags_a = {}
    if snap_a and snap_a.tags then
      if type(snap_a.tags) == "table" then
        tags_a = snap_a.tags
      elseif type(snap_a.tags) == "string" and snap_a.tags ~= "" and snap_a.tags ~= EMPTY_CELL then
        tags_a = vim.split(snap_a.tags, ",")
        for i, t in ipairs(tags_a) do tags_a[i] = vim.trim(t) end
      end
    end

    -- Build candidate list with tags
    local candidates = {}
    for slug, path in pairs(st.note_paths) do
      if slug ~= slug_a then
        local snap = st.snapshot and st.snapshot[slug]
        local tags = {}
        if snap and snap.tags then
          if type(snap.tags) == "table" then
            tags = snap.tags
          elseif type(snap.tags) == "string" and snap.tags ~= "" and snap.tags ~= EMPTY_CELL then
            tags = vim.split(snap.tags, ",")
            for i, t in ipairs(tags) do tags[i] = vim.trim(t) end
          end
        end
        table.insert(candidates, { slug = slug, path = path, tags = tags })
      end
    end

    -- Score and rank
    local scored = scoring.score_merge_candidates(slug_a, tags_a, candidates, { limit = 200 })

    -- Open telescope with ranked results
    local ok_tele, _ = pcall(function()
      local actions      = require("telescope.actions")
      local action_state = require("telescope.actions.state")
      local finders      = require("telescope.finders")
      local pickers      = require("telescope.pickers")
      local sorters      = require("telescope.sorters")
      local conf         = require("telescope.config").values

      pickers.new({}, {
        prompt_title = string.format("Merge into: %s ← ?", slug_a),
        finder = finders.new_table({
          results = scored,
          entry_maker = function(e)
            local pct = math.floor(e.score * 100 + 0.5)
            local display_str = pct > 0
              and string.format("%s (%d%%)", e.slug, pct)
              or e.slug
            return {
              value    = e,
              display  = display_str,
              ordinal  = e.slug,
              path     = e.path,
              filename = e.path,
            }
          end,
        }),
        sorter    = sorters.get_fuzzy_file(),
        previewer = conf.file_previewer({}),
        attach_mappings = function(prompt_bufnr, map)
          actions.select_default:replace(function()
            actions.close(prompt_bufnr)
            local sel = action_state.get_selected_entry()
            if not sel then return end
            local path_b = sel.value.path
            require("vault.merge").merge(path_a, path_b, {
              bufnr   = bufnr,
              on_done = function() M.reload(bufnr) end,
            })
          end)
          return true
        end,
      }):find()
    end)
    if not ok_tele then
      vim.notify("[vault] gJ requires telescope.nvim: " .. tostring(_), vim.log.levels.WARN)
    end
  end, vim.tbl_extend("force", kopts, { desc = "Vault: pick any note to merge into current" }))
  vim.keymap.set("n", "g>", function() M.resize_cursor_column(bufnr, 5) end,
    vim.tbl_extend("force", kopts, { desc = "Vault: widen column" }))
  vim.keymap.set("n", "g<", function() M.resize_cursor_column(bufnr, -5) end,
    vim.tbl_extend("force", kopts, { desc = "Vault: narrow column" }))
  vim.keymap.set("n", "g}", function() M.move_cursor_column(bufnr, 1) end,
    vim.tbl_extend("force", kopts, { desc = "Vault: move column right" }))
  vim.keymap.set("n", "g{", function() M.move_cursor_column(bufnr, -1) end,
    vim.tbl_extend("force", kopts, { desc = "Vault: move column left" }))
  -- Partial save: visual select rows, then :w saves only those
  vim.keymap.set("v", "<C-s>", function()
    local start_row = vim.fn.line("'<") - 1
    local end_row = vim.fn.line("'>") - 1
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "n", false)
    M.save_range(bufnr, start_row, end_row)
  end, vim.tbl_extend("force", kopts, { desc = "Vault: save selected rows only" }))

  local sort_desc = st.sort_by
    and string.format(", sorted by %s %s", st.sort_by.col, st.sort_by.dir)
    or ""
  vim.notify(
    string.format(
      "[vault] Processing %d notes (%s)%s — :w to apply, gs/gS to sort, gu to undo, g>/g< to resize",
      #records, filter_desc, sort_desc
    ),
    vim.log.levels.INFO
  )
end

--- Reload an existing process buffer with fresh data.
---@param bufnr integer
function M.reload(bufnr)
  local st = buf_states[bufnr]
  if not st then return end

  -- Build a notes_map (slug → Note) from st.note_paths so we can reuse
  -- build_records() for all column types (including file.* and formulas).
  local Note = require("vault.notes.note")
  local notes_map = {}
  local dead_slugs = {}
  for slug, path in pairs(st.note_paths) do
    if vim.fn.filereadable(path) == 1 then
      local ok, note = pcall(Note, path)
      if ok and note then
        notes_map[slug] = note
      end
    else
      table.insert(dead_slugs, slug)
    end
  end
  for _, slug in ipairs(dead_slugs) do
    st.note_paths[slug] = nil
    if st.note_mtimes then st.note_mtimes[slug] = nil end
  end

  -- Re-scan using the shared build_records() so all file.* columns are handled.
  local records = build_records(notes_map, st.columns, st.base)
  sort_records(records, st.sort_by, st.sort_keys)

  -- Recompute + refresh mtimes
  st.col_widths = calc_col_widths(st.columns, records)
  st.visible_col_widths = calc_col_widths(st.visible_columns or st.columns, records)
  st.snapshot = build_snapshot(records, st.columns)
  st.note_mtimes = {}
  for _, rec in ipairs(records) do
    st.note_mtimes[rec.slug] = get_mtime(rec.path)
  end

  local lines = build_data_lines(st, records)
  set_buffer_lines(bufnr, lines)
  vim.bo[bufnr].modifiable = true
  apply_extmarks(bufnr, st, records)
  apply_conceal(bufnr, st.slug_hidden)
  highlight_formula_cells(bufnr, st)
  vim.api.nvim_buf_clear_namespace(bufnr, NS_DIFF, 0, -1)
  vim.api.nvim_buf_clear_namespace(bufnr, NS_VALID, 0, -1)
  vim.bo[bufnr].modified = false

  -- Refresh winbar (col_widths or sort indicator may have changed)
  if st.winid and vim.api.nvim_win_is_valid(st.winid) then
    set_winbar(st.winid, st)
  end
end

--- Cycle sort on a column: none → asc → desc → none.
--- Re-renders the buffer with the new sort order.
---@param bufnr integer
---@param col_name string  column to sort by
---@param add_secondary? boolean  if true, add as secondary sort key instead of replacing
function M.cycle_sort(bufnr, col_name, add_secondary)
  local st = buf_states[bufnr]
  if not st then return end

  if add_secondary then
    -- Multi-column sort: add/cycle this column in sort_keys
    st.sort_keys = st.sort_keys or {}
    if st.sort_by and #st.sort_keys == 0 then
      -- Migrate single sort_by to sort_keys
      table.insert(st.sort_keys, vim.deepcopy(st.sort_by))
    end
    -- Find if this column is already in sort_keys
    local found_idx = nil
    for i, sk in ipairs(st.sort_keys) do
      if sk.col == col_name then found_idx = i; break end
    end
    if found_idx then
      if st.sort_keys[found_idx].dir == "asc" then
        st.sort_keys[found_idx].dir = "desc"
      else
        table.remove(st.sort_keys, found_idx)
      end
    else
      table.insert(st.sort_keys, { col = col_name, dir = "asc" })
    end
    -- Keep sort_by in sync with first key
    st.sort_by = st.sort_keys[1] or nil
  else
    -- Single-column sort (legacy behavior)
    local current = st.sort_by
    if current and current.col == col_name then
      if current.dir == "asc" then
        st.sort_by = { col = col_name, dir = "desc" }
      else
        st.sort_by = nil
      end
    else
      st.sort_by = { col = col_name, dir = "asc" }
    end
    st.sort_keys = nil  -- clear multi-sort
  end

  M.reload(bufnr)

  -- Build sort description
  local desc
  if st.sort_keys and #st.sort_keys > 0 then
    local parts = {}
    for _, sk in ipairs(st.sort_keys) do
      table.insert(parts, sk.col .. " " .. sk.dir)
    end
    desc = table.concat(parts, ", ")
  elseif st.sort_by then
    desc = st.sort_by.col .. " " .. st.sort_by.dir
  else
    desc = "default"
  end
  vim.notify("[vault] Sort: " .. desc, vim.log.levels.INFO)
end

--- Get the column name under the cursor.
---@param bufnr integer
---@return string|nil col_name
local function col_under_cursor(bufnr)
  local st = buf_states[bufnr]
  if not st then return nil end

  local vis_cols = st.visible_columns or st.columns
  local vis_widths = st.visible_col_widths or st.col_widths
  local col = vim.fn.virtcol(".")
  local offset = 0
  for i, w in ipairs(vis_widths) do
    local sep_width = (i > 1) and SEP_DISPLAY_WIDTH or 0
    if col <= offset + w + sep_width then
      return vis_cols[i]
    end
    offset = offset + w + sep_width
  end
  return vis_cols[#vis_cols]
end

--- Sort by the column under the cursor (interactive keybind).
---@param bufnr? integer  defaults to current buffer
function M.sort_by_cursor(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local col_name = col_under_cursor(bufnr)
  if col_name then
    M.cycle_sort(bufnr, col_name)
  end
end

--- Undo the last save operation by restoring snapshotted files.
--- Reverses renames, deletes created files, and restores wikilink-patched files.
---@param bufnr? integer  defaults to current buffer
function M.undo(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local snap = undo_snapshots[bufnr]
  if not snap then
    vim.notify("[vault] No undo snapshot available for this buffer", vim.log.levels.WARN)
    return
  end

  local uv = vim.uv or vim.loop
  local restored = 0
  local deleted = 0
  local renames_reversed = 0

  -- 1. Reverse renames FIRST (move files back to old path before restoring content)
  if snap.renames then
    for _, ren in ipairs(snap.renames) do
      if vim.fn.filereadable(ren.new_path) == 1 then
        local ok, err = uv.fs_rename(ren.new_path, ren.old_path)
        if ok then
          renames_reversed = renames_reversed + 1
        else
          vim.notify(
            string.format("[vault] Failed to reverse rename %s → %s: %s", ren.new_path, ren.old_path, tostring(err)),
            vim.log.levels.ERROR
          )
        end
      end
    end
  end

  -- 2. Restore modified/deleted/wikilink-patched files
  for path, original_lines in pairs(snap.files) do
    local ok, err = atomic_writefile(path, original_lines)
    if ok then
      restored = restored + 1
    else
      vim.notify("[vault] Failed to restore " .. path .. ": " .. (err or "unknown"), vim.log.levels.ERROR)
    end
  end

  -- 3. Delete files that were created
  if snap.created_paths then
    for _, path in ipairs(snap.created_paths) do
      if vim.fn.filereadable(path) == 1 then
        vim.fn.delete(path)
        deleted = deleted + 1
      end
    end
  end

  undo_snapshots[bufnr] = nil

  local parts = {}
  if restored > 0 then table.insert(parts, string.format("restored %d file(s)", restored)) end
  if deleted > 0 then table.insert(parts, string.format("removed %d created", deleted)) end
  if renames_reversed > 0 then table.insert(parts, string.format("reversed %d rename(s)", renames_reversed)) end
  vim.notify(
    "[vault] Undo: " .. (#parts > 0 and table.concat(parts, ", ") or "nothing to undo"),
    vim.log.levels.INFO
  )

  -- Reload the buffer to reflect the reverted state
  M.reload(bufnr)
end

--- Partial save: save only changes on lines within the given row range.
--- Useful with visual selection — only mutations for selected rows are applied.
---@param bufnr integer
---@param start_row integer  0-indexed inclusive
---@param end_row integer    0-indexed inclusive
function M.save_range(bufnr, start_row, end_row)
  local st = buf_states[bufnr]
  if not st then
    vim.notify("[vault] Process buffer state lost", vim.log.levels.WARN)
    return
  end
  if st.saving then return end
  st.saving = true

  local diff = diff_buffer(bufnr, st, true)
  if diff._integrity_error then
    st.saving = false
    return
  end

  -- Filter updates to only include slugs on rows within range
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local row_to_slug = reconcile_extmarks(bufnr, st, lines)
  local selected_slugs = {}
  for row = start_row, end_row do
    if row_to_slug[row] then
      selected_slugs[row_to_slug[row]] = true
    end
  end

  -- Filter diff to selected rows only
  local filtered_updates = {}
  for _, upd in ipairs(diff.updates) do
    if selected_slugs[upd.slug] then
      table.insert(filtered_updates, upd)
    end
  end

  if #filtered_updates == 0 then
    vim.notify("[vault] No changes in selected range", vim.log.levels.INFO)
    st.saving = false
    return
  end

  local partial_diff = { updates = filtered_updates, deletes = {}, creates = {} }
  snapshot_for_undo(partial_diff, st, bufnr)
  local n_u = apply_mutations(partial_diff, st)
  vim.notify(string.format("[vault] Partial save: %d updated", n_u), vim.log.levels.INFO)

  vim.schedule(function()
    M.reload(bufnr)
    st.saving = false
  end)
end

--- Resize a column interactively.
---@param bufnr integer
---@param col_name string
---@param delta integer  positive = wider, negative = narrower
function M.resize_column(bufnr, col_name, delta)
  local st = buf_states[bufnr]
  if not st then return end

  -- Resize in visible columns (what the user sees)
  local vis_cols = st.visible_columns or st.columns
  local vis_widths = st.visible_col_widths or st.col_widths
  for i, col in ipairs(vis_cols) do
    if col == col_name then
      vis_widths[i] = math.max(4, vis_widths[i] + delta)
      break
    end
  end
  -- Also update internal widths if the column is there
  for i, col in ipairs(st.columns) do
    if col == col_name then
      st.col_widths[i] = math.max(4, st.col_widths[i] + delta)
      break
    end
  end

  -- Re-render with new widths (preserving data — just reformatting)
  M.reload(bufnr)
end

--- Resize the column under the cursor.
---@param bufnr? integer
---@param delta integer
function M.resize_cursor_column(bufnr, delta)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local col_name = col_under_cursor(bufnr)
  if col_name then
    M.resize_column(bufnr, col_name, delta)
  end
end

--- Reorder columns: move a column left or right.
---@param bufnr integer
---@param col_name string
---@param direction integer  -1 = left, +1 = right
function M.move_column(bufnr, col_name, direction)
  local st = buf_states[bufnr]
  if not st then return end

  -- Move in visible columns (what the user sees)
  local vis_cols = st.visible_columns or st.columns
  local vis_widths = st.visible_col_widths or st.col_widths
  local idx = nil
  for i, col in ipairs(vis_cols) do
    if col == col_name then idx = i; break end
  end
  if not idx then return end

  local new_idx = idx + direction
  if new_idx < 1 or new_idx > #vis_cols then return end

  -- Swap in visible columns and widths
  vis_cols[idx], vis_cols[new_idx] = vis_cols[new_idx], vis_cols[idx]
  vis_widths[idx], vis_widths[new_idx] = vis_widths[new_idx], vis_widths[idx]

  M.reload(bufnr)
end

--- Move column under cursor left or right.
---@param bufnr? integer
---@param direction integer  -1 = left, +1 = right
function M.move_cursor_column(bufnr, direction)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local col_name = col_under_cursor(bufnr)
  if col_name then
    M.move_column(bufnr, col_name, direction)
  end
end

--- Debug: expose buf_states and diff_buffer for testing
M._buf_states = buf_states
M._diff_buffer = diff_buffer
M._undo_snapshots = undo_snapshots

return M
