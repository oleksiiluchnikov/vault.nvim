-- lua/vault/bases/views/shared.lua
-- Shared helpers for vault grid and kanban view adapters.
--
-- Extracted from grid.lua to avoid duplication between the
-- tabular (Grid) and board (Kanban) vault process views.

local M = {}

local log = require("vault.log").scope("bases.shared")

---@alias vault.bases.views.ColumnName string
---@alias vault.bases.views.FrontmatterScalar string|number|boolean
---@alias vault.bases.views.FrontmatterList vault.bases.views.FrontmatterScalar[]
---@alias vault.bases.views.FrontmatterValue vault.bases.views.FrontmatterScalar|vault.bases.views.FrontmatterList
---@alias vault.bases.views.FrontmatterMap table<string, vault.bases.views.FrontmatterValue>

-- ─── Constants ────────────────────────────────────────────────────────────────

---@type table<string, true>
M.READONLY_FILE_COLS = {
  ["file.path"]     = true,
  ["file.ext"]      = true,
  ["file.ctime"]    = true,
  ["file.mtime"]    = true,
  ["file.size"]     = true,
  ["file.inlinks"]  = true,
  ["file.outlinks"] = true,
  ["file.headings"] = true,
}

---@type string[]
M.FILE_IMPLICIT_PROPS = {
  "file.name", "file.folder", "file.path", "file.ext",
  "file.ctime", "file.mtime", "file.size",
  "file.body", "file.slug",
  "file.inlinks", "file.outlinks", "file.headings",
}

-- ─── Empty cell ───────────────────────────────────────────────────────────────

local EMPTY_CELL --- @type string

---@return string
function M.get_empty_cell()
  if not EMPTY_CELL then
    local ok, cfg = pcall(require, "vault.config")
    EMPTY_CELL = (ok and cfg.options.bases and cfg.options.bases.empty_cell) or "_"
  end
  return EMPTY_CELL
end

--- Reset the cached empty cell (for tests).
function M.reset_empty_cell()
  EMPTY_CELL = nil
end

-- ─── Column helpers ───────────────────────────────────────────────────────────

---@param col string
---@return string
function M.normalize_col(col)
  if col:match("^note%.") then col = "file." .. col:sub(6) end
  if col == "dir"  then return "file.folder" end
  if col == "body" then return "file.body"   end
  if col == "name" then return "file.name"   end
  return col
end

---@param key string
---@return string col_name, boolean is_readonly
function M.base_key_to_col(key)
  key = M.normalize_col(key)
  if key:match("^formula%.") then return key, true end
  if M.READONLY_FILE_COLS[key] then return key, true end
  return key, false
end

-- ─── YAML helpers ─────────────────────────────────────────────────────────────

---@param value string
---@return string
function M.yaml_quote(value)
  local dominated = value:lower()
  if dominated == "true" or dominated == "false"
    or dominated == "yes" or dominated == "no"
    or dominated == "on" or dominated == "off"
    or dominated == "null" or dominated == "~"
    or value:match("^[%d%.eE%+%-]+$")
    or value:match("^[%d]")
    or value:match("[:#{}%[%]|>%%@`]")
    or value:match("^%s") or value:match("%s$")
    or value:match("^[?&*!]")
    or value == ""
  then
    return '"' .. value:gsub('\\', '\\\\'):gsub('"', '\\"') .. '"'
  end
  return value
end

-- ─── Path safety ──────────────────────────────────────────────────────────────

---@param path vault.path
---@return vault.path|nil safe_path, string|nil error_msg
function M.validate_path_in_vault(path)
  local config = require("vault.config")
  local raw_root = config.options.root
  if not raw_root or type(raw_root) ~= "string" or raw_root == "" then
    return nil, string.format("config.options.root is invalid: %s", tostring(raw_root))
  end
  local root = vim.fn.resolve(vim.fn.expand(raw_root))
  if not root or root == "" or root == "v:null" then
    return nil, string.format("config.options.root expanded to invalid path: %s", tostring(root))
  end
  local resolved = vim.fn.resolve(vim.fn.expand(path))
  -- Strict prefix check: path must start with root/ (not just contain root)
  local prefix = root:match("/$") and root or (root .. "/")
  if resolved ~= root and not vim.startswith(resolved, prefix) then
    return nil, string.format("Path %s escapes vault root %s", resolved, root)
  end
  return resolved, nil
end

-- ─── File I/O ─────────────────────────────────────────────────────────────────

---@param path vault.path
---@param lines string[]
---@return boolean ok, string|nil error_msg
function M.atomic_writefile(path, lines)
  local tmp = path .. ".vault_tmp"
  local ok = pcall(vim.fn.writefile, lines, tmp)
  if not ok then return false, "Failed to write temp file: " .. tmp end
  local rename_ok = vim.uv.fs_rename(tmp, path)
  if not rename_ok then
    pcall(vim.fn.delete, tmp)
    ok = pcall(vim.fn.writefile, lines, path)
    if not ok then return false, "Failed to write file: " .. path end
  end
  return true, nil
end

---@param path vault.path
---@return integer
function M.get_mtime(path)
  local stat = vim.uv.fs_stat(path)
  return stat and stat.mtime.sec or 0
end

-- ─── Frontmatter I/O ──────────────────────────────────────────────────────────

---@param path vault.path
---@param _columns string[]
---@return vault.bases.views.FrontmatterMap
function M.read_frontmatter_fields(path, _columns)
  ---@type vault.bases.views.FrontmatterMap
  local fields = {}
  local ok, lines = pcall(vim.fn.readfile, path, "", 50)
  if not ok then return fields end
  if not lines[1] or not lines[1]:match("^%-%-%-") then return fields end
  local fm_lines = {}
  for i = 2, #lines do
    if lines[i]:match("^%-%-%-") then break end
    table.insert(fm_lines, lines[i])
  end
  ---@type string|nil, vault.bases.views.FrontmatterList|nil
  local current_key, current_list = nil, nil
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
        current_key, current_list = key, nil
        value = vim.trim(value or "")
        if value == "" then
          current_list = {}
        elseif value:match("^%[") then
          local items = {}
          for item in value:gmatch("[%w/_%-%.]+") do table.insert(items, item) end
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

---@param path vault.path
---@param key string
---@param value vault.bases.views.FrontmatterValue|nil
function M.set_frontmatter_field(path, key, value)
  local safe_path, path_err = M.validate_path_in_vault(path)
  if not safe_path then log.error("SAFETY: %s", path_err); return end
  local ok, lines = pcall(vim.fn.readfile, safe_path)
  if not ok then return end
  local has_fm = lines[1] and lines[1]:match("^%-%-%-$")
  local fm_end
  if has_fm then
    for i = 2, math.min(#lines, 100) do
      if lines[i]:match("^%-%-%-$") then fm_end = i; break end
    end
    if not fm_end then return end
  else
    local new_lines = { "---" }
    if type(value) == "table" then
      table.insert(new_lines, key .. ":")
      for _, v in ipairs(value) do table.insert(new_lines, "  - " .. M.yaml_quote(tostring(v))) end
    elseif value ~= nil then
      table.insert(new_lines, key .. ": " .. M.yaml_quote(tostring(value)))
    end
    table.insert(new_lines, "---")
    for _, l in ipairs(lines) do table.insert(new_lines, l) end
    M.atomic_writefile(safe_path, new_lines)
    return
  end
  local body_line_count = #lines - fm_end
  local fm_lines = {}
  for i = 2, fm_end - 1 do table.insert(fm_lines, lines[i]) end
  local new_fm, skip, insert_pos = {}, false, nil
  for _, l in ipairs(fm_lines) do
    if skip then
      if l:match("^%s") then goto continue else skip = false end
    end
    if l:match("^" .. vim.pesc(key) .. ":") then
      insert_pos = #new_fm + 1; skip = true; goto continue
    end
    table.insert(new_fm, l)
    ::continue::
  end
  local new_lines = {}
  if value ~= nil then
    if type(value) == "table" then
      table.insert(new_lines, key .. ":")
      for _, v in ipairs(value) do table.insert(new_lines, "  - " .. M.yaml_quote(tostring(v))) end
    else
      table.insert(new_lines, key .. ": " .. M.yaml_quote(tostring(value)))
    end
  end
  if #new_lines > 0 then
    if insert_pos then
      for i = #new_lines, 1, -1 do table.insert(new_fm, insert_pos, new_lines[i]) end
    else
      for _, nl in ipairs(new_lines) do table.insert(new_fm, nl) end
    end
  end
  local result = { "---" }
  for _, l in ipairs(new_fm) do table.insert(result, l) end
  table.insert(result, "---")
  for i = fm_end + 1, #lines do table.insert(result, lines[i]) end
  local new_body_count = #result - (#new_fm + 2)
  if new_body_count ~= body_line_count then
    log.error("SAFETY: Aborting frontmatter write — body count mismatch (%d vs %d)",
      new_body_count, body_line_count)
    return
  end
  M.atomic_writefile(safe_path, result)
end

---@param path vault.path
---@param fields vault.bases.views.FrontmatterMap
function M.set_frontmatter_fields(path, fields)
  if not next(fields) then return end
  local safe_path, path_err = M.validate_path_in_vault(path)
  if not safe_path then log.error("SAFETY: %s", path_err); return end
  local ok, lines = pcall(vim.fn.readfile, safe_path)
  if not ok then return end
  local has_fm = lines[1] and lines[1]:match("^%-%-%-$")
  local fm_end
  if has_fm then
    for i = 2, math.min(#lines, 100) do
      if lines[i]:match("^%-%-%-$") then fm_end = i; break end
    end
    if not fm_end then
      for key, value in pairs(fields) do M.set_frontmatter_field(safe_path, key, value) end
      return
    end
  else
    local new_lines = { "---" }
    for key, value in pairs(fields) do
      if value ~= nil then
        if type(value) == "table" then
          table.insert(new_lines, key .. ":")
          for _, v in ipairs(value) do table.insert(new_lines, "  - " .. M.yaml_quote(tostring(v))) end
        else
          table.insert(new_lines, key .. ": " .. M.yaml_quote(tostring(value)))
        end
      end
    end
    table.insert(new_lines, "---")
    for _, l in ipairs(lines) do table.insert(new_lines, l) end
    M.atomic_writefile(safe_path, new_lines)
    return
  end
  local body_line_count = #lines - fm_end
  local fm_lines = {}
  for i = 2, fm_end - 1 do table.insert(fm_lines, lines[i]) end
  local remaining = vim.deepcopy(fields)
  local new_fm, skip, insert_positions = {}, false, {}
  for _, l in ipairs(fm_lines) do
    if skip then
      if l:match("^%s") then goto continue else skip = false end
    end
    local matched
    for key, _ in pairs(remaining) do
      if l:match("^" .. vim.pesc(key) .. ":") then matched = key; break end
    end
    if matched then
      insert_positions[matched] = #new_fm + 1; skip = true; goto continue
    end
    table.insert(new_fm, l)
    ::continue::
  end
  local inserts, appends = {}, {}
  for key, value in pairs(remaining) do
    local vlines = {}
    if value ~= nil then
      if type(value) == "table" then
        table.insert(vlines, key .. ":")
        for _, v in ipairs(value) do table.insert(vlines, "  - " .. M.yaml_quote(tostring(v))) end
      else
        table.insert(vlines, key .. ": " .. M.yaml_quote(tostring(value)))
      end
    end
    if insert_positions[key] then
      table.insert(inserts, { pos = insert_positions[key], lines = vlines })
    else
      for _, vl in ipairs(vlines) do table.insert(appends, vl) end
    end
  end
  table.sort(inserts, function(a, b) return a.pos > b.pos end)
  for _, ins in ipairs(inserts) do
    for i = #ins.lines, 1, -1 do table.insert(new_fm, ins.pos, ins.lines[i]) end
  end
  for _, al in ipairs(appends) do table.insert(new_fm, al) end
  local result = { "---" }
  for _, l in ipairs(new_fm) do table.insert(result, l) end
  table.insert(result, "---")
  for i = fm_end + 1, #lines do table.insert(result, lines[i]) end
  local new_body_count = #result - (#new_fm + 2)
  if new_body_count ~= body_line_count then
    log.error("SAFETY: Aborting batch frontmatter write — body count mismatch (%d vs %d)",
      new_body_count, body_line_count)
    return
  end
  M.atomic_writefile(safe_path, result)
end

-- ─── Value formatting ─────────────────────────────────────────────────────────

---@param value unknown
---@param col_name? string
---@return string
function M.fmt_value(value, col_name)
  if value == nil or value == vim.NIL or type(value) == "userdata" or value == "" then return M.get_empty_cell() end
  if type(value) == "boolean" then return value and "true" or "false" end
  if type(value) == "table" then
    if value._type == "date" then return os.date("%Y-%m-%d", value.epoch) or M.get_empty_cell() end
    if value._type == "duration" then return tostring(value.seconds) .. "s" end
    if col_name == "tags" then
      local parts = {}
      for _, v in ipairs(value) do
        if type(v) == "string" and v ~= "" then
          table.insert(parts, v:match("^#") and v or ("#" .. v))
        end
      end
      return #parts > 0 and table.concat(parts, " ") or M.get_empty_cell()
    end
    if #value > 0 then
      local parts = {}
      for _, v in ipairs(value) do table.insert(parts, tostring(v)) end
      return table.concat(parts, ", ")
    end
    return M.get_empty_cell()
  end
  return tostring(value)
end

---@param text string
---@param col_name string
---@return vault.bases.views.FrontmatterValue|nil
function M.parse_value(text, col_name)
  if text == M.get_empty_cell() or text == "" then return nil end
  if col_name == "tags" then
    local tags = {}
    for tag in text:gmatch("#([^%s#]+)") do table.insert(tags, tag) end
    return #tags > 0 and tags or nil
  end
  return text
end

return M
