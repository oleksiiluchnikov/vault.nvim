-- lua/vault/oil_edit.lua
-- Oil.nvim-style editable buffer for vault note metadata.
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
local NS         = vim.api.nvim_create_namespace("vault_oil_edit")
local NS_DIFF    = vim.api.nvim_create_namespace("vault_oil_diff")

-- ─── Per-buffer state ─────────────────────────────────────────────────────────

---@class vault.OilEditState
---@field bufnr        integer
---@field winid        integer
---@field columns      string[]         ordered column names
---@field col_widths   integer[]        display width per column
---@field snapshot     table<string, table<string, string>>  slug → {col → value}
---@field note_paths   table<string, string>  slug → absolute path
---@field mark_to_slug table<integer, string>  extmark_id → slug
---@field slug_to_mark table<string, integer>  slug → extmark_id
---@field filter_desc  string           human description of the filter used
---@field saving       boolean

local buf_states = {}  -- [bufnr] = vault.OilEditState

-- ─── Default columns ──────────────────────────────────────────────────────────

local DEFAULT_COLUMNS = { "title", "status", "tags", "dir" }

-- ─── Value formatting ─────────────────────────────────────────────────────────

---@param value any
---@return string
local function fmt_value(value)
  if value == nil or value == "" then return EMPTY_CELL end
  if type(value) == "table" then
    local parts = {}
    for _, v in ipairs(value) do
      if type(v) == "string" and v ~= "" then
        table.insert(parts, v:match("^#") and v or ("#" .. v))
      end
    end
    return #parts > 0 and table.concat(parts, " ") or EMPTY_CELL
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
      local cell = fmt_value(records[j].fields[col])
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
  local marks = vim.api.nvim_buf_get_extmarks(bufnr, NS, { row, 0 }, { row, 0 }, {})
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
---@return table[]  list of {slug, path, fields={col→value}}
local function build_records(notes_map, columns)
  local records = {}
  for slug, note in pairs(notes_map) do
    local path = note.data and note.data.path or note.path
    if not path then goto continue end

    local fm = read_frontmatter_fields(path, columns)
    local fields = {}
    for _, col in ipairs(columns) do
      if col == "title" then
        fields.title = fm.title or (note.data and note.data.stem) or slug
      elseif col == "dir" then
        local relpath = note.data and note.data.relpath or ""
        local dir = relpath:match("^(.-/)[^/]*$") or ""
        fields.dir = dir ~= "" and dir or "/"
      elseif col == "tags" then
        fields.tags = fm.tags or (note.data and note.data.frontmatter and note.data.frontmatter.tags) or nil
      else
        fields[col] = fm[col]
      end
    end

    table.insert(records, { slug = slug, path = path, fields = fields })
    ::continue::
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
    local cell = fmt_value(rec.fields[col])
    table.insert(cells, pad(cell, widths[i]))
  end
  return table.concat(cells, SEP)
end

--- Build the header virt_lines chunks for display above row 0.
---@param st vault.OilEditState
---@return table[] virt_lines  list of {chunks} for nvim_buf_set_extmark virt_lines
local function build_header_virt_lines(st)
  -- Header row
  local hcells = {}
  for i, col in ipairs(st.columns) do
    table.insert(hcells, pad(col, st.col_widths[i]))
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

  for row = 0, line_count - 1 do
    local line = lines[row + 1]
    if vim.trim(line) == "" then goto continue end

    local slug = get_line_slug(bufnr, row, st)
    if not slug then
      -- No extmark → new note
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

  -- Count non-empty lines and extmark hits for integrity check
  local non_empty_lines = 0
  local extmark_hits = 0

  for row = 0, line_count - 1 do
    local line = lines[row + 1]
    if vim.trim(line) == "" then goto continue end
    non_empty_lines = non_empty_lines + 1

    local slug = get_line_slug(bufnr, row, st)
    local cells = split_cells(line)

    if slug then
      extmark_hits = extmark_hits + 1
      seen[slug] = true
      local orig = st.snapshot[slug]
      if orig then
        local changed_fields = {}
        local has_changes = false
        for i, col in ipairs(st.columns) do
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
        end
        if has_changes then
          table.insert(diff.updates, { slug = slug, fields = changed_fields })
        end
      end
    else
      -- No extmark → new note
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

  -- ── SAFETY: Extmark integrity check ──────────────────────────────────────
  -- If extmarks are missing on lines that should have them, the slug identity
  -- has been lost. Computing deletes in this state would be catastrophic.
  local snapshot_size = vim.tbl_count(st.snapshot)

  if snapshot_size > 0 and non_empty_lines > 0 and extmark_hits == 0 then
    -- TOTAL extmark loss: every line lost its identity. Refuse ALL operations.
    vim.notify(
      "[vault] SAFETY: All extmark identity lost — refusing to save. "
        .. "Please close this buffer and reopen with :Vault process",
      vim.log.levels.ERROR
    )
    return { updates = {}, deletes = {}, creates = {}, _integrity_error = true }
  end

  if snapshot_size > 0 and extmark_hits < non_empty_lines * 0.5 then
    -- PARTIAL extmark loss: many lines lost identity. Refuse deletes.
    vim.notify(
      string.format(
        "[vault] SAFETY: Only %d/%d lines have extmark identity — "
          .. "skipping delete detection (updates still applied)",
        extmark_hits, non_empty_lines
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
  local ok, lines = pcall(vim.fn.readfile, path)
  if not ok then return end
  if not lines[1] or not lines[1]:match("^%-%-%-$") then return end

  local fm_end = nil
  for i = 2, math.min(#lines, 100) do  -- frontmatter must close within 100 lines
    if lines[i]:match("^%-%-%-$") then fm_end = i; break end
  end
  if not fm_end then return end

  -- Safety: verify the rewritten file preserves all content after frontmatter
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

  -- Build the new value lines
  local new_lines = {}
  if value ~= nil then
    if type(value) == "table" then
      table.insert(new_lines, key .. ":")
      for _, v in ipairs(value) do
        table.insert(new_lines, "  - " .. tostring(v))
      end
    else
      table.insert(new_lines, key .. ": " .. tostring(value))
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
        vim.fn.fnamemodify(path, ":t"), new_body_count, body_line_count),
      vim.log.levels.ERROR
    )
    return
  end

  vim.fn.writefile(result, path)
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

    -- Phase 2: all other field writes
    for col, new_val in pairs(upd.fields) do
      if col == "dir" then
        -- already handled above
      elseif col == "tags" then
        set_frontmatter_field(path, "tags", new_val)
      else
        set_frontmatter_field(path, col, new_val)
      end
    end
    n_updates = n_updates + 1
    ::continue::
  end

  -- Deletes
  for _, slug in ipairs(diff.deletes) do
    local path = st.note_paths[slug]
    if path then
      pcall(function()
        local Note = require("vault.notes.note")
        local note = Note(path)
        note:delete(false, false)
      end)
      n_deletes = n_deletes + 1
    end
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

    local fm = { "---" }
    if create.fields.title then
      table.insert(fm, "title: " .. create.fields.title)
    end
    if create.fields.status then
      table.insert(fm, "status: " .. create.fields.status)
    end
    if create.fields.tags and type(create.fields.tags) == "table" then
      table.insert(fm, "tags:")
      for _, t in ipairs(create.fields.tags) do
        table.insert(fm, "  - " .. t)
      end
    end
    table.insert(fm, "---")
    table.insert(fm, "")

    local parent = vim.fn.fnamemodify(path, ":h")
    if vim.fn.isdirectory(parent) == 0 then
      vim.fn.mkdir(parent, "p")
    end
    vim.fn.writefile(fm, path)
    n_creates = n_creates + 1
    ::continue::
  end

  return n_updates, n_deletes, n_creates
end

-- ─── Save handler ─────────────────────────────────────────────────────────────

--- Hard limit: refuse to delete more than this many notes in a single save.
--- Catches catastrophic extmark-loss scenarios that slip past integrity checks.
local DELETE_HARD_CAP = 100

--- Apply safe mutations (updates + creates only) and reload.
---@param bufnr integer
---@param st vault.OilEditState
---@param diff vault.OilEditDiff
local function apply_safe_and_reload(bufnr, st, diff)
  local safe_diff = { updates = diff.updates, deletes = {}, creates = diff.creates }
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
---@param opts? { notes?: vault.Notes, columns?: string[], filter_desc?: string }
function M.open(opts)
  opts = opts or {}
  local columns = opts.columns or DEFAULT_COLUMNS
  local filter_desc = opts.filter_desc or "all notes"

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

  -- Get notes
  local notes
  if opts.notes then
    notes = opts.notes
  else
    notes = require("vault.notes")()
  end

  local notes_map = notes.map or {}
  if not next(notes_map) then
    vim.notify("[vault] No notes to process", vim.log.levels.INFO)
    return
  end

  -- Build records
  local records = build_records(notes_map, columns)

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
    bufnr        = bufnr,
    columns      = columns,
    col_widths   = col_widths,
    snapshot     = build_snapshot(records, columns),
    note_paths   = {},
    mark_to_slug = {},
    slug_to_mark = {},
    filter_desc  = filter_desc,
    saving       = false,
  }
  for _, rec in ipairs(records) do
    st.note_paths[rec.slug] = rec.path
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
  end
  table.sort(records, function(a, b) return a.slug < b.slug end)

  -- Recompute
  st.col_widths = calc_col_widths(st.columns, records)
  st.snapshot = build_snapshot(records, st.columns)

  local lines = build_data_lines(st, records)
  set_buffer_lines(bufnr, lines)
  vim.bo[bufnr].modifiable = true
  apply_extmarks(bufnr, st, records)
  vim.api.nvim_buf_clear_namespace(bufnr, NS_DIFF, 0, -1)
  vim.bo[bufnr].modified = false
end

return M
