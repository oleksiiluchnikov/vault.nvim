-- Shared helpers for vault grid and kanban view adapters.

local M = {}

local log = require("vault.log").scope("views.shared")

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

M.FILE_IMPLICIT_PROPS = {
  "file.name", "file.folder", "file.path", "file.ext",
  "file.ctime", "file.mtime", "file.size",
  "file.body", "file.slug",
  "file.inlinks", "file.outlinks", "file.headings",
}

local EMPTY_CELL

function M.get_empty_cell()
  if not EMPTY_CELL then
    local ok, cfg = pcall(require, "vault.config")
    EMPTY_CELL = (ok and cfg.options.bases and cfg.options.bases.empty_cell) or "_"
  end
  return EMPTY_CELL
end

function M.reset_empty_cell()
  EMPTY_CELL = nil
end

function M.normalize_col(col)
  if col:match("^note%.") then col = "file." .. col:sub(6) end
  if col == "dir"  then return "file.folder" end
  if col == "body" then return "file.body"   end
  if col == "name" then return "file.name"   end
  return col
end

function M.base_key_to_col(key)
  key = M.normalize_col(key)
  if key:match("^formula%.") then return key, true end
  if M.READONLY_FILE_COLS[key] then return key, true end
  return key, false
end

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
  local prefix = root:match("/$") and root or (root .. "/")
  if resolved ~= root and not vim.startswith(resolved, prefix) then
    return nil, string.format("Path %s escapes vault root %s", resolved, root)
  end
  return resolved, nil
end

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

function M.get_mtime(path)
  local stat = vim.uv.fs_stat(path)
  return stat and stat.mtime.sec or 0
end

function M.read_frontmatter_fields(path, _columns)
  local fields = {}
  local ok, lines = pcall(vim.fn.readfile, path, "", 50)
  if not ok then return fields end
  if not lines[1] or not lines[1]:match("^%-%-%-") then return fields end
  local fm_lines = {}
  for i = 2, #lines do
    if lines[i]:match("^%-%-%-") then break end
    table.insert(fm_lines, lines[i])
  end
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

function M.fmt_value(value, col)
  if value == nil then return M.get_empty_cell() end
  if type(value) == "boolean" then return tostring(value) end
  if type(value) == "table" and value._type == "date" and value.epoch then
    return os.date("%Y-%m-%d", value.epoch)
  end
  if type(value) == "table" then
    if vim.tbl_isempty(value) then return M.get_empty_cell() end
    if col == "tags" then
      local out = {}
      for _, item in ipairs(value) do
        local s = tostring(item)
        if not vim.startswith(s, "#") then s = "#" .. s end
        out[#out + 1] = s
      end
      return table.concat(out, " ")
    end
    local out = {}
    for _, item in ipairs(value) do out[#out + 1] = tostring(item) end
    return table.concat(out, ", ")
  end
  local s = tostring(value)
  if s == "" then return M.get_empty_cell() end
  return s
end

function M.parse_value(text, col)
  text = vim.trim(text or "")
  if text == "" or text == M.get_empty_cell() then return nil end
  if col == "tags" then
    local tags = {}
    for tag in text:gmatch("#([^%s,]+)") do
      tags[#tags + 1] = tag
    end
    if #tags == 0 then return nil end
    return tags
  end
  return text
end

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
    vim.list_extend(new_lines, lines)
    M.atomic_writefile(safe_path, new_lines)
    return
  end
  local start_idx = 2
  local end_idx = fm_end - 1
  local out = { unpack(lines, 1, start_idx - 1) }
  local replaced = false
  local i = start_idx
  while i <= end_idx do
    local line = lines[i]
    local existing_key = line:match("^([%w_%-]+):")
    if existing_key == key then
      replaced = true
      i = i + 1
      while i <= end_idx and lines[i]:match("^%s+%-%s+") do i = i + 1 end
      if value ~= nil then
        if type(value) == "table" then
          table.insert(out, key .. ":")
          for _, v in ipairs(value) do table.insert(out, "  - " .. M.yaml_quote(tostring(v))) end
        else
          table.insert(out, key .. ": " .. M.yaml_quote(tostring(value)))
        end
      end
    else
      table.insert(out, line)
      i = i + 1
    end
  end
  if not replaced and value ~= nil then
    if type(value) == "table" then
      table.insert(out, key .. ":")
      for _, v in ipairs(value) do table.insert(out, "  - " .. M.yaml_quote(tostring(v))) end
    else
      table.insert(out, key .. ": " .. M.yaml_quote(tostring(value)))
    end
  end
  table.insert(out, "---")
  vim.list_extend(out, { unpack(lines, fm_end + 1) })
  M.atomic_writefile(safe_path, out)
end

function M.set_frontmatter_fields(path, updates)
  for key, value in pairs(updates) do
    M.set_frontmatter_field(path, key, value)
  end
end

return M
