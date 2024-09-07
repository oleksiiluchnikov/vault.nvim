local error_formatter = require("vault.utils.fmt.error")
local TagChildData = require("vault.tags.tag.child.data")
local state = require("vault.core.state")

--- @type vault.Tag.constructor|vault.Tag
local Tag = state.get_global_key("class.vault.Tag") or require("vault.tags.tag")

--- @alias vault.Tag.children vault.Tag.Child[]

--- @class vault.Tag.Child: vault.Tag
--- @field Data vault.Tag.Child.Data
local TagChild = Tag:extend("VaultTagChild")

--- Create a new `VaultTagChild` instance.
---
--- @param parent vault.Tag|vault.Tag.Child
--- @param name vault.Tag.Child.Data.name
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
--- @param key string -- |vault.Tag.Data| key
--- @return any
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

--- ```lua
--- assert('foo/bar' == vault.Tag.Child.data.name)
--- ```
--- @alias vault.Tag.Child.Data.name vault.slug
--- @alias vault.Tag.Child.Data.root vault.Tag.Data.name
--- @alias vault.Tag.Child.Data.parent string - The parent tag of the tag. e.g., "foo" from "foo/bar".
--- @alias vault.Tag.Child.Data.children vault.Tag.children - The children of the tag
--- @alias vault.Tag.Child.Data.sources vault.Notes.Data.slugs - The notes slugs of notes with the tag.
--- @alias vault.Tag.Child.Data.documentation vault.Tag.Documentation
--- @alias vault.Tag.Child.Data.count number - The number of notes with the tag.

--- @alias vault.Tag.Child.constructor fun(parent: vault.Tag|vault.Tag.Child, name: string): vault.Tag.Child
--- @type vault.Tag.Child.constructor|vault.Tag.Child
local M = TagChild

state.set_global_key("class.vault.Tag.Child", M)
return M
