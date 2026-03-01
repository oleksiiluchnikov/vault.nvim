--- vault.merge — Merge two notes into one.
--- Absorbs note B into note A: merges frontmatter, appends body,
--- rewrites all [[B]] wikilinks to [[A]], and trashes B.
--- Works standalone or from the process buffer (J keymap).

local M = {}

local config = require("vault.config")
local log = require("vault.log").scope("merge")

--- Read the full content of a file, split into frontmatter fields, body lines.
---@param path string
---@return table|nil fields, string[]|nil body_lines, string[]|nil raw_lines
local function parse_note(path)
  local ok, lines = pcall(vim.fn.readfile, path)
  if not ok or #lines == 0 then return nil, nil, nil end

  local fields = {}
  local body_start = 1

  if lines[1] and lines[1]:match("^%-%-%-$") then
    local fm_end = nil
    for i = 2, math.min(#lines, 200) do
      if lines[i]:match("^%-%-%-$") then fm_end = i; break end
    end
    if fm_end then
      body_start = fm_end + 1
      -- Parse frontmatter
      local current_key, current_list = nil, nil
      for i = 2, fm_end - 1 do
        local l = lines[i]
        local list_item = l:match("^%s+%-%s+(.+)")
        if list_item and current_key and current_list then
          list_item = list_item:gsub('^"(.*)"$', "%1"):gsub("^'(.*)'$", "%1")
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
            else
              value = value:gsub('^"(.*)"$', "%1"):gsub("^'(.*)'$", "%1")
              fields[key] = value
              current_key = nil
            end
          end
        end
      end
      if current_key and current_list and #current_list > 0 then
        fields[current_key] = current_list
      end
    end
  end

  local body = {}
  for i = body_start, #lines do
    table.insert(body, lines[i])
  end

  return fields, body, lines
end

--- Detect field conflicts between two notes.
---@param fields_a table
---@param fields_b table
---@return { field: string, val_a: any, val_b: any }[]
local function detect_conflicts(fields_a, fields_b)
  local conflicts = {}
  for key, val_b in pairs(fields_b) do
    local val_a = fields_a[key]
    if val_a ~= nil and val_a ~= "" and val_b ~= "" then
      -- Both have values — check if they differ
      local a_str = type(val_a) == "table" and table.concat(val_a, ",") or tostring(val_a)
      local b_str = type(val_b) == "table" and table.concat(val_b, ",") or tostring(val_b)
      if a_str ~= b_str then
        table.insert(conflicts, { field = key, val_a = val_a, val_b = val_b })
      end
    end
  end
  return conflicts
end

--- Merge fields: A wins by default, resolved overrides apply, arrays are unioned.
---@param fields_a table
---@param fields_b table
---@param resolved? table<string, any>  field → chosen value (from picker)
---@return table merged
local function merge_fields(fields_a, fields_b, resolved)
  resolved = resolved or {}
  local merged = vim.deepcopy(fields_a)

  for key, val_b in pairs(fields_b) do
    if resolved[key] ~= nil then
      merged[key] = resolved[key]
    elseif merged[key] == nil or merged[key] == "" then
      -- A is empty, take B's value
      merged[key] = val_b
    elseif type(merged[key]) == "table" and type(val_b) == "table" then
      -- Both are arrays: union them
      local seen = {}
      for _, v in ipairs(merged[key]) do seen[v] = true end
      for _, v in ipairs(val_b) do
        if not seen[v] then
          table.insert(merged[key], v)
          seen[v] = true
        end
      end
    end
    -- else: A has a value and B has a different value → A wins (unless resolved)
  end

  return merged
end

--- Build frontmatter YAML lines from a fields table.
---@param fields table
---@return string[]
local function build_frontmatter(fields)
  local lines = { "---" }
  -- Sort keys for deterministic output
  local keys = vim.tbl_keys(fields)
  table.sort(keys)
  for _, key in ipairs(keys) do
    local val = fields[key]
    if type(val) == "table" then
      table.insert(lines, key .. ":")
      for _, v in ipairs(val) do
        local s = tostring(v)
        if s:match("[:%[%]{}#&*!|>%%@`,?]") or s:match("^%s") or s:match("%s$") then
          table.insert(lines, '  - "' .. s:gsub('"', '\\"') .. '"')
        else
          table.insert(lines, "  - " .. s)
        end
      end
    elseif val ~= nil then
      local s = tostring(val)
      if s:match("[:%[%]{}#&*!|>%%@`,?]") or s:match("^%s") or s:match("%s$") or s == "" then
        table.insert(lines, key .. ': "' .. s:gsub('"', '\\"') .. '"')
      else
        table.insert(lines, key .. ": " .. s)
      end
    end
  end
  table.insert(lines, "---")
  return lines
end

--- Open a floating picker for resolving field conflicts.
---@param slug_a string
---@param slug_b string
---@param conflicts { field: string, val_a: any, val_b: any }[]
---@param on_resolve fun(resolved: table<string, any>)
function M.open_conflict_picker(slug_a, slug_b, conflicts, on_resolve)
  local choices = {} -- index → "a" or "b"
  for i = 1, #conflicts do choices[i] = "a" end -- default: pick A

  -- Pre-compute column widths for alignment
  local MAX_VAL = 38  -- max display width for each value column
  local function val_str(v)
    return type(v) == "table" and table.concat(v, ", ") or tostring(v)
  end
  local function truncate(s, max)
    if #s <= max then return s end
    return s:sub(1, max - 1) .. "…"
  end

  -- Field-name column width: longest "fieldname:" + 1 space
  local field_w = 0
  for _, c in ipairs(conflicts) do
    field_w = math.max(field_w, #c.field + 1)  -- +1 for ":"
  end
  field_w = field_w + 1  -- trailing space after colon

  -- Value column width: capped at MAX_VAL
  local val_a_w = 0
  local val_b_w = 0
  for _, c in ipairs(conflicts) do
    val_a_w = math.max(val_a_w, math.min(#val_str(c.val_a), MAX_VAL))
    val_b_w = math.max(val_b_w, math.min(#val_str(c.val_b), MAX_VAL))
  end

  -- marker (●/○) is 1 display cell + 1 space = 2 before value
  -- layout: " " + field_col + "  " + marker + " " + val_a_col + "  |  " + marker + " " + val_b_col
  local total_w = 1 + field_w + 2 + 2 + val_a_w + 5 + 2 + val_b_w
  local width = math.max(total_w, 60)

  local function render_lines()
    local header = string.format(" Merge: %s ← %s", slug_a, slug_b)
    local sep_line = " " .. string.rep("─", width - 2)
    local lines = { header, sep_line }
    for i, c in ipairs(conflicts) do
      local a_str = truncate(val_str(c.val_a), MAX_VAL)
      local b_str = truncate(val_str(c.val_b), MAX_VAL)
      local marker_a = choices[i] == "a" and "●" or "○"
      local marker_b = choices[i] == "b" and "●" or "○"
      -- Pad field name and value columns for alignment
      local field_col = string.format("%-" .. field_w .. "s", c.field .. ":")
      local val_a_col = string.format("%-" .. val_a_w .. "s", a_str)
      table.insert(lines, string.format(
        " %s  %s %s  |  %s %s",
        field_col, marker_a, val_a_col, marker_b, b_str
      ))
    end
    table.insert(lines, "")
    table.insert(lines, " [a] pick A  [b] pick B  [<CR>] confirm  [q] cancel")
    return lines
  end

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, render_lines())
  vim.bo[buf].modifiable = false
  vim.bo[buf].bufhidden = "wipe"

  local height = #conflicts + 5
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    col = math.floor((vim.o.columns - width) / 2),
    row = math.floor((vim.o.lines - height) / 2),
    style = "minimal",
    border = "rounded",
    title = " Resolve Conflicts ",
    title_pos = "center",
  })

  local cursor_idx = 1

  local function update()
    vim.bo[buf].modifiable = true
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, render_lines())
    vim.bo[buf].modifiable = false
    vim.api.nvim_win_set_cursor(win, { cursor_idx + 2, 0 }) -- +2 for header lines
  end

  local function close()
    if vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_close(win, true) end
  end

  local kopts = { buffer = buf, nowait = true, silent = true }

  vim.keymap.set("n", "j", function()
    cursor_idx = math.min(cursor_idx + 1, #conflicts)
    update()
  end, kopts)

  vim.keymap.set("n", "k", function()
    cursor_idx = math.max(cursor_idx - 1, 1)
    update()
  end, kopts)

  vim.keymap.set("n", "a", function()
    choices[cursor_idx] = "a"
    update()
  end, kopts)

  vim.keymap.set("n", "b", function()
    choices[cursor_idx] = "b"
    update()
  end, kopts)

  vim.keymap.set("n", "<CR>", function()
    close()
    local resolved = {}
    for i, c in ipairs(conflicts) do
      resolved[c.field] = choices[i] == "a" and c.val_a or c.val_b
    end
    on_resolve(resolved)
  end, kopts)

  vim.keymap.set("n", "q", function()
    close()
    log.info("Merge cancelled")
  end, kopts)

  vim.keymap.set("n", "<Esc>", function()
    close()
    log.info("Merge cancelled")
  end, kopts)

  update()
end

--- Absorb note B into note A.
---@param path_a string
---@param path_b string
---@param resolved? table<string, any>  resolved conflict fields
---@param opts? { bufnr?: integer, on_done?: fun() }
function M.absorb(path_a, path_b, resolved, opts)
  opts = opts or {}
  local utils = require("vault.utils")

  local slug_a = utils.path_to_slug(path_a)
  local slug_b = utils.path_to_slug(path_b)

  -- Parse both notes
  local fields_a, body_a, raw_a = parse_note(path_a)
  local fields_b, body_b, raw_b = parse_note(path_b)
  if not fields_a or not fields_b then
    local missing = {}
    if not fields_a then table.insert(missing, slug_a .. " (" .. path_a .. ")") end
    if not fields_b then table.insert(missing, slug_b .. " (" .. path_b .. ")") end
    log.error("Failed to parse: %s", table.concat(missing, ", "))
    return
  end

  -- Snapshot for undo: both notes + wikilink files referencing B
  local uv = vim.uv or vim.loop
  local snapshot_files = {}
  snapshot_files[path_a] = raw_a
  snapshot_files[path_b] = raw_b

  -- Find files with wikilinks to B
  local scanner = require("vault.scanner")
  local paths = scanner.paths()
  local escaped_slug = vim.pesc(slug_b)
  local escaped_stem = vim.pesc(vim.fn.fnamemodify(path_b, ":t:r"))
  for _, entry in pairs(paths) do
    local note_path = entry.path
    if not snapshot_files[note_path] and vim.fn.filereadable(note_path) == 1 then
      local f = io.open(note_path, "r")
      if f then
        local content = f:read("*all")
        f:close()
        if content:match("%[%[" .. escaped_slug) or content:match("%[%[" .. escaped_stem) then
          snapshot_files[note_path] = vim.split(content, "\n", { plain = true })
        end
      end
    end
  end

  -- Store undo snapshot if we have a process buffer
  local editor = require("vault.bases.editor")
  if opts.bufnr and editor._undo_snapshots then
    editor._undo_snapshots[opts.bufnr] = {
      files = snapshot_files,
      created_paths = {},
      renames = {},
      timestamp = os.time(),
      description = string.format("merge %s ← %s", slug_a, slug_b),
    }
  end

  -- Merge fields
  local merged_fields = merge_fields(fields_a, fields_b, resolved)

  -- Build merged content
  local merged_lines = build_frontmatter(merged_fields)

  -- Add A's body
  if body_a then
    for _, l in ipairs(body_a) do
      table.insert(merged_lines, l)
    end
  end

  -- Add separator and B's body
  if body_b and #body_b > 0 then
    -- Strip leading blank lines from B's body
    local first_content = 1
    for i, l in ipairs(body_b) do
      if l:match("%S") then first_content = i; break end
    end
    table.insert(merged_lines, "")
    table.insert(merged_lines, string.format("<!-- merged from: %s -->", slug_b))
    table.insert(merged_lines, "")
    for i = first_content, #body_b do
      table.insert(merged_lines, body_b[i])
    end
  end

  -- Write merged content to A
  local write_ok, write_err = pcall(function()
    local f = io.open(path_a, "w")
    if not f then error("Cannot open " .. path_a) end
    f:write(table.concat(merged_lines, "\n") .. "\n")
    f:close()
  end)
  if not write_ok then
    log.error("Failed to write merged note: %s", tostring(write_err))
    return
  end

  -- Rewrite [[B]] wikilinks to [[A]] across vault
  local Watcher = require("vault.watcher")
  local watcher = Watcher()
  watcher:disable_oil_guard()
  local patched = watcher:handle_rename(path_b, path_a) or 0

  -- Trash B
  local Note = require("vault.notes.note")
  local ok_note, note_b = pcall(Note, path_b)
  if ok_note and note_b then
    pcall(note_b.delete, note_b, false, false)
  end

  log.info("Merged %s ← %s (%d wikilinks patched)", slug_a, slug_b, patched)

  if opts.on_done then opts.on_done() end
end

--- Merge two notes, detecting conflicts automatically.
--- If conflicts exist, opens a picker. Otherwise absorbs silently.
---@param path_a string  path of the surviving note
---@param path_b string  path of the absorbed note
---@param opts? { bufnr?: integer, on_done?: fun() }
function M.merge(path_a, path_b, opts)
  opts = opts or {}
  local utils = require("vault.utils")
  local slug_a = utils.path_to_slug(path_a)
  local slug_b = utils.path_to_slug(path_b)

  local fields_a = parse_note(path_a)
  local fields_b = parse_note(path_b)
  if not fields_a or not fields_b then
    local missing = {}
    if not fields_a then table.insert(missing, slug_a .. " (" .. path_a .. ")") end
    if not fields_b then table.insert(missing, slug_b .. " (" .. path_b .. ")") end
    log.error("Failed to parse: %s", table.concat(missing, ", "))
    return
  end

  local conflicts = detect_conflicts(fields_a, fields_b)

  if #conflicts == 0 then
    M.absorb(path_a, path_b, nil, opts)
  else
    M.open_conflict_picker(slug_a, slug_b, conflicts, function(resolved)
      M.absorb(path_a, path_b, resolved, opts)
    end)
  end
end

-- Expose internals for testing
M._parse_note = parse_note
M._detect_conflicts = detect_conflicts
M._merge_fields = merge_fields
M._build_frontmatter = build_frontmatter

return M
