local Object = require("nui.object")

-- local config = require("vault.config")
local TagDocumentation = require("vault.tags.tag.documentation")

---Fetch the children of a tag.
---@param tag_name string
---@return VaultTagChildren
local function fetch_children(tag_name)
  if not tag_name then
    error("fetch_children(tag_name) - tag_name is nil", 2)
  end

	local tag_name_parts = {}
	for part in tag_name:gmatch("[^/]+") do
		table.insert(tag_name_parts, part)
	end

	local root = tag_name_parts[1]

	table.remove(tag_name_parts, 1)
	local depth = #tag_name_parts

	local children = {}
	local current_node = children

	for i, child_name in ipairs(tag_name_parts) do
		local raw = tag_name:gsub("/[A-Za-z0-9_-]+$", "")
		if i == depth then
			raw = tag_name
		end

		current_node[child_name] = {
			raw = raw,
			name = child_name,
			root_name = root,
			parent_name = i > 1 and tag_name_parts[i - 1] or nil,
		}

		if i < depth then
			current_node = current_node[child_name]
		else
			current_node[child_name].children = {}
		end
	end
	return children
end

---@class VaultTagData
---@field name string - The name of the tag. e.g., "foo/bar".
---@field is_nested boolean - Whether the tag is nested. e.g., "foo/bar" is nested, "foo" is not.
---@field root string - The root tag of the tag. e.g., "foo" from "foo/bar".
---@field children VaultTagChildren[]
---@field notes_paths string[] - The paths to notes with the tag.
---@field documentation TagDocumentation
---@field count number - The number of notes with the tag.
local TagData = {}

---@param this table
function TagData:new(this)
  if not this then
    error("missing `this` parameter", 2)
  end

  if type(this) == "string" then
    this = { name = this }
  end

  if not this.name then
    error("missing `name` parameter", 2)
  end

  if not this.notes_paths or next(this.notes_paths) == nil then
    error("missing `notes_paths` parameter", 2)
  end

  if this.name:find("/") then
    this.is_nested = true
    this.root = this.name:match("^[^/]+")
  else
    this.is_nested = false
  end

  this.documentation = TagDocumentation(this.name)

  self = setmetatable(this, self)

  return self
end

function TagData:__index(key)
  if key == "children" then
    if self.is_nested then
      return fetch_children(self.name)
    else
      return {}
    end
  elseif key == "count" then
    return #self.notes_paths
  else
    return rawget(self, key)
  end
end

function TagData:__call(this)
  return TagData:new(this)
end


---@class VaultTagChildData: VaultTagData
---@field parent_name string
---@field siblings_names string[]
---@field root_name string
local TagChildData = {}

---@param parent VaultTag|VaultTagChild
---@param this table
---@return VaultTagChildData
function TagChildData:new(parent, this)
  if not parent then
    error("missing `parent` parameter", 2)
  end

  if not this then
    error("missing `this` parameter", 2)
  end

  if type(this) == "string" then
    this = { name = this }
  end

  if not this.name then
    error("missing `name` parameter", 2)
  end

  this.root_name = this.root_name or parent.root_name or parent.name

  if not this.root_name then
    error("missing `root_name` parameter", 2)
  end

  this.sibling_names = this.sibling_names or vim.tbl_keys(parent.children)

  this.documentation = TagDocumentation(this.name)

  self = setmetatable(this, self)

  return self
end

---@class VaultTagChildren: VaultTag -- List of TagChild
local TagChildren = Object("VaultTagChildren")

---@class VaultTagChild
---@field data VaultTagChildData
local TagChild = Object("VaultTagChild")

---Create a new tag child.
---@param parent VaultTag|VaultTagChild
---@param tag_name string
function TagChild:init(parent, tag_name)

  if not parent then
    error("missing `parent` parameter", 2)
  end

  if not tag_name then
    error("missing `tag_name` parameter", 2)
  end

  self.data = TagChildData({
		name = tag_name,
		parent_name = parent.data.name,
		root_name = parent.data.root_name,
		children = {},
	})
end

---@class VaultTag
local Tag = Object("VaultTag")

---Create a new tag.
---@param this table
function Tag:init(this)
  if not this then
    error("missing `this` parameter", 2)
  end

  if type(this) == "string" then
    this = { name = this }
  end

  if not this.name then
    error("missing `name` parameter", 2)
  end

  self.data = TagData:new(this)

  vim.tbl_deep_extend("force", self, this)
end

---Add a note path to the tag.
---@param path string
function Tag:add_path(path)
  if not vim.tbl_contains(self.data.notes_paths, path) then
    vim.list_extend(self.data.notes_paths, { path })
  end
end

function Tag:__index(key)
  if key == "children" then
    if self.data.is_nested then
      return fetch_children(self.data.name)
    else
      return {}
    end
  elseif key == "count" then
    return #self.data.notes_paths
  else
    return rawget(self, key)
  end
end

---@alias VaultTag.constructor fun(this: VaultTag|table|string): VaultTag
---@type VaultTag.constructor|VaultTag
local VaultTag = Tag

return VaultTag
