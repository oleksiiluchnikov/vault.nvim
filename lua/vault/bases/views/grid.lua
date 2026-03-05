-- lua/vault/bases/views/grid.lua
-- Grid-backed vault process buffer: thin adapter over vimtable.views.grid.Grid.
--
-- Drop-in sibling to editor.lua. Uses the Grid view for all rendering, conceal,
-- header, cursor, diff signs, and inline validation. Vault-specific logic
-- (frontmatter, rename, move, delete, create, undo, merge, safety checks) lives
-- here as callbacks and keymaps.
--
-- Usage: same as editor.lua — M.open({ notes = ..., base = ..., ... })

local M = {}

local log = require("vault.log").scope("bases.views.grid")
local shared = require("vault.bases.views.shared")

-- ─── Lazy imports (avoid circular requires at module level) ───────────────────

local function get_Grid()
  return require("vimtable.views.grid").Grid
end

-- ─── Constants (delegated to shared) ──────────────────────────────────────────

local DEFAULT_COLUMNS = { "slug", "title", "status", "tags" }

local READONLY_FILE_COLS = shared.READONLY_FILE_COLS
local FILE_IMPLICIT_PROPS = shared.FILE_IMPLICIT_PROPS

local DELETE_HARD_CAP = 100
local CREATE_HARD_CAP = 100

local get_empty_cell = shared.get_empty_cell

-- ─── Row highlight defaults ───────────────────────────────────────────────────

--- Define default highlight groups for row coloring (linked, user can override).
local function ensure_row_hl_groups()
  local defaults = {
    VaultRowDone     = { link = "Comment" },
    VaultRowUntagged = { link = "DiagnosticVirtualTextInfo" },
  }
  for name, def in pairs(defaults) do
    vim.api.nvim_set_hl(0, name, vim.tbl_extend("keep", vim.api.nvim_get_hl(0, { name = name }), def))
  end
end

--- @class vault.RowHlRule
--- @field match table<string, any>  Field conditions: { status = "done" } or { tags = {} }
--- @field hl string                 Highlight group name

--- Build a row_hl callback from config rules or a user function.
--- @return fun(record: table, row_idx: integer): string|nil
local function build_row_hl()
  local cfg = require("vault.config").options.process or {}
  local rules = cfg.row_hl
  if not rules then return function() return nil end end

  -- User provided a raw function — use directly
  if type(rules) == "function" then
    ---@diagnostic disable-next-line: return-type-mismatch
    return rules
  end

  -- Rule-based matching: first match wins
  --- @param record table
  --- @return string|nil
  return function(record, _)
    for _, rule in ipairs(rules) do
      local matched = true
      for field, expected in pairs(rule.match) do
        local val = record[field]
        if type(expected) == "table" and next(expected) == nil then
          -- Empty table means "field is nil or empty list"
          if val ~= nil and val ~= "" then
            if type(val) == "table" then
              if #val > 0 then matched = false; break end
            else
              matched = false; break
            end
          end
        elseif val ~= expected then
          matched = false; break
        end
      end
      if matched then return rule.hl end
    end
    return nil
  end
end

-- ─── Per-buffer state ─────────────────────────────────────────────────────────

---@class vault.GridEditorState
---@field grid table  Grid instance
---@field note_paths table<string, string>  slug → absolute path
---@field note_mtimes table<string, integer>  slug → mtime at snapshot time
---@field base? vault.Base
---@field filter_desc string
---@field columns string[]  ALL internal column names (always includes "slug")
---@field visible_columns string[]
---@field display_names table<string, string>
---@field formula_cols string[]
---@field slug_hidden boolean
---@field saving boolean|string

local buf_states = {} --- @type table<integer, vault.GridEditorState>
local vt_undo = require("vimtable.undo")

-- ─── Shared helpers (delegated to shared.lua) ─────────────────────────────────

local normalize_col = shared.normalize_col
local base_key_to_col = shared.base_key_to_col

---@param base vault.Base
---@return string[], table<string,string>, string[], string[]
local function columns_from_base(base)
  local columns, display_names, formula_cols = {}, {}, {}
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
  local base_display = base:display_names()
  local seen, has_slug = {}, false
  for _, key in ipairs(order) do
    local col, is_formula = base_key_to_col(key)
    if col == "slug" then has_slug = true end
    if not seen[col] then
      seen[col] = true
      table.insert(columns, col)
      display_names[col] = base_display[key] or col
      if is_formula then table.insert(formula_cols, col) end
    end
  end
  local visible_columns = vim.list_slice(columns, 1)
  if not has_slug then table.insert(columns, 1, "slug") end
  return columns, display_names, formula_cols, visible_columns
end

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

--- Extract group_by from base view definition.
--- @param base vault.Base
--- @return string|nil
local function group_by_from_base(base)
  if not base.data.views or not base.data.views[1] then return nil end
  local view = base.data.views[1]
  return view.group_by
end

local get_mtime = shared.get_mtime
local yaml_quote = shared.yaml_quote
local validate_path_in_vault = shared.validate_path_in_vault
local atomic_writefile = shared.atomic_writefile

-- ─── Frontmatter I/O (delegated to shared.lua) ───────────────────────────────

local read_frontmatter_fields = shared.read_frontmatter_fields
local set_frontmatter_field = shared.set_frontmatter_field
local set_frontmatter_fields = shared.set_frontmatter_fields

-- ─── Value formatting (delegated to shared.lua) ──────────────────────────────

local fmt_value = shared.fmt_value
local parse_value = shared.parse_value

-- ─── Record building ──────────────────────────────────────────────────────────

---@param notes_map table
---@param columns string[]
---@param base? vault.Base
---@return table[]
local function build_records(notes_map, columns, base)
  local records = {}
  local skipped = 0
  for slug, note in pairs(notes_map) do
    local ok, rec = pcall(function()
      local path = note.data and note.data.path or note.path
      if not path then return nil end
      local fm = read_frontmatter_fields(path, columns)
      local fields = {}
      local formula_results = {}
      if base and base:has_formulas() then
        formula_results = base:evaluate_formulas(note)
      end
      for _, col in ipairs(columns) do
        if col == "slug" then
          fields.slug = slug
        elseif col == "file.name" then
          fields[col] = note.data and note.data.stem or (slug:match("[^/]+$") or slug)
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
          local body = ""
          local f = path and io.open(path, "r")
          if f then
            local chunk = f:read(4096) or ""
            f:close()
            local after_fm = chunk:match("^%-%-%-.-\n%-%-%-\n(.*)") or chunk
            body = after_fm
          end
          fields[col] = body:gsub("\r?\n", " "):gsub("%s+", " "):match("^%s*(.-)%s*$") or ""
        elseif col == "file.inlinks" then
          local links = note.data and note.data.inlinks
          if links then
            local slugs = {}
            for s in pairs(links) do table.insert(slugs, s) end
            table.sort(slugs)
            fields[col] = table.concat(slugs, ", ")
          else
            fields[col] = ""
          end
        elseif col == "file.outlinks" then
          local links = note.data and note.data.outlinks
          if links then
            local slugs = {}
            for s in pairs(links) do table.insert(slugs, s) end
            table.sort(slugs)
            fields[col] = table.concat(slugs, ", ")
          else
            fields[col] = ""
          end
        elseif col == "file.headings" then
          local hdgs = note.data and note.data.headings
          fields[col] = hdgs and #hdgs > 0 and (hdgs[1].text or hdgs[1][2] or "") or ""
        elseif col == "title" then
          local basename = slug:match("[^/]+$") or slug
          fields.title = fm.title or (note.data and note.data.stem) or basename
        elseif col == "dir" then
          local relpath = note.data and note.data.relpath or ""
          local dir = relpath:match("^(.-/)[^/]*$") or ""
          fields.dir = dir ~= "" and dir or "/"
        elseif col == "tags" then
          fields.tags = fm.tags or (note.data and note.data.frontmatter and note.data.frontmatter.tags) or nil
        elseif col:match("^formula%.") then
          local fname = col:match("^formula%.(.+)")
          fields[col] = formula_results[fname]
        else
          fields[col] = fm[col]
        end
      end
      -- Grid expects flat records: { slug = "x", title = "y", ... }
      -- Convert from editor.lua's nested { slug, path, fields } format
      local flat = {}
      for k, v in pairs(fields) do flat[k] = v end
      flat._path = path  -- stash path for save handler
      return flat
    end)
    if ok and rec then
      table.insert(records, rec)
    else
      skipped = skipped + 1
    end
  end
  if skipped > 0 then log.warn("%d notes skipped due to parse errors", skipped) end
  table.sort(records, function(a, b) return (a.slug or "") < (b.slug or "") end)
  return records
end

-- ─── Build grid.Column[] from vault column spec ──────────────────────────────

---@param visible_columns string[]
---@param display_names table<string, string>
---@param formula_cols string[]
---@return table[]  grid.Column[]
local function build_grid_columns(visible_columns, display_names, formula_cols)
  local formula_set = {}
  for _, fc in ipairs(formula_cols) do formula_set[fc] = true end

  --- @type table[]
  local grid_cols = {}
  for _, col in ipairs(visible_columns) do
    local is_readonly = formula_set[col] or READONLY_FILE_COLS[col] or false
    --- @type table
    local gc = {
      name = col,
      header = display_names[col] or col,
      readonly = is_readonly,
    }
    -- Vault-specific formatter/parser
    gc.format = function(value)
      return fmt_value(value, col)
    end
    gc.parse = function(text)
      return parse_value(text, col)
    end
    table.insert(grid_cols, gc)
  end
  return grid_cols
end

-- ─── Classify callback ────────────────────────────────────────────────────────
-- Maps vault column semantics into the Grid's diff classify system.

---@param st vault.GridEditorState
---@return fun(id: string, field: string, old: string, new: string): string, table|nil
local function make_classify(st)
  return function(id, field, old, new)
    -- slug or file.slug edit → rename
    if field == "slug" or field == "file.slug" then
      local new_slug = vim.trim(new)
      if new_slug ~= "" and new_slug ~= id then
        return "rename", { old_slug = id, new_slug = new_slug }
      end
      return "skip"
    end
    -- file.name edit → rename (change filename stem)
    if field == "file.name" then
      local new_stem = vim.trim(new)
      local old_stem = (id:match("[^/]+$") or id)
      if new_stem ~= "" and new_stem ~= old_stem then
        local dir_prefix = id:match("^(.-/)[^/]*$") or ""
        return "rename", { old_slug = id, new_slug = dir_prefix .. new_stem }
      end
      return "skip"
    end
    -- file.folder edit → move (change directory)
    if field == "file.folder" then
      return "update", nil  -- treat as normal update; apply_mutations handles dir moves
    end
    return "update", nil
  end
end

-- ─── Undo snapshot ────────────────────────────────────────────────────────────

---@param diff table  vimtable.Diff
---@param st vault.GridEditorState
---@param bufnr integer
local function snapshot_for_undo(diff, st, bufnr)
  local files = {}
  for _, upd in ipairs(diff.updates) do
    local path = st.note_paths[upd.id]
    if path and vim.fn.filereadable(path) == 1 then
      files[path] = vim.fn.readfile(path)
    end
  end
  local deleted_paths = {} --- @type table<string, string>  slug → path
  for _, slug in ipairs(diff.deletes) do
    local path = st.note_paths[slug]
    if path and vim.fn.filereadable(path) == 1 then
      files[path] = vim.fn.readfile(path)
      deleted_paths[slug] = path
    end
  end
  -- Snapshot wikilink targets for renames
  if diff.custom then
    for _, c in ipairs(diff.custom) do
      if c.type == "rename" and c.extra then
        local old_path = st.note_paths[c.extra.old_slug]
        if old_path and vim.fn.filereadable(old_path) == 1 then
          files[old_path] = vim.fn.readfile(old_path)
        end
        local scanner = require("vault.scanner")
        local paths = scanner.paths()
        local old_stem = old_path and vim.fn.fnamemodify(old_path, ":t:r") or nil
        local esc_slug = vim.pesc(c.extra.old_slug)
        -- Only build stem pattern if stem is valid (non-nil, non-empty)
        local esc_stem = (old_stem and old_stem ~= "") and vim.pesc(old_stem) or nil
        for _, entry in pairs(paths) do
          local np = entry.path
          if not files[np] and vim.fn.filereadable(np) == 1 then
            local f = io.open(np, "r")
            if f then
              local content = f:read("*all")
              f:close()
              local has_link = content:match("%[%[" .. esc_slug)
              if not has_link and esc_stem then
                has_link = content:match("%[%[" .. esc_stem)
              end
              if has_link then
                files[np] = vim.split(content, "\n", { plain = true })
              end
            end
          end
        end
      end
    end
  end
  --- @type vault.ProcessUndoSnapshot
  local payload = {
    files = files,
    created_paths = {},
    deleted_paths = deleted_paths,
    renames = {},
    timestamp = os.time(),
    description = string.format("%d updates, %d deletes, %d creates, %d renames",
      #diff.updates, #diff.deletes, #diff.creates,
      diff.custom and #diff.custom or 0),
  }
  vt_undo.snapshot(bufnr, payload)
  return payload
end

-- ─── Mutation engine ──────────────────────────────────────────────────────────

---@param diff table
---@param st vault.GridEditorState
---@param undo_payload? vault.ProcessUndoSnapshot  Live undo payload to append created_paths/renames
---@return integer, integer, integer
local function apply_mutations(diff, st, undo_payload)
  local n_updates, n_deletes, n_creates = 0, 0, 0
  local empty = get_empty_cell()

  -- Updates
  for _, upd in ipairs(diff.updates) do
    local path = st.note_paths[upd.id]
    if not path then goto continue end
    local safe_path, path_err = validate_path_in_vault(path)
    if not safe_path then
      log.error("SAFETY: Skipping update — %s", path_err); goto continue
    end
    path = safe_path
    local snap_mtime = st.note_mtimes and st.note_mtimes[upd.id] or 0
    if snap_mtime > 0 and get_mtime(path) > snap_mtime then
      log.warn("SAFETY: Skipping %s — file modified externally", upd.id); goto continue
    end
    -- Dir move
    if upd.fields.dir ~= nil or upd.fields["file.folder"] ~= nil then
      local new_dir = upd.fields.dir or upd.fields["file.folder"] or ""
      if type(new_dir) ~= "string" then new_dir = "" end
      if new_dir == "/" then new_dir = "" end
      if new_dir:match("%.%.") then
        log.error("SAFETY: Refusing move with '..': %s", new_dir); goto continue
      end
      -- Ensure trailing / on non-empty dir
      if new_dir ~= "" and not new_dir:match("/$") then
        new_dir = new_dir .. "/"
      end
      local config = require("vault.config")
      local basename = vim.fn.fnamemodify(path, ":t")
      local new_path = config.options.root .. "/" .. new_dir .. basename
      if new_path ~= path then
        local move_ok = pcall(function()
          local Note = require("vault.notes.note")
          local note = Note(path)
          note:move(new_path, false, false, { silent = true })
        end)
        if move_ok then
          st.note_paths[upd.id] = new_path
          path = new_path
        end
      end
    end
    -- file.body write
    if upd.fields["file.body"] ~= nil then
      local new_body = upd.fields["file.body"] or ""
      local ok_read, file_lines = pcall(vim.fn.readfile, path)
      if ok_read and file_lines then
        local fm_end = 0
        if file_lines[1] and file_lines[1]:match("^%-%-%-") then
          for i = 2, #file_lines do
            if file_lines[i]:match("^%-%-%-") then fm_end = i; break end
          end
        end
        local new_lines = {}
        for i = 1, fm_end do table.insert(new_lines, file_lines[i]) end
        table.insert(new_lines, new_body)
        table.insert(new_lines, "")
        atomic_writefile(path, new_lines)
      end
    end
    -- Other fields (batched frontmatter write)
    local fm_fields = {}
    for col, new_val in pairs(upd.fields) do
      if col ~= "dir" and col ~= "file.folder" and col ~= "file.body" then
        fm_fields[col] = new_val
      end
    end
    if next(fm_fields) then set_frontmatter_fields(path, fm_fields) end
    n_updates = n_updates + 1
    ::continue::
  end

  -- Deletes
  for _, slug in ipairs(diff.deletes) do
    local path = st.note_paths[slug]
    if path then
      local safe_del, del_err = validate_path_in_vault(path)
      if not safe_del then
        log.error("SAFETY: Skipping delete — %s", del_err); goto del_continue
      end
      local del_ok = pcall(function()
        local Note = require("vault.notes.note")
        local note = Note(safe_del)
        note:delete(false, false)
      end)
      if del_ok then
        n_deletes = n_deletes + 1
      else
        log.error("Delete failed for: %s", slug)
      end
    end
    ::del_continue::
  end

  -- Creates
  for _, create in ipairs(diff.creates) do
    local raw_slug = create.fields.slug
    local title = create.fields.title
    local source = raw_slug and raw_slug ~= "" and raw_slug ~= empty and raw_slug
      or title and title ~= "" and title ~= empty and title
      or nil
    if not source then goto cr_continue end
    local slug = source:lower():gsub("%s+", "-"):gsub("[%c%[%]#|^]", "")
    if slug == "" then slug = "untitled" end
    local config = require("vault.config")
    local dir = create.fields.dir or create.fields["file.folder"] or ""
    if type(dir) ~= "string" then dir = "" end
    if dir == "/" then dir = "" end
    if dir:match("%.%.") then
      log.error("SAFETY: Refusing create with '..': %s", dir); goto cr_continue
    end
    -- Ensure trailing / on non-empty dir
    if dir ~= "" and not dir:match("/$") then
      dir = dir .. "/"
    end
    local base_slug = slug
    local path = config.options.root .. "/" .. dir .. slug .. config.options.ext
    local counter = 1
    while vim.fn.filereadable(path) == 1 do
      slug = base_slug .. "-" .. counter
      path = config.options.root .. "/" .. dir .. slug .. config.options.ext
      counter = counter + 1
      if counter > 100 then
        log.error("Too many slug collisions for: %s", base_slug); goto cr_continue
      end
    end
    local safe_create, create_err = validate_path_in_vault(path)
    if not safe_create then
      log.error("SAFETY: Skipping create — %s", create_err); goto cr_continue
    end
    local fm = { "---" }
    if create.fields.title then
      table.insert(fm, "title: " .. yaml_quote(create.fields.title))
    end
    local skip_fields = { slug = true, title = true, dir = true, tags = true, ["file.folder"] = true }
    for col, val in pairs(create.fields) do
      if not skip_fields[col] and val ~= nil then
        if type(val) == "table" then
          table.insert(fm, col .. ":")
          for _, v in ipairs(val) do table.insert(fm, "  - " .. yaml_quote(tostring(v))) end
        else
          table.insert(fm, col .. ": " .. yaml_quote(tostring(val)))
        end
      end
    end
    if create.fields.tags and type(create.fields.tags) == "table" then
      table.insert(fm, "tags:")
      for _, t in ipairs(create.fields.tags) do table.insert(fm, "  - " .. yaml_quote(t)) end
    end
    table.insert(fm, "---")
    table.insert(fm, "")
    local parent = vim.fn.fnamemodify(safe_create, ":h")
    if vim.fn.isdirectory(parent) == 0 then vim.fn.mkdir(parent, "p") end
    local write_ok = atomic_writefile(safe_create, fm)
    if write_ok then
      if undo_payload then
        table.insert(undo_payload.created_paths, safe_create)
      end
      -- Register created note so M.reload() can find it.
      -- The slug key is dir + deduped slug (the relative path stem).
      local created_slug = dir .. slug
      st.note_paths[created_slug] = safe_create
      n_creates = n_creates + 1
    end
    ::cr_continue::
  end

  return n_updates, n_deletes, n_creates
end

-- ─── Save handler (on_save callback for Grid) ────────────────────────────────

---@param st vault.GridEditorState
---@return fun(diff: table, done: fun(err: string|nil))
local function make_on_save(st)
  return function(diff, done)
    local bufnr = st.grid:bufnr()
    st.saving = true

    -- ── Validation warnings ──
    if #diff.errors > 0 then
      log.warn("%d edit(s) ignored: %s", #diff.errors,
        diff.errors[1].reason .. " on " .. (diff.errors[1].field or "?"))
    end

    -- Extract renames from diff.custom
    local renames = {}
    local other_custom = {}
    for _, c in ipairs(diff.custom or {}) do
      if c.type == "rename" and c.extra then
        table.insert(renames, c.extra)
      else
        table.insert(other_custom, c)
      end
    end

    local total = #diff.updates + #diff.deletes + #diff.creates + #renames
    if total == 0 then
      st.saving = false
      done(nil)
      return
    end

    -- ── Snapshot for undo ──
    local undo_payload = snapshot_for_undo(diff, st, bufnr)

    -- ── Hard cap on creates ──
    if #diff.creates > CREATE_HARD_CAP then
      log.error("SAFETY: Refusing %d creates (cap %d). Applying updates only.", #diff.creates, CREATE_HARD_CAP)
      diff.creates = {}
      diff.deletes = {}
    end

    -- ── Suspicious create+delete pairing ──
    -- When create and delete counts match (≤5 each), they are likely extmark
    -- drift artifacts (identity lost → looks like a create + a delete). Pair
    -- them as updates to the deleted slug's record instead.
    if #diff.creates > 0 and #diff.deletes > 0 then
      local n_paired = #diff.creates
      if n_paired <= 5 and #diff.deletes <= 5 and n_paired == #diff.deletes then
        for i, cr in ipairs(diff.creates) do
          local del_slug = diff.deletes[i]
          if del_slug then
            -- Strip identity/structural fields that should not be written to
            -- frontmatter — they are part of the file identity, not metadata.
            local safe_fields = {}
            local skip = { slug = true, ["file.slug"] = true, ["file.name"] = true,
                           ["file.folder"] = true, ["file.path"] = true, dir = true }
            for k, v in pairs(cr.fields) do
              if not skip[k] then safe_fields[k] = v end
            end
            table.insert(diff.updates, { id = del_slug, fields = safe_fields })
          end
        end
        diff.creates = {}
        diff.deletes = {}
        log.info("Paired %d create+delete as edits", n_paired)
      else
        log.warn("SAFETY: %d creates + %d deletes — applying updates only",
          #diff.creates, #diff.deletes)
        diff.creates = {}
        diff.deletes = {}
      end
    end

    -- ── Process renames ──
    local n_renamed, n_patched = 0, 0
    if #renames > 0 then
      local Note = require("vault.notes.note")
      local config = require("vault.config")
      local vault_root = vim.fn.expand(config.options.root or "")
      for _, ren in ipairs(renames) do
        local old_path = st.note_paths[ren.old_slug]
        if not old_path then goto skip_ren end
        local new_path = vault_root .. "/" .. ren.new_slug .. ".md"
        if ren.new_slug:match("%.%.") then
          log.error("SAFETY: Refusing rename '%s' — '..'", ren.new_slug); goto skip_ren
        end
        if vim.fn.filereadable(new_path) == 1 and old_path ~= new_path then
          log.error("SAFETY: Cannot rename to '%s' — exists", ren.new_slug); goto skip_ren
        end
        local ok, note = pcall(Note, old_path)
        if ok and note then
          local move_ok, result = pcall(note.move, note, new_path, false, false, { silent = true })
          if move_ok then
            n_patched = n_patched + (result or 0)
            if undo_payload then
              table.insert(undo_payload.renames, { old_path = old_path, new_path = new_path })
            end
            st.note_paths[ren.new_slug] = new_path
            st.note_paths[ren.old_slug] = nil
            if st.note_mtimes then
              st.note_mtimes[ren.new_slug] = st.note_mtimes[ren.old_slug]
              st.note_mtimes[ren.old_slug] = nil
            end
            -- Remap any pending updates from old_slug to new_slug so they
            -- can find the path after rename.
            for _, upd in ipairs(diff.updates) do
              if upd.id == ren.old_slug then upd.id = ren.new_slug end
            end
            n_renamed = n_renamed + 1
          else
            log.error("Rename '%s' failed: %s", ren.old_slug, tostring(result))
          end
        end
        ::skip_ren::
      end
    end

    -- ── Handle deletes ──
    if #diff.deletes > 0 and #diff.deletes > DELETE_HARD_CAP then
      log.error("SAFETY: Refusing %d deletes (cap %d)", #diff.deletes, DELETE_HARD_CAP)
      diff.deletes = {}
    end

    local function finish_save()
      local n_u, n_d, n_c = apply_mutations(diff, st, undo_payload)
      local parts = {}
      if n_renamed > 0 then
        local msg = string.format("%d renamed", n_renamed)
        if n_patched > 0 then msg = msg .. string.format(" (%d patched)", n_patched) end
        table.insert(parts, msg)
      end
      if n_u > 0 then table.insert(parts, string.format("%d updated", n_u)) end
      if n_d > 0 then table.insert(parts, string.format("%d trashed", n_d)) end
      if n_c > 0 then table.insert(parts, string.format("%d created", n_c)) end
      if #parts == 0 then parts = { "no changes" } end
      log.info("Saved: %s", table.concat(parts, ", "))
      st.saving = false
      done(nil)
      -- Reload the grid to rebuild snapshot from current state.
      -- Without this, incremental saves compare against the stale
      -- snapshot and re-detect already-applied changes.
      M.reload(bufnr)
    end

    if #diff.deletes > 0 then
      -- Confirmation for deletes
      local confirm_ui = require("vault.ui.confirm")
      local preview = {}
      for i = 1, math.min(10, #diff.deletes) do
        table.insert(preview, "  - " .. diff.deletes[i])
      end
      if #diff.deletes > 10 then
        table.insert(preview, string.format("  ... and %d more", #diff.deletes - 10))
      end
      confirm_ui.select({
        message = string.format(
          "Vault: About to TRASH %d note%s:\n%s\n\n%d updated, %d created.\n\nProceed?",
          #diff.deletes, #diff.deletes == 1 and "" or "s",
          table.concat(preview, "\n"), #diff.updates, #diff.creates),
        title = "Vault Process (grid)",
        choices = {
          { key = "y", label = "Yes, trash them", action = finish_save },
          { key = "n", label = "No, skip deletes", action = function()
            diff.deletes = {}
            finish_save()
          end },
          { key = "c", label = "Cancel", action = function()
            st.saving = false
            done(nil)
          end },
        },
        on_cancel = function()
          st.saving = false
          done(nil)
        end,
      })
    else
      finish_save()
    end
  end
end

-- ─── Reload ───────────────────────────────────────────────────────────────────

---@param bufnr integer
function M.reload(bufnr)
  local st = buf_states[bufnr]
  if not st then return end
  EMPTY_CELL = nil; get_empty_cell()

  local Note = require("vault.notes.note")
  local notes_map = {}
  local dead_slugs = {}
  for slug, path in pairs(st.note_paths) do
    if vim.fn.filereadable(path) == 1 then
      local ok, note = pcall(Note, path)
      if ok and note then notes_map[slug] = note end
    else
      table.insert(dead_slugs, slug)
    end
  end
  for _, slug in ipairs(dead_slugs) do
    st.note_paths[slug] = nil
    if st.note_mtimes then st.note_mtimes[slug] = nil end
  end

  local records = build_records(notes_map, st.columns, st.base)
  -- Rebuild note_paths from records
  st.note_paths = {}
  st.note_mtimes = {}
  for _, rec in ipairs(records) do
    st.note_paths[rec.slug] = rec._path
    st.note_mtimes[rec.slug] = get_mtime(rec._path)
  end

  st.grid:reload(records)
end

-- ─── Undo ─────────────────────────────────────────────────────────────────────

--- Apply an undo snapshot (internal — used by both M.undo and on_undo callback).
---
---@param bufnr integer
---@param snap vault.ProcessUndoSnapshot
function M._apply_undo(bufnr, snap)
  local uv = vim.uv or vim.loop
  local restored, deleted, renames_reversed = 0, 0, 0
  if snap.renames then
    for _, ren in ipairs(snap.renames) do
      if vim.fn.filereadable(ren.new_path) == 1 then
        local ok = uv.fs_rename(ren.new_path, ren.old_path)
        if ok then renames_reversed = renames_reversed + 1
        else log.error("Failed to reverse rename %s → %s", ren.new_path, ren.old_path) end
      end
    end
  end
  for path, original_lines in pairs(snap.files) do
    local ok = atomic_writefile(path, original_lines)
    if ok then restored = restored + 1
    else log.error("Failed to restore %s", path) end
  end
  if snap.created_paths then
    for _, path in ipairs(snap.created_paths) do
      if vim.fn.filereadable(path) == 1 then
        vim.fn.delete(path)
        deleted = deleted + 1
      end
    end
  end
  -- Re-register deleted note paths so M.reload can find them
  local st = buf_states[bufnr]
  if st and snap.deleted_paths then
    for slug, path in pairs(snap.deleted_paths) do
      if vim.fn.filereadable(path) == 1 then
        st.note_paths[slug] = path
      end
    end
  end
  local parts = {}
  if restored > 0 then table.insert(parts, string.format("restored %d", restored)) end
  if deleted > 0 then table.insert(parts, string.format("removed %d created", deleted)) end
  if renames_reversed > 0 then table.insert(parts, string.format("reversed %d rename(s)", renames_reversed)) end
  log.info("Undo: %s", #parts > 0 and table.concat(parts, ", ") or "nothing to undo")
  M.reload(bufnr)
end

---@param bufnr? integer
function M.undo(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local snap = vt_undo.restore(bufnr)
  if not snap then
    log.warn("No undo snapshot available")
    return
  end
  M._apply_undo(bufnr, snap)
end

-- ─── Partial save ─────────────────────────────────────────────────────────────

---@param bufnr integer
---@param start_row integer  0-indexed inclusive
---@param end_row integer    0-indexed inclusive
function M.save_range(bufnr, start_row, end_row)
  local st = buf_states[bufnr]
  if not st or st.saving then return end
  st.saving = true

  local grid = st.grid
  local diff = grid:diff()

  -- Filter updates to only rows in range by checking line identity
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local render = require("vimtable.views.grid.render")
  local vt_id = require("vimtable.identity")
  local id_opts = { separator = render.SEP_CHAR }
  local selected_ids = {}
  local header_lines = grid:state().header_lines
  for row = start_row, end_row do
    if row >= header_lines then
      local line = lines[row + 1]
      if line then
        local id = vt_id.parse(line, id_opts)
        if id then selected_ids[id] = true end
      end
    end
  end

  local filtered = {}
  for _, upd in ipairs(diff.updates) do
    if selected_ids[upd.id] then table.insert(filtered, upd) end
  end
  if #filtered == 0 then
    log.info("No changes in selected range")
    st.saving = false
    return
  end

  local partial = { updates = filtered, deletes = {}, creates = {}, custom = {}, errors = {} }
  local undo_payload = snapshot_for_undo(partial, st, bufnr)
  local n_u = apply_mutations(partial, st, undo_payload)
  log.info("Partial save: %d updated", n_u)
  vim.schedule(function()
    M.reload(bufnr)
    st.saving = false
  end)
end

-- ─── Sort helpers ─────────────────────────────────────────────────────────────

---@param bufnr integer
---@param col_name string
---@param add_secondary? boolean
function M.cycle_sort(bufnr, col_name, add_secondary)
  local st = buf_states[bufnr]
  if not st then return end
  st.grid:cycle_sort(col_name, add_secondary)
end

---@param bufnr? integer
function M.sort_by_cursor(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local st = buf_states[bufnr]
  if not st then return end
  st.grid:sort_by_cursor()
end

---@param bufnr integer
---@param col_name string
---@param delta integer
function M.resize_column(bufnr, col_name, delta)
  local st = buf_states[bufnr]
  if not st then return end
  st.grid:resize_column(col_name, delta)
end

---@param bufnr? integer
---@param delta integer
function M.resize_cursor_column(bufnr, delta)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local st = buf_states[bufnr]
  if not st then return end
  st.grid:resize_cursor_column(delta)
end

---@param bufnr integer
---@param col_name string
---@param direction integer
function M.move_column(bufnr, col_name, direction)
  local st = buf_states[bufnr]
  if not st then return end
  st.grid:move_column(col_name, direction)
end

---@param bufnr? integer
---@param direction integer
function M.move_cursor_column(bufnr, direction)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local st = buf_states[bufnr]
  if not st then return end
  st.grid:move_cursor_column(direction)
end

-- ─── Open ─────────────────────────────────────────────────────────────────────

---@param opts? { notes?: vault.Notes, columns?: string[], filter_desc?: string, base?: vault.Base, group_by?: string }
function M.open(opts)
  opts = opts or {}
  get_empty_cell()

  local win = vim.api.nvim_get_current_win()
  if vim.wo[win].winfixbuf then vim.wo[win].winfixbuf = false end

  local base = opts.base
  local display_names = {}
  local formula_cols = {}
  local filter_desc = opts.filter_desc or "all notes"
  local visible_columns

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
    for i, c in ipairs(visible_columns) do visible_columns[i] = normalize_col(c) end
    for _, c in ipairs(visible_columns) do
      if READONLY_FILE_COLS[c] then table.insert(formula_cols, c) end
    end
    local has_slug = false
    for _, c in ipairs(visible_columns) do
      if c == "slug" then has_slug = true; break end
    end
    columns = vim.list_slice(visible_columns, 1)
    if not has_slug then table.insert(columns, 1, "slug") end
  end

  -- Prevent duplicates
  for bufnr, s in pairs(buf_states) do
    if vim.api.nvim_buf_is_valid(bufnr) then
      if s.filter_desc == filter_desc then
        vim.api.nvim_set_current_buf(bufnr)
        log.info("Switched to existing grid process buffer (%s)", filter_desc)
        return
      end
    else
      buf_states[bufnr] = nil
    end
  end

  -- Get notes
  local notes
  if opts.notes then notes = opts.notes
  else notes = require("vault.notes")() end
  local notes_map = notes.map or {}
  if base and base:has_filters() then notes_map = base:match_notes(notes_map) end
  if not next(notes_map) then
    log.info("No notes match%s", base and (" base '" .. base.data.name .. "'") or "")
    return
  end

  -- Build records
  local records = build_records(notes_map, columns, base)

  -- Determine slug_hidden
  local slug_hidden = true
  for _, c in ipairs(visible_columns) do
    if c == "slug" then slug_hidden = false; break end
  end

  -- Build grid.Column[] from visible columns
  local grid_columns = build_grid_columns(visible_columns, display_names, formula_cols)

  -- Prepare state (pre-grid — we need it for make_classify and make_on_save)
  ---@type vault.GridEditorState
  local st = {
    grid = nil, --- set below
    note_paths = {},
    note_mtimes = {},
    base = base,
    filter_desc = filter_desc,
    columns = columns,
    visible_columns = visible_columns,
    display_names = display_names,
    formula_cols = formula_cols,
    slug_hidden = slug_hidden,
    saving = false,
  }
  for _, rec in ipairs(records) do
    st.note_paths[rec.slug] = rec._path
    st.note_mtimes[rec.slug] = get_mtime(rec._path)
  end

  -- Initial sort from base
  local initial_sort = base and sort_from_base(base) or nil
  local sort_keys --- @type table[]|nil
  if initial_sort then
    sort_keys = { initial_sort }
  end

  -- Row highlight groups + callback
  ensure_row_hl_groups()
  local row_hl_fn = build_row_hl()

  -- Group-by from base definition or command opts
  local group_by = opts.group_by or (base and group_by_from_base(base)) or nil

  -- Create Grid
  local Grid = get_Grid()
  local grid = Grid.new({
    columns = grid_columns,
    records = records,
    id_field = "slug",
    header = "winbar",
    identity = slug_hidden and "conceal" or "visible",
    separator = "\x1f",
    empty_cell = get_empty_cell(),
    buf_name = "vault://grid-process/" .. filter_desc:gsub("%s+", "-"),
    filetype = "vault_process",
    on_save = make_on_save(st),
    on_undo = function(payload, done)
      -- payload is already popped from vt_undo by Grid's gu handler
      M._apply_undo(st.grid:bufnr(), payload)
      done(nil)
    end,
    on_refresh = function(g)
      M.reload(g:bufnr())
    end,
    on_filter_request = function(g)
      local s = buf_states[g:bufnr()]
      if not s then return end
      local picker = require("vault.bases.views.filter_picker")
      picker.open(g, s.visible_columns)
    end,
    keymaps = {
      refresh = "gR",  -- vault uses gR instead of default <C-r>
    },
    classify = make_classify(st),
    sort_keys = sort_keys,
    row_hl = row_hl_fn,
    group_by = group_by,
    hl = {
      header = "VaultProcessHeader",
      separator = "VaultProcessSep",
      readonly = "VaultProcessFormula",
      validation_error = "VaultProcessValidationErr",
    },
  })
  st.grid = grid
  local bufnr = grid:bufnr()
  buf_states[bufnr] = st

  -- Attach to current window
  grid:attach()

  -- Disable auto-formatters for this buffer
  vim.b[bufnr].formatter_skip_buf = true   -- formatter.nvim
  vim.b[bufnr].autoformat         = false  -- conform.nvim

  -- Allow :q without "no write" error when there are no real changes
  vim.api.nvim_create_autocmd("QuitPre", {
    buffer = bufnr,
    callback = function()
      local s = buf_states[bufnr]
      if not s then
        vim.bo[bufnr].modified = false
        return
      end
      local diff = s.grid:diff()
      local total = #diff.updates + #diff.deletes + #diff.creates + #(diff.custom or {})
      if total == 0 then
        vim.bo[bufnr].modified = false
      end
    end,
  })

  -- Cleanup on buffer delete
  vim.api.nvim_create_autocmd("BufDelete", {
    buffer = bufnr,
    callback = function()
      buf_states[bufnr] = nil
      vt_undo.clear(bufnr)
    end,
  })

  -- Buffer-local keymaps (vault-specific only; gs, gS, gR, gf, gF, g>, g<, o, <C-s> handled by Grid)
  local kopts = { buffer = bufnr, silent = true }
  -- Note: `gu` keymap is handled by vimtable Grid via on_undo callback
  vim.keymap.set("n", "u", function()
    local tree = vim.fn.undotree()
    if #tree.entries > 0 then
      vim.cmd("undo")
    elseif vt_undo.has(bufnr) then
      M.undo(bufnr)
    else
      log.info("Nothing to undo")
    end
  end, vim.tbl_extend("force", kopts, { desc = "Vault: smart undo" }))
  vim.keymap.set("n", "J", function()
    local row = vim.api.nvim_win_get_cursor(0)[1] - 1
    local line_count = vim.api.nvim_buf_line_count(bufnr)
    if row + 1 >= line_count then log.warn("No next line to merge with"); return end
    local render = require("vimtable.views.grid.render")
    local vt_id = require("vimtable.identity")
    local id_opts = { separator = render.SEP_CHAR }
    local lines = vim.api.nvim_buf_get_lines(bufnr, row, row + 2, false)
    local slug_a = lines[1] and vt_id.parse(lines[1], id_opts)
    local slug_b = lines[2] and vt_id.parse(lines[2], id_opts)
    if not slug_a or not slug_b then log.warn("Cannot determine note identity for merge"); return end
    local path_a, path_b = st.note_paths[slug_a], st.note_paths[slug_b]
    if not path_a or not path_b then log.warn("Cannot find note paths for merge"); return end
    require("vault.merge").merge(path_a, path_b, {
      bufnr = bufnr,
      on_done = function() M.reload(bufnr) end,
    })
  end, vim.tbl_extend("force", kopts, { desc = "Vault: merge next note into current" }))
  vim.keymap.set("n", "gJ", function()
    local row = vim.api.nvim_win_get_cursor(0)[1] - 1
    local render = require("vimtable.views.grid.render")
    local vt_id = require("vimtable.identity")
    local id_opts = { separator = render.SEP_CHAR }
    local line = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1]
    local slug_a = line and vt_id.parse(line, id_opts)
    if not slug_a then log.warn("Cannot determine note identity"); return end
    local path_a = st.note_paths[slug_a]
    if not path_a then log.warn("Cannot find path for current note"); return end
    local scoring = require("vault.scoring")
    local snap = grid:state().snapshot
    local snap_a = snap.data and snap.data[slug_a]
    local tags_a = {}
    if snap_a and snap_a.tags then
      if type(snap_a.tags) == "string" and snap_a.tags ~= "" and snap_a.tags ~= get_empty_cell() then
        tags_a = vim.split(snap_a.tags, ",")
        for i, t in ipairs(tags_a) do tags_a[i] = vim.trim(t) end
      end
    end
    local candidates = {}
    for slug, path in pairs(st.note_paths) do
      if slug ~= slug_a then
        local snap_c = snap.data and snap.data[slug]
        local tags = {}
        if snap_c and snap_c.tags then
          if type(snap_c.tags) == "string" and snap_c.tags ~= "" and snap_c.tags ~= get_empty_cell() then
            tags = vim.split(snap_c.tags, ",")
            for i, t in ipairs(tags) do tags[i] = vim.trim(t) end
          end
        end
        table.insert(candidates, { slug = slug, path = path, tags = tags })
      end
    end
    local scored = scoring.score_merge_candidates(slug_a, tags_a, candidates, { limit = 200 })
    local ok_tele = pcall(function()
      local actions      = require("telescope.actions")
      local action_state = require("telescope.actions.state")
      local finders      = require("telescope.finders")
      local pickers      = require("telescope.pickers")
      local sorters      = require("telescope.sorters")
      local conf         = require("telescope.config").values
      pickers.new({}, {
        prompt_title = string.format("Merge into: %s <- ?", slug_a),
        finder = finders.new_table({
          results = scored,
          entry_maker = function(e)
            local pct = math.floor(e.score * 100 + 0.5)
            return {
              value = e,
              display = pct > 0 and string.format("%s (%d%%)", e.slug, pct) or e.slug,
              ordinal = e.slug,
              path = e.path,
              filename = e.path,
            }
          end,
        }),
        sorter = sorters.get_fuzzy_file(),
        previewer = conf.file_previewer({}),
        attach_mappings = function(prompt_bufnr)
          actions.select_default:replace(function()
            actions.close(prompt_bufnr)
            local sel = action_state.get_selected_entry()
            if not sel then return end
            require("vault.merge").merge(path_a, sel.value.path, {
              bufnr = bufnr,
              on_done = function() M.reload(bufnr) end,
            })
          end)
          return true
        end,
      }):find()
    end)
    if not ok_tele then log.warn("gJ requires telescope.nvim") end
  end, vim.tbl_extend("force", kopts, { desc = "Vault: pick note to merge" }))
  -- gf, gF, g>, g< handled by Grid._setup_shared_keymaps
  vim.keymap.set("n", "g}", function() M.move_cursor_column(bufnr, 1) end,
    vim.tbl_extend("force", kopts, { desc = "Vault: move column right" }))
  vim.keymap.set("n", "g{", function() M.move_cursor_column(bufnr, -1) end,
    vim.tbl_extend("force", kopts, { desc = "Vault: move column left" }))
  vim.keymap.set("v", "<C-s>", function()
    local sr = vim.fn.line("'<") - 1
    local er = vim.fn.line("'>") - 1
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "n", false)
    M.save_range(bufnr, sr, er)
  end, vim.tbl_extend("force", kopts, { desc = "Vault: save selected rows only" }))
  vim.keymap.set("n", "gp", function() M.toggle_preview(bufnr) end,
    vim.tbl_extend("force", kopts, { desc = "Vault: toggle note preview on hover" }))
  vim.keymap.set("v", "g=", function()
    -- Exit visual mode first so '< '> marks are set
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "n", false)
    vim.schedule(function()
      local sr = vim.fn.line("'<") - 1
      local er = vim.fn.line("'>") - 1
      vim.ui.input({ prompt = "Set status: " }, function(value)
        if not value or value == "" then return end
        M.batch_set_field(bufnr, "status", value, sr, er)
      end)
    end)
  end, vim.tbl_extend("force", kopts, { desc = "Vault: batch set status on selection" }))
  vim.keymap.set("v", "gt", function()
    -- Exit visual mode first so '< '> marks are set
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "n", false)
    vim.schedule(function()
      local sr = vim.fn.line("'<") - 1
      local er = vim.fn.line("'>") - 1
      vim.ui.input({ prompt = "Add tag: " }, function(tag)
        if not tag or tag == "" then return end
        M.batch_append_tag(bufnr, tag, sr, er)
      end)
    end)
  end, vim.tbl_extend("force", kopts, { desc = "Vault: batch add tag to selection" }))

  -- Help legend
  require("vimtable.help").setup_keymap(bufnr, {
    { group = "Navigation",    lhs = "h / l",       desc = "Column left / right" },
    { lhs = "j / k",          desc = "Row up / down" },
    { lhs = "g> / g<",        desc = "Resize column wider / narrower" },
    { lhs = "g} / g{",        desc = "Move column right / left" },
    { group = "Saving",        lhs = ":w / <C-s>",  desc = "Save all changes" },
    { lhs = "<C-s> (visual)",  desc = "Save selected rows only" },
    { group = "Undo",          lhs = "u / gu",      desc = "Undo (vim / plugin-level)" },
    { group = "Sort",          lhs = "gs",           desc = "Cycle sort on column" },
    { lhs = "gS",              desc = "Add secondary sort key" },
    { group = "Filter",        lhs = "gf",           desc = "Open filter picker" },
    { lhs = "gF",              desc = "Clear all filters" },
    { group = "Merge",         lhs = "J",            desc = "Merge next note into current" },
    { lhs = "gJ",              desc = "Pick note to merge (Telescope)" },
    { group = "Batch ops",     lhs = "g= (visual)", desc = "Set status on selection" },
    { lhs = "gt (visual)",     desc = "Add tag to selection" },
    { group = "Reload",        lhs = "gR",           desc = "Reload buffer" },
    { group = "Preview",       lhs = "gp",           desc = "Toggle note preview on hover" },
    { group = "Detail",        lhs = "gd",           desc = "Open note detail form" },
    { group = "Help",          lhs = "g?",           desc = "Toggle this help" },
  })

  local sort_desc = initial_sort
    and string.format(", sorted by %s %s", initial_sort.col, initial_sort.dir)
    or ""
  log.info(
    "Processing %d notes (%s)%s [grid] — :w to apply, gs/gS to sort, gu to undo, g>/g< to resize",
    #records, filter_desc, sort_desc
  )
end

-- ─── Inline note preview (CursorHold float) ──────────────────────────────────

local PREVIEW_MAX_LINES = 15
local PREVIEW_MAX_WIDTH = 80

--- Close the preview float if it exists.
---@param st vault.GridEditorState
local function close_preview(st)
  if st._preview_win and vim.api.nvim_win_is_valid(st._preview_win) then
    vim.api.nvim_win_close(st._preview_win, true)
  end
  st._preview_win = nil
  st._preview_slug = nil
end

--- Show a floating preview of the note under the cursor.
---@param bufnr integer
---@param st vault.GridEditorState
local function show_preview(bufnr, st)
  if not st.grid then return end
  local row = vim.api.nvim_win_get_cursor(0)[1] - 1
  local header_lines = st.grid:state().header_lines
  if row < header_lines then close_preview(st); return end

  local line = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1]
  if not line then close_preview(st); return end

  local render = require("vimtable.views.grid.render")
  local vt_id = require("vimtable.identity")
  local slug = vt_id.parse(line, { separator = render.SEP_CHAR })
  if not slug then close_preview(st); return end

  -- Don't re-open for same slug
  if st._preview_slug == slug and st._preview_win
      and vim.api.nvim_win_is_valid(st._preview_win) then
    return
  end
  close_preview(st)

  local path = st.note_paths[slug]
  if not path then return end

  local ok, file_lines = pcall(vim.fn.readfile, path, "", PREVIEW_MAX_LINES)
  if not ok or #file_lines == 0 then return end

  -- Compute float size
  local width = 0
  for _, l in ipairs(file_lines) do
    local len = vim.fn.strdisplaywidth(l)
    if len > width then width = len end
  end
  width = math.min(width + 2, PREVIEW_MAX_WIDTH)
  width = math.max(width, 20)
  local height = math.min(#file_lines, PREVIEW_MAX_LINES)

  local preview_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(preview_buf, 0, -1, false, file_lines)
  vim.bo[preview_buf].modifiable = false
  vim.bo[preview_buf].bufhidden = "wipe"
  vim.bo[preview_buf].filetype = "markdown"

  local ui = vim.api.nvim_list_uis()[1] or { width = 120, height = 40 }
  local cursor_row = vim.api.nvim_win_get_cursor(0)[1]
  local anchor_row = cursor_row + 1
  local anchor_col = 2
  -- Flip above if not enough room below
  if anchor_row + height + 2 > ui.height then
    anchor_row = cursor_row - height - 2
    if anchor_row < 0 then anchor_row = 0 end
  end

  st._preview_win = vim.api.nvim_open_win(preview_buf, false, {
    relative = "win",
    win = vim.api.nvim_get_current_win(),
    width = width,
    height = height,
    row = anchor_row - cursor_row,
    col = anchor_col,
    style = "minimal",
    border = "rounded",
    title = " " .. slug .. " ",
    title_pos = "center",
    focusable = false,
    noautocmd = true,
  })
  st._preview_slug = slug
end

--- Toggle preview mode on/off for a grid buffer.
---@param bufnr integer
function M.toggle_preview(bufnr)
  local st = buf_states[bufnr]
  if not st then return end
  if st._preview_enabled then
    st._preview_enabled = false
    close_preview(st)
    if st._preview_augroup then
      pcall(vim.api.nvim_del_augroup_by_id, st._preview_augroup)
      st._preview_augroup = nil
    end
    log.info("Preview off")
  else
    st._preview_enabled = true
    local group = vim.api.nvim_create_augroup("vault_grid_preview_" .. bufnr, { clear = true })
    st._preview_augroup = group
    vim.api.nvim_create_autocmd("CursorHold", {
      group = group,
      buffer = bufnr,
      callback = function() show_preview(bufnr, st) end,
    })
    vim.api.nvim_create_autocmd({ "CursorMoved", "InsertEnter", "BufLeave" }, {
      group = group,
      buffer = bufnr,
      callback = function() close_preview(st) end,
    })
    log.info("Preview on (CursorHold)")
    -- Show immediately for current position
    show_preview(bufnr, st)
  end
end

-- ─── Batch operations (visual selection) ──────────────────────────────────────

--- Collect note slugs and paths for a visual row range.
---@param bufnr integer
---@param start_row integer  0-indexed inclusive
---@param end_row integer    0-indexed inclusive
---@return { slug: string, path: string }[]
local function collect_row_identities(bufnr, start_row, end_row)
  local st = buf_states[bufnr]
  if not st or not st.grid then return {} end
  local grid = st.grid
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local render = require("vimtable.views.grid.render")
  local vt_id = require("vimtable.identity")
  local id_opts = { separator = render.SEP_CHAR }
  local header_lines = grid:state().header_lines
  local results = {}
  for row = start_row, end_row do
    if row >= header_lines then
      local line = lines[row + 1]
      if line then
        local slug = vt_id.parse(line, id_opts)
        if slug and st.note_paths[slug] then
          table.insert(results, { slug = slug, path = st.note_paths[slug] })
        end
      end
    end
  end
  return results
end

--- Batch-set a frontmatter field on all notes in a visual selection.
---@param bufnr integer
---@param field string   field name (e.g. "status")
---@param value string   value to set
---@param start_row integer  0-indexed inclusive
---@param end_row integer    0-indexed inclusive
function M.batch_set_field(bufnr, field, value, start_row, end_row)
  local targets = collect_row_identities(bufnr, start_row, end_row)
  if #targets == 0 then log.info("No notes in selection"); return end
  for _, t in ipairs(targets) do
    shared.set_frontmatter_fields(t.path, { [field] = value })
  end
  log.info("Set %s=%s on %d notes", field, value, #targets)
  M.reload(bufnr)
end

--- Batch-append a tag to all notes in a visual selection (deduplicates).
---@param bufnr integer
---@param tag string     tag to add (with or without # prefix)
---@param start_row integer  0-indexed inclusive
---@param end_row integer    0-indexed inclusive
function M.batch_append_tag(bufnr, tag, start_row, end_row)
  -- Normalize: strip leading # for storage
  tag = tag:gsub("^#", "")
  if tag == "" then log.warn("Empty tag"); return end
  local targets = collect_row_identities(bufnr, start_row, end_row)
  if #targets == 0 then log.info("No notes in selection"); return end
  for _, t in ipairs(targets) do
    local existing = shared.read_frontmatter_fields(t.path, { "tags" })
    local tags = existing.tags
    if type(tags) == "string" then
      tags = vim.split(tags, ",")
      for i, v in ipairs(tags) do tags[i] = vim.trim(v) end
    elseif type(tags) ~= "table" then
      tags = {}
    end
    -- Dedup: check if tag already present (normalize # prefix)
    local found = false
    for _, existing_tag in ipairs(tags) do
      if existing_tag:gsub("^#", "") == tag then found = true; break end
    end
    if not found then
      table.insert(tags, tag)
    end
    shared.set_frontmatter_fields(t.path, { tags = tags })
  end
  log.info("Added tag #%s to %d notes", tag, #targets)
  M.reload(bufnr)
end

-- ─── Debug / test exports ─────────────────────────────────────────────────────

M._buf_states = buf_states
M._vt_undo = vt_undo  -- for merge.lua and tests

-- Pure-function exports for unit testing (prefixed with _ to signal internal use)
M._normalize_col = shared.normalize_col
M._base_key_to_col = shared.base_key_to_col
M._columns_from_base = columns_from_base
M._yaml_quote = shared.yaml_quote
M._validate_path_in_vault = shared.validate_path_in_vault
M._fmt_value = shared.fmt_value
M._parse_value = shared.parse_value
M._make_classify = make_classify
M._build_records = build_records
M._build_grid_columns = build_grid_columns
M._sort_from_base = sort_from_base
M._atomic_writefile = shared.atomic_writefile
M._read_frontmatter_fields = shared.read_frontmatter_fields
M._set_frontmatter_field = shared.set_frontmatter_field
M._set_frontmatter_fields = shared.set_frontmatter_fields
M._snapshot_for_undo = snapshot_for_undo
M._apply_mutations = apply_mutations
M._make_on_save = make_on_save

return M
