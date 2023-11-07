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
---@param tags_values table - The table to store the tag values.
---@return string[]? - Array of tag values.
function M.parse_line_for_tags(line, tags_values)
	local path, line_with_tag = line:match("^(.*" .. config.ext .. "):(.+)")
	if path == nil or line_with_tag == nil then
		return
	end

	for tag_value in line:gmatch("#([A-Za-z0-9_][A-Za-z0-9-_/]+)") do
		if require('vault.tag').is_tag(tag_value) == false then
			goto continue
		end

		if tags_values[tag_value] == nil then
			-- Initialize tags_values[tag_value] as table
			tags_values[tag_value] = { path }
		elseif not vim.tbl_contains(tags_values[tag_value], path) then
			vim.list_extend(tags_values[tag_value], { path })
		end
		-- elseif not vim.tbl_contains(tags_values[tag_value], path) then
		--     vim.tbl_extend("force", tags_values[tag_value], { path })
		-- end
		::continue::
	end
	return tags_values
end

return M
