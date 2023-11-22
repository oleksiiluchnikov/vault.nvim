---FrontmatterField class
---@class NoteFrontmatterField - A single field in a frontmatter.
---@field key string - The key of the field. E.g. "date_created"
---@field value string - The value of the field. E.g. "2024-01-01"
local FrontmatterField = {}

---Create a new FrontmatterField object.
---@param this table - The table to use as the object. If nil, a new table is created.
---@return NoteFrontmatterField
function FrontmatterField:new(this)
	this = this or {}
	setmetatable(this, self)
	self.__index = this
	return this
end

---Create a new FrontmatterField object from a string.
---@param line string - The string to parse.
---@return NoteFrontmatterField|nil
function FrontmatterField:from_string(line)
	local key, value = line:match("^%s*([%w_]+)%s*:%s*(.*)$")
	if key == nil then
		return nil
	end
	return self:new({ key = key, value = value })
end

---Convert the FrontmatterField to a string.
---@return string
function FrontmatterField:__tostring()
	return self.key .. ": " .. self.value
end

---Frontmatter class
---@class NoteFrontmatter
local NoteFrontmatter = {}

---Create a new NoteFrontmatter object.
---@param this table - The table to use as the object. If nil, a new table is created.
---@return NoteFrontmatter
function NoteFrontmatter:new(this)
  if type(this) == "string" then
    this = self:decode(this)
    return this
  end
	this = this or {}
	setmetatable(this, self)
	self.__index = self
	return this
end

---Decode a frontmatter string to a table.
---@param text string - The frontmatter string to decode.
---@return NoteFrontmatter - The decoded frontmatter.
function NoteFrontmatter:decode(text)
	local lines = vim.split(text, "\n")
	for _, line in ipairs(lines) do
		---@type NoteFrontmatterField|nil
		local field = FrontmatterField:from_string(line)
		if field ~= nil then
			self[field.key] = field.value
		end
	end
	return self
end

function NoteFrontmatter:to_table()
	local tbl = {}
	for k, v in pairs(self) do
		if type(k) ~= "function" then
			tbl[k] = v
		end
	end
	return tbl
end

---Encode a table to frontmatter string.
---@param tbl table? - The table to encode.
---@return string - The encoded frontmatter.
function NoteFrontmatter:encode(tbl)
	tbl = tbl or self:to_table()
	local frontmatter = "---\n"
	for key, value in pairs(tbl) do
		if type(value) == "table" then
			value = vim.inspect(value)
		end
		if type(value) == "boolean" then
			value = tostring(value)
		end
    if type(value) == "number" then
      value = tostring(value)
    end
		frontmatter = frontmatter .. key .. ": " .. value .. "\n"
	end

	frontmatter = frontmatter .. "---\n"
	return frontmatter
end

---Convert the NoteFrontmatter to a string.
---@return string
function NoteFrontmatter:__tostring()
	return self:encode()
end

function NoteFrontmatter:__call(content)
	return self:decode(content)
end

NoteFrontmatter = setmetatable(NoteFrontmatter, NoteFrontmatter)

return NoteFrontmatter
