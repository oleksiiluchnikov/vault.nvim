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


return M
