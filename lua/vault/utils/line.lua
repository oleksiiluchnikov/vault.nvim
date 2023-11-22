local config = require("vault.config")
local utils = require("vault.utils")
local M = {}

---Catch that is not tag if:
---It is inside link [[Note#header]]
---It is inside code block ```
---It is inside inline code ``
---It is surrounded with brackets ()
---@param line string
---@return boolean
function M.has_tag(line)
	local tag_pattern = [[#[A-Za-z0-9_][A-Za-z0-9-_/]+]]
	local link_pattern = "%[%[.+" .. tag_pattern .. ".+%]%]"
	if line:match(link_pattern) ~= nil then
		return false
	end
	local code_block_pattern = "```.*\n(.*" .. tag_pattern .. ".*)\n```"
	if line:match(code_block_pattern) ~= nil then
		return false
	end
	local inline_code_pattern = "`.*" .. tag_pattern .. ".*`"
	if line:match(inline_code_pattern) ~= nil then
		return false
	end
	local brackets_pattern = "[%(%[%{%<].*" .. tag_pattern .. ".*[%)%]%}%>]"
	if line:match(brackets_pattern) ~= nil then
		return false
	end

	return true
end

---@param line string - The line to parse.
---@return table<string, string[]>? - Table of tag names and their notes paths. E.g., { ["status"] = { "foo.md", "bar.md" } }
function M.parse_line_for_tags(line)
  local tags_map_from_line = {}
	local path, line_with_tag = line:match("^(.*" .. config.ext .. "):(.+)")
	if path == nil or line_with_tag == nil then
		return
	end

	for tag_name in line:gmatch("#([A-Za-z0-9_][A-Za-z0-9-_/]+)") do
		if utils.is_tag(tag_name) == false then
			goto continue
		end

    if tags_map_from_line[tag_name] == nil then
      tags_map_from_line[tag_name] = {}
    end

    if not vim.tbl_contains(tags_map_from_line[tag_name], path) then
      table.insert(tags_map_from_line[tag_name], path)
    end
		::continue::
	end
    return tags_map_from_line
end
return M
