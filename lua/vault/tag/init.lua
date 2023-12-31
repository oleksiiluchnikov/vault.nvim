local config = require("vault.config")
local TagDocumentation = require("vault.tag.documentation")

---@class Tag
---@field value string - The value of the tag. e.g., "foo/bar".
---@field is_nested boolean - Whether the tag is nested. e.g., "foo/bar" is nested, "foo" is not.
---@field root string - The root tag of the tag. e.g., "foo" from "foo/bar".
---@field children TagChildren[]|function
---@field notes_paths string[]|function - The paths to notes with the tag.
---@field documentation TagDocumentation
---@field count number|function - The number of notes with the tag.
local Tag = {}

--- Create a new tag.
--- @param obj table
--- @return Tag
function Tag:new(obj)
	local is_nested = false
	local root = obj.value:match("^[^/]+") -- Get the root tag. e.g., "foo" from "foo/bar". if no "/" found, return nil
	if root ~= nil then
		is_nested = true
	end

	local tag = {
		value = obj.value,
		is_nested = is_nested,
		root = root,
		notes_paths = obj.notes_paths,
		children = self:children(obj.value),
		documentation = TagDocumentation:new(obj.value),
	}
	tag.count = #tag.notes_paths

	setmetatable(tag, self)
	self.__index = self
	return tag
end

---Fetch {notes} with specified tag.
---@param tag_value string
---@return string[]
---@see Tag.notes_paths
function Tag:notes_paths(tag_value)
	tag_value = tag_value or self.value
	local notes_paths = require("vault.list").notes_paths()
	local notes_paths__with_tag = {}
	for _, note_path in ipairs(notes_paths) do
		local f = io.open(note_path, "r")
		if f then
			local content = f:read("*all")
			f:close()
			for tag in content:gmatch(config.search_pattern.tag) do
				if tag == tag_value then
					table.insert(notes_paths__with_tag, note_path)
				end
			end
		end
	end
	return notes_paths
end

---Fetch the children of a tag.
---@param value string
---@return TagChildren
function Tag:children(value)
	value = value or self.value

	if value:find("/") == nil then
		return {}
	end

	local value_parts = {}
	for part in value:gmatch("[^/]+") do
		table.insert(value_parts, part)
	end

	local root = value_parts[1]

	table.remove(value_parts, 1)
	local depth = #value_parts

	local children = {}
	local current_node = children

	for i, child_value in ipairs(value_parts) do
		local raw = value:gsub("/[A-Za-z0-9_-]+$", "")
		if i == depth then
			raw = value
		end

		current_node[child_value] = {
			raw = raw,
			value = child_value,
			root_value = root,
			parent_value = i > 1 and value_parts[i - 1] or nil,
		}

		if i < depth then
			current_node = current_node[child_value]
		else
			current_node[child_value].children = {}
		end
	end
	return children
end

function Tag.test()
	vim.cmd("lua package.loaded['vault.tag'] = nil")
	vim.cmd("lua package['vault.tag'] = nil")
end

---@class TagChild
---@field value string
---@field parent_value Tag|TagChild
---@field root_value string
---@field children TagChild[]
local TagChild = {}

---Create a new tag child.
---@param parent Tag|TagChild
---@param value string
---@return TagChild
function TagChild:new(parent, value)
	local tag_child = {
		value = value,
		parent_value = parent.value,
		root_value = parent.root_value,
		children = {},
	}
	setmetatable(tag_child, self)
	self.__index = self
	return tag_child
end

--- Catch that is not tag if:
--- It is inside link [[Note#header]]
--- It is inside code block ```
--- It is inside inline code ``
--- It is surrounded with brackets ()
---@param context string
---@return boolean
function Tag.is_tag_context(context)
	local tag_pattern = [[#[A-Za-z0-9_][A-Za-z0-9-_/]+]]
	local link_pattern = "%[%[.+" .. tag_pattern .. ".+%]%]"
	if context:match(link_pattern) ~= nil then
		return false
	end
	local code_block_pattern = "```.*\n(.*" .. tag_pattern .. ".*)\n```"
	if context:match(code_block_pattern) ~= nil then
		return false
	end
	local inline_code_pattern = "`.*" .. tag_pattern .. ".*`"
	if context:match(inline_code_pattern) ~= nil then
		return false
	end
	local brackets_pattern = "[%(%[%{%<].*" .. tag_pattern .. ".*[%)%]%}%>]"
	if context:match(brackets_pattern) ~= nil then
		return false
	end

	return true
end

function Tag.is_tag(tag_value)
	local raw_tag = "#" .. tag_value
	if not config.tag.valid.hex then
		local hex_pattern = "(#[A-Fa-f0-9]+){3,6}"
		if raw_tag:match(hex_pattern) ~= nil then
			return false
		end
	end
	return true
end

---@class TagChildren: Tag
local TagChildren = {}

return Tag
