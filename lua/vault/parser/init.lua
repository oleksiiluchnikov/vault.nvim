local config = require("vault.config")
local utils = require("vault.utils")

local parser = {}

---@param line string - The line to parse.
---@return table<string, VaultMap.paths> - A map of tags to paths.
function parser.str_to_tags_with_paths(line)
  local tags_map_from_line = {}
  local path, line_with_tag = line:match("^(.*" .. config.ext .. "):(.+)")
  if path == nil or line_with_tag == nil then
    return {}
  end

  for tag_name in line:gmatch("#([A-Za-z0-9_][A-Za-z0-9-_/]+)") do
    if utils.is_tag(tag_name) == false then
      goto continue
    end

    if tags_map_from_line[tag_name] == nil then
      tags_map_from_line[tag_name] = {}
    end

    if tags_map_from_line[tag_name][path] == nil then
      tags_map_from_line[tag_name][path] = true
    end
    ::continue::
  end
  return tags_map_from_line
end

--- Catch that is not tag if:
--- It is inside link [[Note#header]]
--- It is inside code block ```
--- It is inside inline code ``
--- It is surrounded with brackets ()
---@param s string
---@return boolean
function parser.has_tag(s)
  local tag_pattern = [[#[A-Za-z0-9_][A-Za-z0-9-_/]+]]
  local link_pattern = "%[%[.+" .. tag_pattern .. ".+%]%]"
  if s:match(link_pattern) ~= nil then
    return false
  end
  local code_block_pattern = "```.*\n(.*" .. tag_pattern .. ".*)\n```"
  if s:match(code_block_pattern) ~= nil then
    return false
  end
  local inline_code_pattern = "`.*" .. tag_pattern .. ".*`"
  if s:match(inline_code_pattern) ~= nil then
    return false
  end
  local brackets_pattern = "[%(%[%{%<].*" .. tag_pattern .. ".*[%)%]%}%>]"
  if s:match(brackets_pattern) ~= nil then
    return false
  end

  return true
end

return parser
