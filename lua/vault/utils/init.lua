local utils = {}
local config = require("vault.config")

---Generate a uuid e.g. 202301011924 (YYYYMMDDHHMM)
---@return string
function utils.generate_uuid()
  return tostring(os.date("%Y%m%d%H%M"))
end

---Format an absolute path to a relative path.
---@param path string - The absolute path to format.
---@return string - The formatted relative path.
function utils.to_relpath(path)
  if type(path) ~= "string" then
    error("path must be a string, got " .. type(path))
  end
	local root_dir = config.dirs.root
  path = path:gsub(root_dir .. "/", "")
	return path
end

---Format a relative path to an absolute path.
---@param relpath string - The relative path to format.
---@return string - The formatted `absolute path`.
function utils.to_abs(relpath)
	local root_dir = config.dirs.root
	if relpath:sub(1, 1) == "/" then
		return root_dir .. relpath
	end
	return root_dir .. "/" .. relpath
end

---Check if the value is a tag.
function utils.is_tag(tag_name)
	local raw_tag = "#" .. tag_name
	if not config.tags.valid.hex then
		local hex_pattern = "(#[A-Fa-f0-9]+){3,6}"
		if raw_tag:match(hex_pattern) ~= nil then
			return false
		end
	end
	return true
end

---@param tbl table - The table to check.
---@param expected_type string - The expected type.
---| "string" - The expected type is string.
---| "table" - The expected type is table.
---| "number" - The expected type is number.
---| "boolean" - The expected type is boolean.
---| "function" - The expected type is function.
---| "thread" - The expected type is thread.
---| "userdata" - The expected type is userdata.
---@return boolean
function utils.is_flatten_list(tbl, expected_type)
  if not tbl then
    error("`tbl` argument is required.")
  end

  if type(tbl) ~= "table" then
    error("`tbl` argument must be a table, got " .. type(tbl))
  end

  if not expected_type then
    error("`expected_type` argument is required.")
  end

  if type(expected_type) ~= "string" then
    error("`expected_type` argument must be a string, got " .. type(expected_type))
  end

  for _, v in ipairs(tbl) do
    if type(v) == expected_type then
      return true
    end
  end

  return false
end

return utils
