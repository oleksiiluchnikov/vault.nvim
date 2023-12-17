local TagDocumentation = require("vault.tags.tag.documentation")
---@alias VaultTag.data.name string - The name of the tag. e.g., "foo/bar".
---@alias VaultTag.data.root string - The root tag of the tag. e.g., "foo" from "foo/bar".
---@alias VaultTag.data.children VaultTagChildren - The children of the tag
---@alias VaultTag.data.sources VaultMap.slugs - The notes slugs of notes with the tag.
---@alias VaultTag.data.documentation VaultTag.documentation
---@alias VaultTag.data.count number - The number of notes with the tag.

---@class VaultTag.data
---@field name VaultTag.data.name - The name of the tag. e.g., "foo/bar".
---@field root VaultTag.data.root - The root tag of the tag. e.g., "foo" from "foo/bar".
---@field is_nested boolean - Whether the tag is nested. e.g., "foo/bar" is nested, "foo" is not.
---@field children VaultTagChildren[]
---@field sources VaultMap.sources - The notes slugs of notes with the tag.
---@field documentation VaultTag.documentation
---@field count number - The number of notes with the tag.

---@class VaultTag.data.parser
---@field sources fun(tag_data: VaultTag.data): VaultMap.slugs - The notes slugs of notes with the tag.
---@field children fun(tag_data: VaultTag.data): VaultTagChildren - The children of the tag.
local data = {}

data.name = function(tag_data)
    return tag_data.name
end

data.sources = function(tag_data) end

data.documentation = function(tag_data)
    return TagDocumentation(tag_data.name)
end

--- Fetch the children of a tag.
---@param tag_data VaultTag.data
---@return VaultTagChildren
data.children = function(tag_data)
    local tag_name = tag_data.name
    if not tag_name then
        error("fetch_children(tag_name) - tag_name is nil", 2)
    end

    if tag_name:find("/") == nil then
        return {}
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

return data
