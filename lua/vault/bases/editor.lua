-- lua/vault/bases/editor.lua
-- Obsidian Bases-style editable buffer for vault note metadata.
--
-- Architecture:
--   1. Each data line is pure visible text: "title │ status │ #tags │ dir/"
--   2. Slug identity is stored as extmark metadata (not in buffer text).
--   3. buftype=acwrite so :w fires BufWriteCmd instead of touching disk.
--   4. On BufWriteCmd: diff buffer lines against snapshot → mutations.
--   5. Mutations rewrite YAML frontmatter, move/rename, delete, or create.
--   6. After mutations complete, re-scan and re-render.
--
-- Extmark design:
--   NS namespace — one extmark per data line at col 0, right_gravity=false.
--   State maps extmark_id → slug and slug → extmark_id.
--   Lines without a slug extmark → new note (CREATE).
--   Slugs in snapshot whose extmark is gone → note trashed (DELETE).
--   Header/separator rendered as virt_lines above row 0 (immutable).

local M = {}

-- ─── Constants ────────────────────────────────────────────────────────────────

local SEP        = " │ "
local EMPTY_CELL = "∅"
local NS         = vim.api.nvim_create_namespace("vault_bases_editor")
local NS_DIFF    = vim.api.nvim_create_namespace("vault_oil_diff")

-- ─── Per-buffer state ─────────────────────────────────────────────────────────

---@class vault.OilEditState
---@field bufnr         integer
---@field winid         integer
---@field columns       string[]         ordered column names
---@field col_widths    integer[]        display width per column
---@field snapshot      table<string, table<string, string>>  slug → {col → value}
---@field note_paths    table<string, string>  slug → absolute path
---@field mark_to_slug  table<integer, string>  extmark_id → slug
---@field slug_to_mark  table<string, integer>  slug → extmark_id
---@field note_mtimes   table<string, integer>  slug → mtime at snapshot time
---@field filter_desc   string           human description of the filter used
---@field saving        boolean
---@field base?         vault.Base       the Base object (if opened via base)
---@field display_names table<string, string>  col → header display name
---@field formula_cols  string[]         formula column names (read-only)

local buf_states = {}  -- [bufnr] = vault.OilEditState

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

local DEFAULT_COLUMNS = { "title", "status", "tags", "dir" }

-- ─── Base property key mapping ────────────────────────────────────────────────

--- Map a base property key (e.g. "file.name") to the internal column name
--- used by the editor. Returns the internal name and whether the column is
--- a formula (computed, read-only).
---@param key string  Base property key like "file.name", "formula.x", "tags"
---@return string col_name  Internal column name for build_records
---@return boolean is_formula
local function base_key_to_col(key)
  if key == "file.name" then return "title", false end
  if key == "file.folder" then return "dir", false end
  if key:match("^formula%.") then return key, true end
  -- Everything else maps directly (e.g. "status", "tags", "priority", etc.)
  return key, false
end

--- Extract columns and display names from a Base object.
--- Uses the first view's order if available, otherwise properties keys.
---@param base vault.Base
---@return string[] columns  Internal column names
---@return table<string, string> display_names  col → display name
---@return string[] formula_cols  List of formula column names (read-only)
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
    return DEFAULT_COLUMNS, {}, {}
  end

  -- Get display name map from base
  local base_display = base:display_names()

  local seen = {}
  for _, key in ipairs(order) do
    local col, is_formula = base_key_to_col(key)
    if not seen[col] then
      seen[col] = true
      table.insert(columns, col)
      display_names[col] = base_display[key] or col
      if is_formula then
        table.insert(formula_cols, col)
      end
    end
  end

  return columns, display_names, formula_cols
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
  local uis = vim.api.nvim_list_uis()
  local win_width = (uis[1] and uis[1].width) or 120
  win_width = math.max(80, math.floor(win_width * 0.95)) - 2
  local sep_total = (#columns - 1) * #SEP
  local content_width = win_width - sep_total

  local natural = {}
  for i, col in ipairs(columns) do
    local w = vim.fn.strdisplaywidth(col)
    local sample = math.min(200, #records)
    for j = 1, sample do
      local cell = fmt_value(records[j].fields[col], col)
      w = math.max(w, vim.fn.strdisplaywidth(cell))
    end
    natural[i] = math.max(w, 8)
  end

  local total = 0
  for _, w in ipairs(natural) do total = total + w end
  if total <= content_width then
    local surplus = content_width - total
    local widths = {}
    for i, w in ipairs(natural) do
      widths[i] = w + math.floor(surplus * (w / total))
    end
    local used = 0
    for _, w in ipairs(widths) do used = used + w end
    widths[1] = widths[1] + (content_width - used)
    return widths
  end
  return natural
end

-- ─── String helpers ───────────────────────────────────────────────────────────

---@param s string
---@param width integer
---@return string
local function pad(s, width)
  local dw = vim.fn.strdisplaywidth(s)
  if dw >= width then
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
  local raw = vim.split(text, "│", { plain = true })
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

--- Place a slug identity extmark on a data row.
---@param bufnr integer
---@param row integer  0-indexed
---@param slug string
---@param st vault.OilEditState
---@return integer mark_id
local function set_line_slug(bufnr, row, slug, st)
  local mark_id = vim.api.nvim_buf_set_extmark(bufnr, NS, row, 0, {
    right_gravity = false,
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

--- Build a reconciled slug-per-row map that corrects for extmark drift.
--- Returns a table { [row] = slug } where each slug is verified or
--- content-matched, plus metadata about the reconciliation.
---@param bufnr integer
---@param st vault.OilEditState
---@param lines string[]  buffer lines (already read)
---@return table<integer, string|nil>  row → slug (nil = genuinely new line)
---@return integer drift_count  number of rows where extmark was wrong
---@return integer reconciled_count  number of drifted rows successfully fixed
local function reconcile_extmarks(bufnr, st, lines)
  local title_col_idx = nil
  for i, col in ipairs(st.columns) do
    if col == "title" then title_col_idx = i; break end
  end

  -- Build reverse lookup: snapshot title → slug (for content matching)
  -- Only used when extmark drift is detected.
  local title_to_slugs = {}  -- title_text → list of slugs (handle duplicates)
  if title_col_idx then
    for slug, snap in pairs(st.snapshot) do
      local title_rendered = vim.trim(pad(fmt_value(snap.title), st.col_widths[title_col_idx]))
      if not title_to_slugs[title_rendered] then
        title_to_slugs[title_rendered] = {}
      end
      table.insert(title_to_slugs[title_rendered], slug)
    end
  end

  local row_to_slug = {}      -- final reconciled map
  local drift_count = 0
  local reconciled_count = 0
  local claimed_slugs = {}    -- slugs already assigned to a row (prevent duplicates)
  local line_count = #lines

  for row = 0, line_count - 1 do
    local line = lines[row + 1]
    if vim.trim(line) == "" then goto continue end

    local extmark_slug = get_line_slug(bufnr, row, st)
    local cells = split_cells(line)

    if extmark_slug and st.snapshot[extmark_slug] then
      -- Extmark claims this row is `extmark_slug`. Verify via title.
      if title_col_idx then
        local expected_title = vim.trim(pad(
          fmt_value(st.snapshot[extmark_slug].title),
          st.col_widths[title_col_idx]
        ))
        local actual_title = cells[title_col_idx] or ""

        if expected_title == actual_title then
          -- Extmark is correct — use it
          row_to_slug[row] = extmark_slug
          claimed_slugs[extmark_slug] = true
        else
          -- DRIFT DETECTED: extmark says one slug but title says another.
          drift_count = drift_count + 1
          -- Try content-based reconciliation: look up by title
          local candidates = title_to_slugs[actual_title]
          if candidates then
            -- Find a candidate that hasn't been claimed yet
            local matched = false
            for _, cand_slug in ipairs(candidates) do
              if not claimed_slugs[cand_slug] then
                row_to_slug[row] = cand_slug
                claimed_slugs[cand_slug] = true
                reconciled_count = reconciled_count + 1
                matched = true
                break
              end
            end
            if not matched then
              -- All candidates claimed — treat as drifted but unresolvable
              -- Still use extmark slug as fallback (better than nil)
              row_to_slug[row] = extmark_slug
              claimed_slugs[extmark_slug] = true
            end
          else
            -- Title was edited AND extmark drifted — can't distinguish
            -- which note this was. Use extmark slug as best guess but
            -- flag the drift so we can warn.
            row_to_slug[row] = extmark_slug
            claimed_slugs[extmark_slug] = true
          end
        end
      else
        -- No title column — can't verify, trust the extmark
        row_to_slug[row] = extmark_slug
        claimed_slugs[extmark_slug] = true
      end
    elseif extmark_slug then
      -- Extmark points to a slug not in snapshot (shouldn't happen normally)
      -- Treat as a new line
      row_to_slug[row] = nil
    else
      -- No extmark at all. Try content-based recovery.
      if title_col_idx then
        local actual_title = cells[title_col_idx] or ""
        local candidates = title_to_slugs[actual_title]
        if candidates then
          for _, cand_slug in ipairs(candidates) do
            if not claimed_slugs[cand_slug] then
              row_to_slug[row] = cand_slug
              claimed_slugs[cand_slug] = true
              reconciled_count = reconciled_count + 1
              drift_count = drift_count + 1  -- extmark was missing entirely
              break
            end
          end
        end
        -- If no candidate found, row_to_slug[row] stays nil → new note
      end
    end

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
        if col == "title" then
          fields.title = fm.title or (note.data and note.data.stem) or slug
        elseif col == "dir" then
          local relpath = note.data and note.data.relpath or ""
          local dir = relpath:match("^(.-/)[^/]*$") or ""
          fields.dir = dir ~= "" and dir or "/"
        elseif col == "tags" then
          fields.tags = fm.tags or (note.data and note.data.frontmatter and note.data.frontmatter.tags) or nil
        elseif col:match("^formula%.") then
          -- Formula column: use precomputed result
          local formula_name = col:match("^formula%.(.+)")
          fields[col] = formula_results[formula_name]
        else
          -- Generic frontmatter key
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
---@param columns string[]
---@param widths integer[]
---@return string
local function render_record_line(rec, columns, widths)
  local cells = {}
  for i, col in ipairs(columns) do
    local cell = fmt_value(rec.fields[col], col)
    table.insert(cells, pad(cell, widths[i]))
  end
  return table.concat(cells, SEP)
end

--- Build the header virt_lines chunks for display above row 0.
---@param st vault.OilEditState
---@return table[] virt_lines  list of {chunks} for nvim_buf_set_extmark virt_lines
local function build_header_virt_lines(st)
  -- Header row (use display names if available)
  local hcells = {}
  for i, col in ipairs(st.columns) do
    local label = (st.display_names and st.display_names[col]) or col
    table.insert(hcells, pad(label, st.col_widths[i]))
  end
  local header_text = table.concat(hcells, SEP)

  -- Separator row
  local sep_parts = {}
  for i, _ in ipairs(st.columns) do
    table.insert(sep_parts, string.rep("─", st.col_widths[i]))
  end
  local sep_text = table.concat(sep_parts, "─┼─")

  return {
    { { header_text, "Visual" } },
    { { sep_text, "Visual" } },
  }
end

--- Build data lines (no header — header is virtual).
---@param st vault.OilEditState
---@param records table[]
---@return string[]
local function build_data_lines(st, records)
  local lines = {}
  for _, rec in ipairs(records) do
    table.insert(lines, render_record_line(rec, st.columns, st.col_widths))
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
      right_gravity = false,
      -- This extmark is just for the header; don't track it as a slug
    })
  end

  -- Slug identity extmark on each data line
  for i, rec in ipairs(records) do
    local row = i - 1  -- 0-indexed (no header lines in buffer)
    set_line_slug(bufnr, row, rec.slug, st)
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
        for i, col in ipairs(st.columns) do
          local old_rendered = vim.trim(pad(fmt_value(orig[col]), st.col_widths[i]))
          if old_rendered ~= (cells[i] or "") then changed = true; break end
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
    vim.api.nvim_buf_set_extmark(bufnr, NS_DIFF, 0, 0, {
      sign_text = tostring(deleted), sign_hl_group = "DiffDelete", priority = 30,
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
---@return vault.OilEditDiff
local function diff_buffer(bufnr, st)
  local diff = { updates = {}, deletes = {}, creates = {} }
  local line_count = vim.api.nvim_buf_line_count(bufnr)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local seen = {}

  -- ── Reconcile extmark drift before diffing ──────────────────────────────
  local row_to_slug, drift_count, reconciled_count = reconcile_extmarks(bufnr, st, lines)

  if drift_count > 0 then
    vim.notify(
      string.format(
        "[vault] Extmark drift detected on %d row%s (%d reconciled via title matching)",
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
        for i, col in ipairs(st.columns) do
          if formula_set[col] then goto next_col end  -- skip read-only formula columns
          local old_rendered = vim.trim(pad(fmt_value(orig[col]), st.col_widths[i]))
          local new_text = cells[i] or ""
          if old_rendered ~= new_text then
            if old_rendered:match("…$") and not new_text:match("…$") then
              vim.notify(
                string.format("[vault] Warning: '%s' was truncated for %s — edit may replace full value", col, slug),
                vim.log.levels.WARN
              )
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
      for i, col in ipairs(st.columns) do
        local text = cells[i] or ""
        if text ~= "" and text ~= EMPTY_CELL then
          fields[col] = parse_value(text, col)
          has_content = true
        end
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
      "[vault] SAFETY: All line identity lost (even after title reconciliation) — refusing to save. "
        .. "Please close this buffer and reopen with :Vault process",
      vim.log.levels.ERROR
    )
    return { updates = {}, deletes = {}, creates = {}, _integrity_error = true }
  end

  if snapshot_size > 0 and identified_lines < non_empty_lines * 0.5 then
    -- PARTIAL identity loss: many lines unidentifiable. Refuse deletes.
    vim.notify(
      string.format(
        "[vault] SAFETY: Only %d/%d lines identified (after reconciliation) — "
          .. "skipping delete detection (updates still applied)",
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
--- Reduces corruption window and is faster than N individual set_frontmatter_field calls.
---@param path string
---@param fields table<string, any>  key → value (nil value = delete key)
local function set_frontmatter_fields(path, fields)
  for key, value in pairs(fields) do
    -- Apply one at a time but on the same file — each call re-reads.
    -- TODO: optimize to single read-modify-write if perf becomes an issue.
    -- For now, correctness > performance: each call validates independently.
    set_frontmatter_field(path, key, value)
  end
end

--- Apply all mutations from a diff.
---@param diff vault.OilEditDiff
---@param st vault.OilEditState
---@return integer updates, integer deletes, integer creates
local function apply_mutations(diff, st)
  local n_updates, n_deletes, n_creates = 0, 0, 0

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
          note:move(new_path, false, false)
        end)
        if move_ok then
          st.note_paths[upd.slug] = new_path
          path = new_path
        end
      end
    end

    -- Phase 2: all other field writes (batched to minimize I/O)
    local fm_fields = {}
    for col, new_val in pairs(upd.fields) do
      if col ~= "dir" then  -- dir already handled above
        fm_fields[col] = new_val
      end
    end
    if next(fm_fields) then
      set_frontmatter_fields(path, fm_fields)
    end
    n_updates = n_updates + 1
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
    end
    ::del_continue::
  end

  -- Creates
  for _, create in ipairs(diff.creates) do
    local title = create.fields.title
    if not title or title == "" then goto continue end
    local slug = title:lower():gsub("%s+", "-"):gsub("[%c%[%]#|^]", "")
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

    local fm = { "---" }
    if create.fields.title then
      table.insert(fm, "title: " .. yaml_quote(create.fields.title))
    end
    if create.fields.status then
      table.insert(fm, "status: " .. yaml_quote(create.fields.status))
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
    n_creates = n_creates + 1
    ::continue::
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

  local diff = diff_buffer(bufnr, st)

  -- Integrity error — diff_buffer already notified the user
  if diff._integrity_error then
    vim.bo[bufnr].modified = false
    st.saving = false
    return
  end

  local total = #diff.updates + #diff.deletes + #diff.creates
  if total == 0 then
    vim.bo[bufnr].modified = false
    st.saving = false
    vim.notify("[vault] No changes", vim.log.levels.INFO)
    return
  end

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
  if #diff.creates > 0 and #diff.deletes > 0 then
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

  -- ── No deletes: apply immediately ────────────────────────────────────────
  if #diff.deletes == 0 then
    local n_u, _, n_c = apply_mutations(diff, st)
    vim.notify(
      string.format("[vault] Applied: %d updated, %d created", n_u, n_c),
      vim.log.levels.INFO
    )
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
  local base = opts.base
  local columns = opts.columns or DEFAULT_COLUMNS
  local display_names = {}
  local formula_cols = {}
  local filter_desc = opts.filter_desc or "all notes"

  -- If a base is provided, derive columns/filters/formulas from it
  if base then
    columns, display_names, formula_cols = columns_from_base(base)
    filter_desc = opts.filter_desc or ("base:" .. (base.data.name or "unnamed"))
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

  -- Create buffer
  local bufnr = vim.api.nvim_create_buf(true, false)
  local buf_name = "vault://process/" .. filter_desc:gsub("%s+", "-")
  pcall(vim.api.nvim_buf_set_name, bufnr, buf_name)
  vim.bo[bufnr].buftype = "acwrite"
  vim.bo[bufnr].filetype = "vault_process"
  vim.bo[bufnr].swapfile = false

  -- Compute layout
  local col_widths = calc_col_widths(columns, records)

  -- Build state
  local st = {
    bufnr         = bufnr,
    columns       = columns,
    col_widths    = col_widths,
    snapshot      = build_snapshot(records, columns),
    note_paths    = {},
    note_mtimes   = {},
    mark_to_slug  = {},
    slug_to_mark  = {},
    filter_desc   = filter_desc,
    saving        = false,
    base          = base,
    display_names = display_names,
    formula_cols  = formula_cols,
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

  -- Open in current window
  vim.api.nvim_set_current_buf(bufnr)
  local winid = vim.api.nvim_get_current_win()
  st.winid = winid

  -- Window options (no conceal needed — slug is in extmarks, not text)
  vim.wo[winid].signcolumn = "yes"
  vim.wo[winid].number = false
  vim.wo[winid].relativenumber = false
  vim.wo[winid].wrap = false

  -- Apply extmarks: header virt_lines + slug identity on each data line
  apply_extmarks(bufnr, st, records)

  -- BufWriteCmd autocmd
  vim.api.nvim_create_autocmd("BufWriteCmd", {
    buffer = bufnr,
    callback = function() on_save(bufnr) end,
  })

  -- Live diff signs on TextChanged (no re-conceal needed — much cheaper)
  vim.api.nvim_create_autocmd({ "TextChanged", "InsertLeave" }, {
    buffer = bufnr,
    callback = function()
      local s = buf_states[bufnr]
      if s and not s.saving then
        update_diff_signs(bufnr, s)
      end
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
      local d = diff_buffer(bufnr, s)
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

  vim.notify(
    string.format("[vault] Processing %d notes (%s) — :w to apply changes", #records, filter_desc),
    vim.log.levels.INFO
  )
end

--- Reload an existing process buffer with fresh data.
---@param bufnr integer
function M.reload(bufnr)
  local st = buf_states[bufnr]
  if not st then return end

  -- Check if we need Note objects for formula evaluation
  local has_formulas = st.formula_cols and #st.formula_cols > 0
  local formula_results_by_slug = {}

  if has_formulas and st.base then
    -- Re-create Note objects for formula evaluation
    local Note = require("vault.notes.note")
    for slug, path in pairs(st.note_paths) do
      if vim.fn.filereadable(path) == 1 then
        local ok, note = pcall(Note, path)
        if ok and note then
          formula_results_by_slug[slug] = st.base:evaluate_formulas(note)
        end
      end
    end
  end

  -- Re-scan notes
  local records = {}
  local dead_slugs = {}
  for slug, path in pairs(st.note_paths) do
    if vim.fn.filereadable(path) == 1 then
      local fm = read_frontmatter_fields(path, st.columns)
      local fields = {}
      for _, col in ipairs(st.columns) do
        if col == "title" then
          fields.title = fm.title or slug
        elseif col == "dir" then
          local relpath = require("vault.utils").path_to_relpath(path)
          local dir = relpath:match("^(.-/)[^/]*$") or "/"
          fields.dir = dir
        elseif col == "tags" then
          fields.tags = fm.tags
        elseif col:match("^formula%.") then
          local formula_name = col:match("^formula%.(.+)")
          local results = formula_results_by_slug[slug]
          fields[col] = results and results[formula_name] or nil
        else
          fields[col] = fm[col]
        end
      end
      table.insert(records, { slug = slug, path = path, fields = fields })
    else
      table.insert(dead_slugs, slug)
    end
  end
  for _, slug in ipairs(dead_slugs) do
    st.note_paths[slug] = nil
    if st.note_mtimes then st.note_mtimes[slug] = nil end
  end
  table.sort(records, function(a, b) return a.slug < b.slug end)

  -- Recompute + refresh mtimes
  st.col_widths = calc_col_widths(st.columns, records)
  st.snapshot = build_snapshot(records, st.columns)
  st.note_mtimes = {}
  for _, rec in ipairs(records) do
    st.note_mtimes[rec.slug] = get_mtime(rec.path)
  end

  local lines = build_data_lines(st, records)
  set_buffer_lines(bufnr, lines)
  vim.bo[bufnr].modifiable = true
  apply_extmarks(bufnr, st, records)
  vim.api.nvim_buf_clear_namespace(bufnr, NS_DIFF, 0, -1)
  vim.bo[bufnr].modified = false
end

--- Debug: expose buf_states for testing
M._buf_states = buf_states

return M
