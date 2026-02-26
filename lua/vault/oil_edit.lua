-- lua/vault/oil_edit.lua
-- Oil.nvim-style editable buffer for vault note metadata.
--
-- Pattern (adapted from oil.nvim + airtable.nvim):
--   1. Render notes as text lines with a hidden slug prefix (concealed).
--   2. buftype=acwrite so :w fires BufWriteCmd instead of touching disk.
--   3. On BufWriteCmd: diff buffer lines against snapshot → mutations.
--   4. Mutations rewrite YAML frontmatter, move/rename, delete, or create.
--   5. After mutations complete, re-scan and re-render.
--
-- Line format (visible after concealing):
--   /my-note-slug        Published │ #rust #programming │ Projects/
--   ^── concealed ──^
--
-- Lines without a /slug prefix → new note (CREATE).
-- Lines from snapshot missing in buffer → note trashed (DELETE).

local M = {}

-- ─── Constants ────────────────────────────────────────────────────────────────

local SEP        = " │ "
local ID_PREFIX  = "/"
local EMPTY_CELL = "∅"
local NS         = vim.api.nvim_create_namespace("vault_oil_edit")
local NS_DIFF    = vim.api.nvim_create_namespace("vault_oil_diff")
local HEADER_LINES = 2  -- header + separator

-- ─── Per-buffer state ─────────────────────────────────────────────────────────

---@class vault.OilEditState
---@field bufnr        integer
---@field winid        integer
---@field columns      string[]         ordered column names
---@field col_widths   integer[]        display width per column
---@field id_width     integer          byte length of slug prefix
---@field snapshot     table<string, table<string, string>>  slug → {col → value}
---@field note_paths   table<string, string>  slug → absolute path
---@field header_lines integer
---@field header_text  string[]
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
    -- tags array → "#foo #bar"
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

---@param text string
---@param col_name string
---@return any
local function parse_value(text, col_name)
  if text == EMPTY_CELL or text == "" then return nil end
  if col_name == "tags" then
    local tags = {}
    for tag in text:gmatch("#([%w/_%-%.]+)") do
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
  local content_width = win_width - 40 - sep_total  -- 40 for concealed ID

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

-- ─── ID prefix helpers ────────────────────────────────────────────────────────

---@param slugs string[]
---@return integer
local function compute_id_width(slugs)
  local max_len = 20
  for _, slug in ipairs(slugs) do
    local token_len = 1 + #slug + 2  -- "/" + slug + "  "
    if token_len > max_len then max_len = token_len end
  end
  return max_len
end

---@param slug string
---@param width integer
---@return string
local function id_token(slug, width)
  local raw = ID_PREFIX .. slug .. "  "
  if #raw < width then
    raw = raw .. string.rep(" ", width - #raw)
  end
  return raw
end

---@param line string
---@return string|nil slug
---@return string rest
local function parse_id(line)
  local slug, rest = line:match("^/([%w/_%-%.]+)%s%s+(.*)")
  if slug then return slug, rest end
  return nil, line
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

-- ─── Data extraction ──────────────────────────────────────────────────────────

--- Read note frontmatter fields for the given columns.
---@param path string
---@param columns string[]
---@return table<string, any>
local function read_frontmatter_fields(path, columns)
  local fields = {}
  local ok, lines = pcall(vim.fn.readfile, path, "", 50)  -- first 50 lines
  if not ok then return fields end

  -- Find frontmatter block
  if not lines[1] or not lines[1]:match("^%-%-%-") then return fields end
  local fm_lines = {}
  for i = 2, #lines do
    if lines[i]:match("^%-%-%-") then break end
    table.insert(fm_lines, lines[i])
  end

  -- Simple YAML key: value parser (handles tags as list)
  local current_key = nil
  local current_list = nil
  for _, l in ipairs(fm_lines) do
    -- List continuation: "  - value"
    local list_item = l:match("^%s+%-%s+(.+)")
    if list_item and current_key and current_list then
      -- Strip surrounding quotes
      list_item = list_item:gsub('^"(.*)"$', '%1'):gsub("^'(.*)'$", '%1')
      table.insert(current_list, list_item)
    else
      -- New key: value line
      local key, value = l:match("^([%w_%-]+):%s*(.*)")
      if key then
        -- Flush previous list
        if current_key and current_list and #current_list > 0 then
          fields[current_key] = current_list
        end
        current_key = key
        current_list = nil

        value = vim.trim(value or "")
        if value == "" then
          -- Could be start of a list
          current_list = {}
        elseif value:match("^%[") then
          -- Inline list: [foo, bar]
          local items = {}
          for item in value:gmatch("[%w/_%-%.]+") do
            table.insert(items, item)
          end
          fields[key] = items
          current_key = nil
        else
          -- Strip surrounding quotes
          value = value:gsub('^"(.*)"$', '%1'):gsub("^'(.*)'$", '%1')
          -- Handle wikilink values: "[[foo]]" → "foo"
          value = value:gsub("^%[%[(.-)%]%]$", "%1")
          fields[key] = value
          current_key = nil
        end
      end
    end
  end
  -- Flush last list
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
        fields.title = fm.title or note.data and note.data.stem or slug
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
  -- Sort by slug for stable ordering
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
---@param id_w integer
---@return string
local function render_record_line(rec, columns, widths, id_w)
  local cells = {}
  for i, col in ipairs(columns) do
    local cell = fmt_value(rec.fields[col])
    table.insert(cells, pad(cell, widths[i]))
  end
  return id_token(rec.slug, id_w) .. table.concat(cells, SEP)
end

---@param st vault.OilEditState
---@param records table[]
---@return string[]
local function build_lines(st, records)
  local lines = {}
  -- Header
  local hcells = {}
  for i, col in ipairs(st.columns) do
    table.insert(hcells, pad(col, st.col_widths[i]))
  end
  table.insert(lines, table.concat(hcells, SEP))
  -- Separator
  local sep_parts = {}
  for i, _ in ipairs(st.columns) do
    table.insert(sep_parts, string.rep("─", st.col_widths[i]))
  end
  table.insert(lines, table.concat(sep_parts, "─┼─"))
  -- Data
  for _, rec in ipairs(records) do
    table.insert(lines, render_record_line(rec, st.columns, st.col_widths, st.id_width))
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

---@param bufnr integer
---@param row integer  0-indexed
local function apply_conceal_to_line(bufnr, row)
  local line = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1] or ""
  local prefix = line:match("^(/[%w/_%-%.]+%s%s+)")
  if prefix then
    vim.api.nvim_buf_set_extmark(bufnr, NS, row, 0, {
      end_col  = #prefix,
      conceal  = "",
      priority = 200,
    })
  end
end

---@param bufnr integer
---@param st vault.OilEditState
---@param num_records integer
local function apply_highlights(bufnr, st, num_records)
  vim.api.nvim_buf_clear_namespace(bufnr, NS, 0, -1)
  -- Header highlight
  for row = 0, st.header_lines - 1 do
    vim.api.nvim_buf_set_extmark(bufnr, NS, row, 0, {
      line_hl_group = "Visual",
      priority = 10,
    })
  end
  -- Conceal ID prefixes on data lines
  local total = vim.api.nvim_buf_line_count(bufnr)
  for row = st.header_lines, total - 1 do
    apply_conceal_to_line(bufnr, row)
  end
end

---@param bufnr integer
---@param st vault.OilEditState
local function restore_header_if_needed(bufnr, st)
  if not st.header_text or #st.header_text == 0 then return end
  local current = vim.api.nvim_buf_get_lines(bufnr, 0, st.header_lines, false)
  local needs_fix = false
  for i = 1, st.header_lines do
    if current[i] ~= st.header_text[i] then needs_fix = true; break end
  end
  if needs_fix then
    local saved_ei = vim.o.eventignore
    vim.o.eventignore = "TextChanged,TextChangedI,TextChangedP"
    vim.bo[bufnr].modifiable = true
    vim.api.nvim_buf_set_lines(bufnr, 0, st.header_lines, false, st.header_text)
    vim.o.eventignore = saved_ei
    for row = 0, st.header_lines - 1 do
      vim.api.nvim_buf_set_extmark(bufnr, NS, row, 0, {
        line_hl_group = "Visual",
        priority = 10,
      })
    end
  end
end

-- ─── Diff signs ───────────────────────────────────────────────────────────────

---@param bufnr integer
---@param st vault.OilEditState
local function update_diff_signs(bufnr, st)
  vim.api.nvim_buf_clear_namespace(bufnr, NS_DIFF, 0, -1)
  local lines = vim.api.nvim_buf_get_lines(bufnr, st.header_lines, -1, false)
  for idx, line in ipairs(lines) do
    if vim.trim(line) == "" then goto continue end
    local row = st.header_lines + idx - 1
    local slug, rest = parse_id(line)
    if not slug then
      -- New note
      local cells = split_cells(rest)
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
      local orig = st.snapshot[slug]
      if orig then
        local cells = split_cells(rest)
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
  local seen = {}
  for _, line in ipairs(lines) do
    local rid = parse_id(line)
    if rid then seen[rid] = true end
  end
  local deleted = 0
  for slug, _ in pairs(st.snapshot) do
    if not seen[slug] then deleted = deleted + 1 end
  end
  if deleted > 0 then
    vim.api.nvim_buf_set_extmark(bufnr, NS_DIFF, 1, 0, {
      sign_text = tostring(deleted), sign_hl_group = "DiffDelete", priority = 30,
    })
  end
end

-- ─── Diff engine ──────────────────────────────────────────────────────────────

---@class vault.OilEditDiff
---@field updates table[]  {slug: string, fields: table<string, any>}
---@field deletes string[]  slugs
---@field creates table[]  {fields: table<string, any>}

---@param bufnr integer
---@param st vault.OilEditState
---@return vault.OilEditDiff
local function diff_buffer(bufnr, st)
  local diff = { updates = {}, deletes = {}, creates = {} }
  local lines = vim.api.nvim_buf_get_lines(bufnr, st.header_lines, -1, false)
  local seen = {}

  for _, line in ipairs(lines) do
    if vim.trim(line) == "" then goto continue end
    local slug, rest = parse_id(line)
    local cells = split_cells(rest)

    if slug then
      seen[slug] = true
      local orig = st.snapshot[slug]
      if orig then
        local changed_fields = {}
        local has_changes = false
        for i, col in ipairs(st.columns) do
          local old_rendered = vim.trim(pad(fmt_value(orig[col]), st.col_widths[i]))
          local new_text = cells[i] or ""
          if old_rendered ~= new_text then
            changed_fields[col] = parse_value(new_text, col)
            has_changes = true
          end
        end
        if has_changes then
          table.insert(diff.updates, { slug = slug, fields = changed_fields })
        end
      end
    else
      -- New note
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

  -- Deletes: in snapshot but not in buffer
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
  if not lines[1] or not lines[1]:match("^%-%-%-") then return end

  -- Find frontmatter end
  local fm_end = nil
  for i = 2, #lines do
    if lines[i]:match("^%-%-%-") then fm_end = i; break end
  end
  if not fm_end then return end

  -- Build new frontmatter lines
  local fm_lines = {}
  for i = 2, fm_end - 1 do
    table.insert(fm_lines, lines[i])
  end

  -- Remove existing key (and any list continuation)
  local new_fm = {}
  local skip = false
  for _, l in ipairs(fm_lines) do
    if skip then
      if l:match("^%s+%-") then
        goto continue  -- skip list items
      else
        skip = false
      end
    end
    if l:match("^" .. vim.pesc(key) .. ":") then
      skip = true  -- will add new value below
      -- Check if next lines are list items
      goto continue
    end
    table.insert(new_fm, l)
    ::continue::
  end

  -- Add new value
  if value ~= nil then
    if type(value) == "table" then
      table.insert(new_fm, key .. ":")
      for _, v in ipairs(value) do
        table.insert(new_fm, "  - " .. tostring(v))
      end
    else
      table.insert(new_fm, key .. ": " .. tostring(value))
    end
  end

  -- Reconstruct file
  local result = { "---" }
  for _, l in ipairs(new_fm) do table.insert(result, l) end
  table.insert(result, "---")
  for i = fm_end + 1, #lines do table.insert(result, lines[i]) end

  vim.fn.writefile(result, path)
end

--- Apply all mutations from a diff.
---@param diff vault.OilEditDiff
---@param st vault.OilEditState
---@return integer updates, integer deletes, integer creates
local function apply_mutations(diff, st)
  local n_updates, n_deletes, n_creates = 0, 0, 0

  -- Updates
  for _, upd in ipairs(diff.updates) do
    local path = st.note_paths[upd.slug]
    if not path then goto continue end

    for col, new_val in pairs(upd.fields) do
      if col == "dir" then
        -- Move note to new directory
        local config = require("vault.config")
        local new_dir = new_val or ""
        if new_dir == "/" then new_dir = "" end
        local basename = vim.fn.fnamemodify(path, ":t")
        local new_path = config.options.root .. "/" .. new_dir .. basename
        if new_path ~= path then
          pcall(function()
            local Note = require("vault.notes.note")
            local note = Note(path)
            note:move(new_path, false, false)
            -- Update path in state for subsequent field edits
            st.note_paths[upd.slug] = new_path
            path = new_path
          end)
        end
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
        note:delete(false, false)  -- soft delete to .trash
      end)
      n_deletes = n_deletes + 1
    end
  end

  -- Creates
  for _, create in ipairs(diff.creates) do
    local title = create.fields.title
    if not title or title == "" then goto continue end
    local slug = title:lower():gsub("%s+", "-"):gsub("[^%w%-]", "")
    local config = require("vault.config")
    local dir = create.fields.dir or ""
    if dir == "/" then dir = "" end
    local path = config.options.root .. "/" .. dir .. slug .. config.options.ext
    if vim.fn.filereadable(path) == 1 then
      vim.notify("[vault] Note already exists: " .. slug, vim.log.levels.WARN)
      goto continue
    end

    -- Build frontmatter
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

    -- Ensure directory exists
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

---@param bufnr integer
local function on_save(bufnr)
  local st = buf_states[bufnr]
  if not st then return end
  if st.saving then return end
  st.saving = true

  local diff = diff_buffer(bufnr, st)
  local total = #diff.updates + #diff.deletes + #diff.creates
  if total == 0 then
    vim.bo[bufnr].modified = false
    st.saving = false
    vim.notify("[vault] No changes", vim.log.levels.INFO)
    return
  end

  local n_u, n_d, n_c = apply_mutations(diff, st)
  vim.notify(
    string.format("[vault] Applied: %d updated, %d trashed, %d created", n_u, n_d, n_c),
    vim.log.levels.INFO
  )

  -- Reload: re-scan and re-render
  vim.schedule(function()
    M.reload(bufnr)
    st.saving = false
  end)
end

-- ─── Public API ───────────────────────────────────────────────────────────────

--- Open a vault process buffer.
---@param opts? { notes?: vault.Notes, columns?: string[], filter_desc?: string }
function M.open(opts)
  opts = opts or {}
  local columns = opts.columns or DEFAULT_COLUMNS
  local filter_desc = opts.filter_desc or "all notes"

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
  local slugs = {}
  for _, rec in ipairs(records) do table.insert(slugs, rec.slug) end

  -- Create buffer
  local bufnr = vim.api.nvim_create_buf(true, false)
  local buf_name = "vault://process/" .. filter_desc:gsub("%s+", "-")
  pcall(vim.api.nvim_buf_set_name, bufnr, buf_name)
  vim.bo[bufnr].buftype = "acwrite"
  vim.bo[bufnr].filetype = "vault_process"
  vim.bo[bufnr].swapfile = false

  -- Compute layout
  local id_w = compute_id_width(slugs)
  local col_widths = calc_col_widths(columns, records)

  -- Build state
  local st = {
    bufnr       = bufnr,
    columns     = columns,
    col_widths  = col_widths,
    id_width    = id_w,
    snapshot    = build_snapshot(records, columns),
    note_paths  = {},
    header_lines = HEADER_LINES,
    header_text  = nil,
    filter_desc  = filter_desc,
    saving       = false,
  }
  for _, rec in ipairs(records) do
    st.note_paths[rec.slug] = rec.path
  end
  buf_states[bufnr] = st

  -- Render
  local lines = build_lines(st, records)
  st.header_text = { lines[1], lines[2] }
  set_buffer_lines(bufnr, lines)
  vim.bo[bufnr].modifiable = true  -- allow editing after initial render

  -- Open in current window
  vim.api.nvim_set_current_buf(bufnr)
  local winid = vim.api.nvim_get_current_win()
  st.winid = winid

  -- Window options for concealing
  vim.wo[winid].conceallevel = 2
  vim.wo[winid].concealcursor = "nvic"
  vim.wo[winid].signcolumn = "yes"
  vim.wo[winid].number = false
  vim.wo[winid].relativenumber = false
  vim.wo[winid].wrap = false

  -- Apply highlights and conceals
  apply_highlights(bufnr, st, #records)

  -- BufWriteCmd autocmd
  vim.api.nvim_create_autocmd("BufWriteCmd", {
    buffer = bufnr,
    callback = function() on_save(bufnr) end,
  })

  -- Live diff signs on TextChanged
  vim.api.nvim_create_autocmd({ "TextChanged", "InsertLeave" }, {
    buffer = bufnr,
    callback = function()
      local s = buf_states[bufnr]
      if s and not s.saving then
        restore_header_if_needed(bufnr, s)
        update_diff_signs(bufnr, s)
        -- Re-apply conceals (user may have added/edited lines)
        local total = vim.api.nvim_buf_line_count(bufnr)
        for row = s.header_lines, total - 1 do
          apply_conceal_to_line(bufnr, row)
        end
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

  -- Re-scan notes (using slug → path mapping from state for fresh reads)
  local records = {}
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
    end
  end
  table.sort(records, function(a, b) return a.slug < b.slug end)

  -- Recompute
  st.col_widths = calc_col_widths(st.columns, records)
  st.id_width = compute_id_width(vim.tbl_keys(st.note_paths))
  st.snapshot = build_snapshot(records, st.columns)

  local lines = build_lines(st, records)
  st.header_text = { lines[1], lines[2] }
  set_buffer_lines(bufnr, lines)
  vim.bo[bufnr].modifiable = true
  apply_highlights(bufnr, st, #records)
  vim.api.nvim_buf_clear_namespace(bufnr, NS_DIFF, 0, -1)
  vim.bo[bufnr].modified = false
end

return M
