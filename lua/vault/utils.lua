local M = {}
local config = require("vault.config")

---Generate a uuid e.g. 202301011924 (YYYYMMDDHHMM)
---@return string
function M.generate_uuid()
  local date = os.date("*t")
  local year = date.year
  local month = date.month
  local day = date.day
  local hour = date.hour
  local min = date.min
  return string.format("%04d%02d%02d%02d%02d", year, month, day, hour, min)
end

--- Format an absolute path to a relative path.
--- @param path string - The absolute path to format.
function M.to_relpath(path)
	local root_dir = config.dirs.root
  path = path:gsub(root_dir .. "/", "")
	return path
end

--- Format a relative path to an absolute path.
--- @param relpath string - The relative path to format.
function M.to_abs(relpath)
	local root_dir = config.dirs.root
	if relpath:sub(1, 1) == "/" then
		return root_dir .. relpath
	end
	return root_dir .. "/" .. relpath
end


---@param line string - The line to parse.
---@return table<string, string[]>? - Table of tag values and their notes paths. E.g., { ["status"] = { "foo.md", "bar.md" } }
function M.parse_line_for_tags(line)
  local tags_map_from_line = {}
	local path, line_with_tag = line:match("^(.*" .. config.ext .. "):(.+)")
	if path == nil or line_with_tag == nil then
		return
	end

	for tag_value in line:gmatch("#([A-Za-z0-9_][A-Za-z0-9-_/]+)") do
		if require('vault.tags.tag').is_tag(tag_value) == false then
			goto continue
		end

    if tags_map_from_line[tag_value] == nil then
      tags_map_from_line[tag_value] = {}
    end

    if not vim.tbl_contains(tags_map_from_line[tag_value], path) then
      table.insert(tags_map_from_line[tag_value], path)
    end
		::continue::
	end
    return tags_map_from_line
end

return M
