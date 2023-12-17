local error_formatter = require("vault.utils.error_formatter")
local TagChildData = require("vault.tags.tag.child.data")
local state = require("vault.core.state")

---@type VaultTag.constructor|VaultTag
local Tag = state.get_global_key("_class.VaultTag") or require("vault.tags.tag")

---@alias VaultTagChildren VaultTagChild[]

---@class VaultTagChild: VaultTag
---@field data VaultTagChild.data
local TagChild = Tag:extend("VaultTagChild")

--- Create a new `VaultTagChild` instance.
---
---@param parent VaultTag|VaultTagChild
---@param name VaultTagChild.data.name
function TagChild:init(parent, name)
    if not parent then
        error(error_formatter.missing_parameter("parent"), 2)
    end

    if not name then
        error(error_formatter.missing_parameter("tag_name"), 2)
    end

    self.data = TagChildData({
        name = name,
        parent = parent.data.name,
        root = parent.data.root,
    })
end

--- Fetch the data if it is not already cached.
---
---@param key string -- `VaultTag.data` key
---@return any
function TagChild:__index(key)
    self[key] = rawget(self, key) or TagChildData[key](self)
    if self[key] == nil then
        error(
            "Invalid key: "
                .. vim.inspect(key)
                .. ". Valid keys: "
                .. vim.inspect(vim.tbl_keys(TagChildData))
        )
    end
    return self[key]
end

---@alias VaultTagChild.data.name string - The name of the tag. e.g., "foo/bar".
---@alias VaultTagChild.data.root string - The root tag of the tag. e.g., "foo" from "foo/bar".
---@alias VaultTagChild.data.parent string - The parent tag of the tag. e.g., "foo" from "foo/bar".
---@alias VaultTagChild.data.children VaultTagChildren - The children of the tag
---@alias VaultTagChild.data.sources VaultMap.slugs - The notes slugs of notes with the tag.
---@alias VaultTagChild.data.documentation VaultTag.documentation
---@alias VaultTagChild.data.count number - The number of notes with the tag.

---@alias VaultTagChild.constructor fun(parent: VaultTag|VaultTagChild, name: string): VaultTagChild
---@type VaultTagChild.constructor|VaultTagChild
local VaultTagChild = TagChild

state.set_global_key("_class.VaultTag.VaultTagChild", VaultTagChild)
return VaultTagChild
