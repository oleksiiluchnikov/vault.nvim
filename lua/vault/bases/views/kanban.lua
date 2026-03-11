-- lua/vault/bases/views/kanban.lua
-- Kanban board adapter for vault.nvim backed by vimtable.views.kanban.Board.
--
-- Provides a multi-column board view where notes are grouped by:
--   1. Frontmatter field value  (group_field = "status")
--   2. Tag prefix extraction    (group_field = "tags/status")
--   3. Directory path           (group_field = "directory")
--
-- Usage:
--   require("vault.bases.views.kanban").open({ group_field = "status" })
--   require("vault.bases.views.kanban").open({ base = base_obj })

local M = {}

local log = require("vault.log").scope("bases.views.kanban")
local shared = require("vault.views.shared")

-- ─── Lazy imports ─────────────────────────────────────────────────────────────

---@return table Board class
local function get_Board()
  return require("vimtable.views.kanban").Board
end

-- ─── Constants ────────────────────────────────────────────────────────────────

local DEFAULT_GROUP_FIELD = "status"
local DEFAULT_DISPLAY_FIELDS = { "title", "tags" }
local DEFAULT_RENDER_MODE = "card"

local DELETE_HARD_CAP = 100
local CREATE_HARD_CAP = 100

-- ─── Keyword-based value highlight ────────────────────────────────────────────

---@type table<string, string>
local STATUS_HL_KEYWORDS = {
  done       = "String",
  completed  = "String",
  complete   = "String",
  active     = "Function",
  ["in-progress"] = "Function",
  ["in progress"]  = "Function",
  started    = "Function",
  planned    = "Keyword",
  todo       = "Keyword",
  backlog    = "Comment",
  ["on-hold"]  = "WarningMsg",
  ["on hold"]  = "WarningMsg",
  blocked    = "ErrorMsg",
  cancelled  = "Comment",
  archived   = "Comment",
}

---@param text string
---@return string|nil hl_group
local function get_value_hl(text)
  if not text or text == "" then return nil end
  local lower = text:lower()
  return STATUS_HL_KEYWORDS[lower]
end

-- ─── Per-board state ──────────────────────────────────────────────────────────

---@class vault.GridKanbanState
---@field board table           Board instance
---@field note_paths table<string, string>  slug → absolute path
---@field note_mtimes table<string, integer>  slug → mtime at snapshot time
---@field base? vault.Base
---@field group_field string    Raw group_field spec ("status", "tags/status", "directory")
---@field group_mode "frontmatter"|"tag_prefix"|"directory"
---@field tag_prefix? string    For tag_prefix mode: the prefix part (e.g. "status")
---@field display_fields string[]
---@field columns string[]      All column names used in records
---@field filter_desc string
---@field notes_map table       Original notes map for refresh
---@field saving boolean

---@type table<string, vault.GridKanbanState>
local board_states = {}

-- ─── Group field resolution ───────────────────────────────────────────────────

---@class vault.KanbanGroupInfo
---@field mode "frontmatter"|"tag_prefix"|"directory"
---@field field_key string       Actual field key used in flat records
---@field tag_prefix? string     Tag prefix (only for tag_prefix mode)
---@field values string[]        Ordered group values derived from notes
---@field resolver? fun(record: table, field: string): string
---@field colors table<string, string>

--- Parse group_field spec and derive group values from notes.
---@param notes_map table<string, table>  slug → note
---@param group_field string  "status", "tags/prefix", or "directory"
---@param explicit_values? string[]  User-specified ordered values
---@return vault.KanbanGroupInfo
local function resolve_group_field(notes_map, group_field, explicit_values)
  local info = {
    mode = "frontmatter",
    field_key = group_field,
    values = {},
    colors = {},
  } ---@type vault.KanbanGroupInfo

  -- Detect mode from group_field spec
  if group_field == "directory" then
    info.mode = "directory"
    info.field_key = "_directory"
  elseif group_field:match("^tags/(.+)$") then
    info.mode = "tag_prefix"
    info.tag_prefix = group_field:match("^tags/(.+)$")
    info.field_key = "_tag_group"
  end

  -- Collect unique values from notes
  local seen = {}
  local ordered = {}

  for _, note in pairs(notes_map) do
    local value

    if info.mode == "frontmatter" then
      local fm = note.data and note.data.frontmatter or {}
      value = fm[group_field]
      if value == vim.NIL or type(value) == "userdata" then value = nil end
      if type(value) == "table" then value = value[1] end
      if value == nil or value == "" then value = "" end
      value = tostring(value)
      value = value:gsub("^%[%[(.-)%]%]$", "%1")

    elseif info.mode == "tag_prefix" then
      local tags = note.data and note.data.tags or {}
      if type(tags) == "table" then
        local prefix = info.tag_prefix .. "/"
        for _, tag in ipairs(tags) do
          local t = type(tag) == "string" and tag or tostring(tag)
          if t:sub(1, #prefix) == prefix then
            value = t:sub(#prefix + 1)
            break
          end
        end
      end
      if not value then value = "" end

    elseif info.mode == "directory" then
      local relpath = note.data and note.data.relpath or ""
      local dir = relpath:match("^(.-/)[^/]*$") or "/"
      value = dir
    end

    if not seen[value] then
      seen[value] = true
      table.insert(ordered, value)
    end
  end

  -- Use explicit values if provided, append any unseen values from data
  if explicit_values and #explicit_values > 0 then
    local ev_set = {}
    for _, v in ipairs(explicit_values) do ev_set[v] = true end
    info.values = vim.list_slice(explicit_values, 1)
    for _, v in ipairs(ordered) do
      if not ev_set[v] then table.insert(info.values, v) end
    end
  else
    table.sort(ordered)
    info.values = ordered
  end

  -- Build resolver for tag_prefix and directory modes
  if info.mode == "tag_prefix" then
    local prefix = info.tag_prefix .. "/"
    info.resolver = function(record, _field)
      local tags = record._raw_tags
      if type(tags) == "table" then
        for _, tag in ipairs(tags) do
          local t = type(tag) == "string" and tag or tostring(tag)
          if t:sub(1, #prefix) == prefix then
            return t:sub(#prefix + 1)
          end
        end
      end
      return ""
    end
  elseif info.mode == "directory" then
    info.resolver = function(record, _field)
      return record._directory or "/"
    end
  end

  return info
end

-- ─── Record building ──────────────────────────────────────────────────────────

--- Flatten notes into records for Board consumption.
---@param notes_map table<string, table>  slug → note
---@param display_fields string[]
---@param group_info vault.KanbanGroupInfo
---@param base? vault.Base
---@return table[]  flat records
---@return table<string, string>  slug → path map
---@return table<string, integer>  slug → mtime map
local function flatten_notes(notes_map, display_fields, group_info, base)
  local records = {}
  local paths = {}
  local mtimes = {}

  -- Build column set: group field + display fields
  local all_fields = {}
  local seen = {}
  -- Always include group field (if frontmatter mode — tag/dir use resolver)
  if group_info.mode == "frontmatter" then
    table.insert(all_fields, group_info.field_key)
    seen[group_info.field_key] = true
  end
  for _, f in ipairs(display_fields) do
    local col = shared.normalize_col(f)
    if not seen[col] then
      seen[col] = true
      table.insert(all_fields, col)
    end
  end

  local skipped = 0
  for slug, note in pairs(notes_map) do
    local ok, rec = pcall(function()
      local path = note.data and note.data.path or note.path
      if not path then return nil end

      local fm = shared.read_frontmatter_fields(path, all_fields)
      local flat = { id = slug }

      -- Stash raw data for resolvers
      local raw_tags = fm.tags
        or (note.data and note.data.frontmatter and note.data.frontmatter.tags)
        or (note.data and note.data.tags)
        or nil
      flat._raw_tags = raw_tags
      flat._path = path

      -- Directory for directory-mode grouping
      local relpath = note.data and note.data.relpath or ""
      flat._directory = relpath:match("^(.-/)[^/]*$") or "/"

      -- Frontmatter group field
      if group_info.mode == "frontmatter" then
        local gv = fm[group_info.field_key]
        if gv == vim.NIL or type(gv) == "userdata" then gv = nil end
        if type(gv) == "table" then gv = gv[1] end
        flat[group_info.field_key] = gv and tostring(gv) or ""
      elseif group_info.mode == "tag_prefix" then
        -- resolver handles this, but we still need the field key in the record
        flat[group_info.field_key] = ""  -- placeholder
      elseif group_info.mode == "directory" then
        flat[group_info.field_key] = flat._directory
      end

      -- Display fields
      for _, col in ipairs(all_fields) do
        if flat[col] ~= nil then goto cont end
        if col == "slug" then
          flat.slug = slug
        elseif col == "title" then
          flat.title = fm.title
            or (note.data and note.data.title)
            or (slug:match("[^/]+$") or slug)
        elseif col == "tags" then
          flat.tags = raw_tags
        elseif col == "file.name" then
          flat[col] = note.data and note.data.stem or (slug:match("[^/]+$") or slug)
        elseif col == "file.folder" then
          flat[col] = flat._directory
        elseif col == "file.path" then
          flat[col] = relpath
        elseif col == "file.ctime" then
          local t = note.data and note.data.ctime
          flat[col] = t and t > 0 and os.date("%Y-%m-%d %H:%M", t) or ""
        elseif col == "file.mtime" then
          local t = note.data and note.data.mtime
          flat[col] = t and t > 0 and os.date("%Y-%m-%d %H:%M", t) or ""
        elseif col:match("^formula%.") then
          if base and base:has_formulas() then
            local results = base:evaluate_formulas(note)
            local fname = col:match("^formula%.(.+)")
            flat[col] = results[fname]
          end
        else
          flat[col] = fm[col]
        end
        ::cont::
      end

      paths[slug] = path
      mtimes[slug] = shared.get_mtime(path)
      return flat
    end)

    if ok and rec then
      table.insert(records, rec)
    else
      skipped = skipped + 1
    end
  end

  if skipped > 0 then log.warn("%d notes skipped due to parse errors", skipped) end
  table.sort(records, function(a, b) return (a.id or "") < (b.id or "") end)
  return records, paths, mtimes
end

-- ─── Build kanban.Field[] ─────────────────────────────────────────────────────

---@param display_fields string[]
---@return kanban.Field[]
local function build_kanban_fields(display_fields)
  ---@type kanban.Field[]
  local fields = {}
  for _, col in ipairs(display_fields) do
    local name = shared.normalize_col(col)
    local is_readonly = shared.READONLY_FILE_COLS[name] or name:match("^formula%.") ~= nil
    ---@type kanban.Field
    local field = {
      name = name,
      readonly = is_readonly or false,
      format = function(value, _record)
        return shared.fmt_value(value, name)
      end,
      parse = function(text)
        return shared.parse_value(text, name)
      end,
    }
    if is_readonly then
      field.hl_group = "Comment"
    end
    table.insert(fields, field)
  end
  return fields
end

-- ─── Mutation helpers ─────────────────────────────────────────────────────────

---@param st vault.GridKanbanState
---@param slug string
---@param field_key string  The group field key
---@param new_value string  The new group value
local function apply_group_change(st, slug, field_key, new_value)
  local path = st.note_paths[slug]
  if not path then
    log.error("Cannot find path for note: %s", slug)
    return
  end

  if st.group_mode == "frontmatter" then
    local value_to_store = new_value
    if type(new_value) == "string" and new_value ~= "" then
      local is_link = new_value:match("^%[%[.-%]%]$") ~= nil
      local should_link = false

      -- Keep wikilink style when current field is stored as wikilink.
      local ok, lines = pcall(vim.fn.readfile, path, "", 80)
      if ok and lines and lines[1] and lines[1]:match("^%-%-%-") then
        for i = 2, #lines do
          local line = lines[i]
          if line:match("^%-%-%-") then break end
          local key, raw = line:match("^([%w_%-]+):%s*(.*)")
          if key == field_key and type(raw) == "string" then
            if raw:match("^%[%[.-%]%]$") or raw:match('^"%[%[.-%]%]"$') then
              should_link = true
            end
            break
          end
        end
      end

      -- Heuristic: grouped Status values are reference notes in this vault.
      if new_value:match("^Status%s*%-%s*") then
        should_link = true
      end

      if should_link and not is_link then
        value_to_store = string.format("[[%s]]", new_value)
      end
    end

    shared.set_frontmatter_field(path, field_key, value_to_store)

  elseif st.group_mode == "tag_prefix" then
    -- Remove old tag with prefix, add new tag with prefix
    local prefix = st.tag_prefix or ""
    local fm = shared.read_frontmatter_fields(path, { "tags" })
    local tags = fm.tags or {}
    if type(tags) == "table" then
      local new_tags = {}
      for _, t in ipairs(tags) do
        if not (type(t) == "string" and t:sub(1, #prefix + 1) == prefix .. "/") then
          table.insert(new_tags, t)
        end
      end
      -- Add new tag
      if new_value ~= "" then
        table.insert(new_tags, prefix .. "/" .. new_value)
      end
      shared.set_frontmatter_field(path, "tags", new_tags)
    end

  elseif st.group_mode == "directory" then
    -- Move file to new directory
    local config = require("vault.config")
    local basename = vim.fn.fnamemodify(path, ":t")
    local new_dir = new_value
    if new_dir == "/" then new_dir = "" end
    if new_dir ~= "" and not new_dir:match("/$") then
      new_dir = new_dir .. "/"
    end
    if new_dir:match("%.%.") then
      log.error("SAFETY: Refusing directory move with '..': %s", new_dir)
      return
    end
    local new_path = config.options.root .. "/" .. new_dir .. basename
    if new_path ~= path then
      local move_ok = pcall(function()
        local Note = require("vault.notes.note")
        local note = Note(path)
        note:move(new_path, false, false, { silent = true })
      end)
      if move_ok then
        st.note_paths[slug] = new_path
      else
        log.error("Directory move failed for: %s", slug)
      end
    end
  end
end

-- ─── Callback builders ────────────────────────────────────────────────────────

---@param st vault.GridKanbanState
---@return fun(mutations: kanban.Mutations, done: fun(err: string|nil))
local function make_on_save(st)
  return function(mutations, done)
    st.saving = true

    local n_updates = #mutations.updates
    local n_moves = #mutations.moves
    local n_creates = #mutations.creates
    local n_deletes = #mutations.deletes
    local total = n_updates + n_moves + n_creates + n_deletes

    if total == 0 then
      st.saving = false
      done(nil)
      return
    end

    -- Safety caps
    if n_deletes > DELETE_HARD_CAP then
      log.error("SAFETY: Refusing %d deletes (cap %d)", n_deletes, DELETE_HARD_CAP)
      mutations.deletes = {}
      n_deletes = 0
    end
    if n_creates > CREATE_HARD_CAP then
      log.error("SAFETY: Refusing %d creates (cap %d)", n_creates, CREATE_HARD_CAP)
      mutations.creates = {}
      n_creates = 0
    end

    local function finish_save()
      local results = {}

      local function is_tasks_board()
        if st.group_mode ~= "frontmatter" or st.group_field ~= "status" then
          return false
        end
        for _, p in pairs(st.note_paths or {}) do
          if type(p) == "string" and p:match("/Tasks/") then
            return true
          end
        end
        return false
      end

      local function derive_create_title(cr)
        local candidates = {}
        candidates[#candidates + 1] = cr.fields and cr.fields.title or nil
        if st.display_fields then
          for _, f in ipairs(st.display_fields) do
            candidates[#candidates + 1] = cr.fields and cr.fields[f] or nil
          end
        end
        for _, v in ipairs(candidates) do
          if type(v) == "string" then
            local t = vim.trim(v)
            if t ~= "" and not t:match("^%w+:%s*$") then
              return t
            end
          end
        end
        return "untitled"
      end

      local tasks_board = is_tasks_board()

      -- Process moves (group field changes)
      for _, mv in ipairs(mutations.moves) do
        apply_group_change(st, mv.id, st.group_field, mv.to)
      end
      if n_moves > 0 then table.insert(results, string.format("%d moved", n_moves)) end

      -- Process updates (field edits within cards)
      local n_upd = 0
      for _, upd in ipairs(mutations.updates) do
        local path = st.note_paths[upd.id]
        if not path then goto upd_continue end
        local safe_path, path_err = shared.validate_path_in_vault(path)
        if not safe_path then
          log.error("SAFETY: Skipping update — %s", path_err); goto upd_continue
        end
        -- Mtime check
        local snap_mtime = st.note_mtimes and st.note_mtimes[upd.id] or 0
        if snap_mtime > 0 and shared.get_mtime(safe_path) > snap_mtime then
          log.warn("SAFETY: Skipping %s — file modified externally", upd.id)
          goto upd_continue
        end
        -- Filter out internal fields
        local fm_fields = {}
        for col, val in pairs(upd.fields) do
          if not col:match("^_") then
            fm_fields[col] = val
          end
        end
        if next(fm_fields) then
          shared.set_frontmatter_fields(safe_path, fm_fields)
        end
        n_upd = n_upd + 1
        ::upd_continue::
      end
      if n_upd > 0 then table.insert(results, string.format("%d updated", n_upd)) end

      -- Process creates (new notes)
      local n_cr = 0
      for _, cr in ipairs(mutations.creates) do
        local config = require("vault.config")
        local title = derive_create_title(cr)

        if tasks_board then
          local task_notes = require("vault.tasks.notes")
          local gv = cr.fields and cr.fields[st.group_field] or nil
          local status = "[[Status - Backlog]]"
          if type(gv) == "string" and gv ~= "" then
            gv = gv:gsub("^%[%[(.-)%]%]$", "%1")
            status = string.format("[[%s]]", gv)
          end

          local path = task_notes.create(title, { status = status })
          if path and vim.fn.filereadable(path) == 1 then
            local slug = require("vault.utils").path_to_slug(path)
            st.note_paths[slug] = path
            n_cr = n_cr + 1
          end
          goto cr_continue
        end

        local slug_source = title:lower():gsub("%s+", "-"):gsub("[%c%[%]#|^]", "")
        if slug_source == "" then slug_source = "untitled" end

        -- Determine directory from group field if in directory mode
        local dir = ""
        if st.group_mode == "directory" then
          local gv = cr.fields[st.group_field] or cr.fields._directory or ""
          if gv == "/" then gv = "" end
          dir = gv
        end
        if dir ~= "" and not dir:match("/$") then dir = dir .. "/" end
        if dir:match("%.%.") then
          log.error("SAFETY: Refusing create with '..': %s", dir); goto cr_continue
        end

        local slug = slug_source
        local path = config.options.root .. "/" .. dir .. slug .. config.options.ext
        local counter = 1
        while vim.fn.filereadable(path) == 1 do
          slug = slug_source .. "-" .. counter
          path = config.options.root .. "/" .. dir .. slug .. config.options.ext
          counter = counter + 1
          if counter > 100 then
            log.error("Too many slug collisions for: %s", slug_source); goto cr_continue
          end
        end

        local safe_path, cr_err = shared.validate_path_in_vault(path)
        if not safe_path then
          log.error("SAFETY: Skipping create — %s", cr_err); goto cr_continue
        end

        -- Build frontmatter
        local fm = { "---" }
        if cr.fields.title then
          table.insert(fm, "title: " .. shared.yaml_quote(tostring(cr.fields.title)))
        end

        -- Set group field
        if st.group_mode == "frontmatter" then
          local gv = cr.fields[st.group_field]
          if gv and gv ~= "" then
            table.insert(fm, st.group_field .. ": " .. shared.yaml_quote(tostring(gv)))
          end
        elseif st.group_mode == "tag_prefix" then
          local gv = cr.fields[st.group_field]
          if gv and gv ~= "" then
            table.insert(fm, "tags:")
            table.insert(fm, "  - " .. shared.yaml_quote(st.tag_prefix .. "/" .. gv))
          end
        end

        -- Other fields
        local skip = { title = true, id = true, [st.group_field] = true }
        for col, val in pairs(cr.fields) do
          if not skip[col] and not col:match("^_") and val ~= nil then
            if col == "tags" and type(val) == "table" then
              -- Only add tags: header if not already added by tag_prefix
              if st.group_mode ~= "tag_prefix" then
                table.insert(fm, "tags:")
              end
              for _, t in ipairs(val) do table.insert(fm, "  - " .. shared.yaml_quote(tostring(t))) end
            elseif type(val) == "table" then
              table.insert(fm, col .. ":")
              for _, v in ipairs(val) do table.insert(fm, "  - " .. shared.yaml_quote(tostring(v))) end
            else
              table.insert(fm, col .. ": " .. shared.yaml_quote(tostring(val)))
            end
          end
        end

        table.insert(fm, "---")
        table.insert(fm, "")

        local parent = vim.fn.fnamemodify(safe_path, ":h")
        if vim.fn.isdirectory(parent) == 0 then vim.fn.mkdir(parent, "p") end
        local write_ok = shared.atomic_writefile(safe_path, fm)
        if write_ok then
          st.note_paths[dir .. slug] = safe_path
          n_cr = n_cr + 1
        end
        ::cr_continue::
      end
      if n_cr > 0 then table.insert(results, string.format("%d created", n_cr)) end

      -- Process deletes
      local n_del = 0
      for _, slug in ipairs(mutations.deletes) do
        local path = st.note_paths[slug]
        if path then
          local safe_del, del_err = shared.validate_path_in_vault(path)
          if not safe_del then
            log.error("SAFETY: Skipping delete — %s", del_err); goto del_continue
          end
          local del_ok = pcall(function()
            local Note = require("vault.notes.note")
            local note = Note(safe_del)
            note:delete(false, false)
          end)
          if del_ok then
            n_del = n_del + 1
          else
            log.error("Delete failed for: %s", slug)
          end
        end
        ::del_continue::
      end
      if n_del > 0 then table.insert(results, string.format("%d trashed", n_del)) end

      if #results == 0 then results = { "no changes" } end
      log.info("Kanban saved: %s", table.concat(results, ", "))
      st.saving = false
      done(nil)

      -- Refresh the board after save
      if st.board then
        M.refresh_board(st)
      end
    end

    -- Confirmation dialog for deletes
    if n_deletes > 0 then
      local confirm_ui = require("vault.ui.confirm")
      local preview = {}
      for i = 1, math.min(10, n_deletes) do
        table.insert(preview, "  - " .. mutations.deletes[i])
      end
      if n_deletes > 10 then
        table.insert(preview, string.format("  ... and %d more", n_deletes - 10))
      end
      confirm_ui.select({
        message = string.format(
          "Vault Kanban: About to TRASH %d note%s:\n%s\n\n%d updated, %d moved, %d created.\n\nProceed?",
          n_deletes, n_deletes == 1 and "" or "s",
          table.concat(preview, "\n"), n_updates, n_moves, n_creates),
        title = "Vault Kanban",
        choices = {
          { key = "y", label = "Yes, trash them", action = finish_save },
          { key = "n", label = "No, skip deletes", action = function()
            mutations.deletes = {}
            finish_save()
          end },
          { key = "c", label = "Cancel", action = function()
            st.saving = false
            done(nil)
          end },
        },
      })
    else
      finish_save()
    end
  end
end

---@param st vault.GridKanbanState
---@return fun(record_id: string, from: string, to: string, done: fun(err: string|nil))
local function make_on_move(st)
  return function(record_id, from, to, done)
    apply_group_change(st, record_id, st.group_field, to)
    log.info("Moved '%s': %s → %s", record_id, from, to)
    done(nil)
  end
end

---@param st vault.GridKanbanState
---@return fun(done: fun(records: table[]|nil, err: string|nil))
local function make_on_refresh(st)
  return function(done)
    -- Rescan notes
    if st.base then
      local all_notes = require("vault.notes")()
      local notes_map = all_notes.map or {}
      if st.base:has_filters() then
        notes_map = st.base:match_notes(notes_map)
      end
      st.notes_map = notes_map
    else
      local all_notes = require("vault.notes")()
      st.notes_map = all_notes.map or {}
    end

    local group_info = resolve_group_field(st.notes_map, st.group_field, nil)
    local records, paths, mtimes = flatten_notes(
      st.notes_map, st.display_fields, group_info, st.base)
    st.note_paths = paths
    st.note_mtimes = mtimes
    done(records, nil)
  end
end

--- Refresh the board state (used after save).
---@param st vault.GridKanbanState
function M.refresh_board(st)
  if not st.board then return end
  local refresh = make_on_refresh(st)
  refresh(function(records, err)
    if err then
      log.error("Refresh failed: %s", err)
      return
    end
    if records and st.board then
      st.board:reload(records)
    end
  end)
end

-- ─── Base kanban view parsing ─────────────────────────────────────────────────

--- Find the first kanban view in a base's views array.
---@param base vault.Base
---@return table|nil  The kanban view definition or nil
local function find_kanban_view(base)
  if not base.data.views then return nil end
  for _, view in ipairs(base.data.views) do
    if view.type == "kanban" then
      return view
    end
  end
  return nil
end

-- ─── Open ─────────────────────────────────────────────────────────────────────

---@class vault.GridKanbanOpenOpts
---@field notes? vault.Notes        Pre-filtered notes (if nil, scans all)
---@field base? vault.Base           Base definition (for filters + kanban view config)
---@field group_field? string        Override group field
---@field group_values? string[]     Override group values (ordered column names)
---@field display_fields? string[]   Override display fields
---@field render_mode? kanban.RenderMode  Override render mode
---@field filter_desc? string        Description for logging

---@param opts? vault.GridKanbanOpenOpts
function M.open(opts)
  opts = opts or {}

  local cfg = require("vault.config")
  local kanban_cfg = cfg.options and cfg.options.kanban or {}

  local base = opts.base
  local filter_desc = opts.filter_desc or "all notes"

  -- Derive settings from base kanban view if available
  local base_view = base and find_kanban_view(base) or nil
  local group_field = opts.group_field
    or (base_view and base_view.group_by)
    or kanban_cfg.group_field
    or DEFAULT_GROUP_FIELD
  local group_values = opts.group_values
    or (base_view and base_view.group_values)
    or kanban_cfg.group_values
    or nil
  local display_fields = opts.display_fields
    or (base_view and base_view.display_fields)
    or kanban_cfg.display_fields
    or DEFAULT_DISPLAY_FIELDS
  local render_mode = opts.render_mode
    or (base_view and base_view.render_mode)
    or kanban_cfg.render_mode
    or DEFAULT_RENDER_MODE

  if base then
    filter_desc = opts.filter_desc or ("base:" .. (base.data.name or "unnamed"))
  end

  -- Build board_id for dedup
  local board_id = "vault/kanban/" .. filter_desc .. "/" .. group_field

  -- Close existing board with same ID
  if board_states[board_id] then
    local old = board_states[board_id]
    if old.board then
      pcall(old.board.close, old.board)
    end
    board_states[board_id] = nil
  end

  -- Clean up orphan kanban buffers from previously failed attach calls
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(bufnr) then
      local bname = vim.api.nvim_buf_get_name(bufnr)
      if bname:match("^kanban://") then
        pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
      end
    end
  end

  -- Get notes
  local notes_map
  if opts.notes then
    notes_map = opts.notes.map or {}
  else
    notes_map = require("vault.notes")().map or {}
  end
  if base and base:has_filters() then
    notes_map = base:match_notes(notes_map)
  end
  if not next(notes_map) then
    log.info("No notes match%s", base and (" base '" .. base.data.name .. "'") or "")
    return
  end

  -- Resolve group field
  local group_info = resolve_group_field(notes_map, group_field, group_values)

  -- Flatten notes to records
  local records, note_paths, note_mtimes = flatten_notes(
    notes_map, display_fields, group_info, base)

  if #records == 0 then
    log.info("No records after flattening")
    return
  end

  -- Build kanban fields
  local kanban_fields = build_kanban_fields(display_fields)

  -- Layout config
  local layout_cfg = kanban_cfg.layout or {}
  local layout = {
    width_ratio = layout_cfg.width_ratio or 0.95,
    height_ratio = layout_cfg.height_ratio or 0.90,
    column_gap = layout_cfg.column_gap or 1,
    min_column_width = layout_cfg.min_column_width or 25,
  }

  -- Prepare state
  ---@type vault.GridKanbanState
  local st = {
    board = nil,  -- set below
    note_paths = note_paths,
    note_mtimes = note_mtimes,
    base = base,
    group_field = group_field,
    group_mode = group_info.mode,
    tag_prefix = group_info.tag_prefix,
    display_fields = display_fields,
    columns = {},  -- populated by board
    filter_desc = filter_desc,
    notes_map = notes_map,
    saving = false,
  }

  -- Create Board
  local Board = get_Board()
  local board = Board.new({
    group_field = group_info.field_key,
    fields = kanban_fields,
    records = records,
    id_field = "id",
    identity_prefix = "/",
    render_mode = render_mode,
    group_values = group_info.values,
    group_colors = group_info.colors,
    group_resolver = group_info.resolver,
    empty_cell = shared.get_empty_cell(),
    on_save = make_on_save(st),
    on_move = make_on_move(st),
    on_refresh = make_on_refresh(st),
    on_filter_request = function(b)
      local s = board_states[board_id]
      if not s then return end
      local picker = require("vault.bases.views.filter_picker")
      picker.open(b, s.display_fields)
    end,
    on_close = function()
      board_states[board_id] = nil
      log.info("Kanban board closed (%s)", filter_desc)
    end,
    on_record_entry = function(record, _board)
      local slug = record.id
      local path = st.note_paths[slug]
      if path then
        -- Close the board first, then open the note
        if st.board then
          pcall(st.board.close, st.board)
        end
        vim.cmd("edit " .. vim.fn.fnameescape(path))
      else
        log.warn("Cannot find path for note: %s", slug)
      end
    end,
    on_new_record = function(column_value, done)
      -- Create a new note directly with the group field set
      local config = require("vault.config")
      local timestamp = os.date("%Y%m%d%H%M%S")
      local slug = "note-" .. timestamp
      local dir = ""
      if st.group_mode == "directory" then
        dir = column_value
        if dir == "/" then dir = "" end
        if dir ~= "" and not dir:match("/$") then dir = dir .. "/" end
      end
      local path = config.options.root .. "/" .. dir .. slug .. config.options.ext

      local fm = { "---" }
      table.insert(fm, "title: " .. shared.yaml_quote(slug))
      if st.group_mode == "frontmatter" then
        if column_value ~= "" then
          table.insert(fm, st.group_field .. ": " .. shared.yaml_quote(column_value))
        end
      elseif st.group_mode == "tag_prefix" then
        if column_value ~= "" then
          table.insert(fm, "tags:")
          table.insert(fm, "  - " .. shared.yaml_quote(st.tag_prefix .. "/" .. column_value))
        end
      end
      table.insert(fm, "---")
      table.insert(fm, "")

      local parent = vim.fn.fnamemodify(path, ":h")
      if vim.fn.isdirectory(parent) == 0 then vim.fn.mkdir(parent, "p") end
      local write_ok = shared.atomic_writefile(path, fm)
      if write_ok then
        local new_slug = dir .. slug
        st.note_paths[new_slug] = path
        local rec = {
          id = new_slug,
          title = slug,
          _path = path,
          _directory = dir ~= "" and dir or "/",
          _raw_tags = {},
        }
        -- Set group field on record
        if st.group_mode == "frontmatter" then
          rec[st.group_field] = column_value
        elseif st.group_mode == "tag_prefix" then
          rec[group_info.field_key] = ""  -- resolver handles display
          rec._raw_tags = st.tag_prefix and column_value ~= ""
            and { st.tag_prefix .. "/" .. column_value } or {}
        elseif st.group_mode == "directory" then
          rec[group_info.field_key] = dir ~= "" and dir or "/"
        end
        log.info("Created note: %s (column: %s)", new_slug, column_value)
        done(rec)
      else
        log.error("Failed to create note: %s", path)
        done(nil)
      end
    end,
    layout = layout,
    value_hl = function(text)
      return get_value_hl(text)
    end,
  })

  st.board = board
  board_states[board_id] = st

  -- Attach (opens floating windows)
  board:attach()

  -- gf/gF handled by Board._setup_column_keymaps via on_filter_request
  for _, col in ipairs(board:columns()) do
    -- Help legend
    require("vimtable.help").setup_keymap(col.bufnr, {
      { group = "Navigation",  lhs = "h / l",       desc = "Previous / next column" },
      { lhs = "j / k",        desc = "Card up / down" },
      { group = "Move card",   lhs = "<C-h> / <C-l>", desc = "Move card left / right" },
      { group = "Assign",      lhs = "ga",           desc = "Assign card to group" },
      { group = "Add / Delete", lhs = "o",           desc = "New card" },
      { lhs = "dd",           desc = "Delete card" },
      { group = "Filter",      lhs = "gf",           desc = "Open filter picker" },
      { lhs = "gF",           desc = "Clear all filters" },
      { group = "Saving",      lhs = "<C-s> / :w",  desc = "Save changes" },
      { group = "Help",        lhs = "g?",           desc = "Toggle this help" },
      { lhs = "q / <Esc>",    desc = "Close board" },
    })
  end

  log.info(
    "Kanban board: %d notes, grouped by '%s' (%s), %d columns — H/L to move, <C-s> to save, q to close",
    #records, group_field, group_info.mode, #group_info.values
  )
end

-- ─── Close all boards ─────────────────────────────────────────────────────────

function M.close_all()
  for id, st in pairs(board_states) do
    if st.board then
      pcall(st.board.close, st.board)
    end
    board_states[id] = nil
  end
  -- Clean up orphan kanban buffers (from partially failed attach calls)
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(bufnr) then
      local name = vim.api.nvim_buf_get_name(bufnr)
      if name:match("^kanban://") then
        pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
      end
    end
  end
end

-- ─── Debug / test exports ─────────────────────────────────────────────────────

M._board_states = board_states
M._resolve_group_field = resolve_group_field
M._flatten_notes = flatten_notes
M._build_kanban_fields = build_kanban_fields
M._find_kanban_view = find_kanban_view
M._get_value_hl = get_value_hl
M._apply_group_change = apply_group_change

return M
