local TagDocumentation = require("vault.tags.tag.documentation")
--- ```lua
--- assert('foo/bar' == vault.Tag.data.name)
--- ```
--- @alias vault.Tag.Data.name string - The name of the tag. e.g., "foo/bar".
--- @alias vault.Tag.Data.root string - The root tag of the tag. e.g., "foo" from "foo/bar".
--- @alias vault.Tag.SourceMap vault.Sources.map
--- @alias vault.Tag.Data.children vault.Tag.children - The children of the tag
--- @alias vault.Tag.Data.sources vault.Tag.SourceMap - Source note slugs and their occurrence sets.
--- @alias vault.Tag.Data.count integer - The number of notes with the tag.
--- @alias vault.Tag.Data.occurences integer - The total number of occurrences across all source notes.
--- @class vault.Tag.Child
--- @field raw vault.Tag.Data.name
--- @field name string
--- @field root_name vault.Tag.Data.root
--- @field parent_name string|nil
--- @field children vault.Tag.children
--- @alias vault.Tag.children table<string, vault.Tag.Child>
--- @class vault.Tag.Data.partial
--- @field name? vault.Tag.Data.name
--- @field root? vault.Tag.Data.root
--- @field is_nested? boolean
--- @field children? vault.Tag.children
--- @field sources? vault.Tag.SourceMap
--- @field documentation? vault.Tag.Documentation
--- @field count? integer
--- @field occurences? integer

--- @class vault.Tag.Data
--- @field name vault.Tag.Data.name - The name of the tag. e.g., "foo/bar".
--- @field root vault.Tag.Data.root - The root tag of the tag. e.g., "foo" from "foo/bar".
--- @field is_nested boolean - Whether the tag is nested. e.g., "foo/bar" is nested, "foo" is not.
--- @field children vault.Tag.children
--- @field sources vault.Tag.SourceMap - The notes slugs of notes with the tag.
--- @field documentation vault.Tag.Documentation
--- @field count integer - The number of notes with the tag.
--- @field occurences integer - The total number of line-level occurrences across all notes.

--- @class vault.Tag.Data.parser
--- @field sources fun(tag_data: vault.Tag.Data): vault.Tag.SourceMap - The notes slugs of notes with the tag.
--- @field children fun(tag_Data: vault.Tag.Data): vault.Tag.children - The children of the tag.
---@type vault.Tag.Data.parser
local data = {}

--- @param tag_data vault.Tag.Data
--- @return vault.Tag.Data.name
data.name = function(tag_data)
    return tag_data.name
end

--- No-op: sources are populated by the scanner, not lazily computed.
--- @param _tag_data vault.Tag.Data
--- @return nil
data.sources = function(_tag_data) end

--- @param tag_data vault.Tag.Data
--- @return vault.Tag.Documentation
data.documentation = function(tag_data)
    return TagDocumentation(tag_data.name)
end

--- Scann the children of a tag.
--- @param tag_Data vault.Tag.Data
--- @return vault.Tag.children
data.children = function(tag_data)
    local tag_name = tag_data.name
    if not tag_name then
        error("scann_children(tag_name) - tag_name is nil", 2)
    end

    if tag_name:find("/") == nil then
        return {}
    end

    --- @type string[]
    local tag_name_parts = {}
    for part in tag_name:gmatch("[^/]+") do
        table.insert(tag_name_parts, part)
    end

    local root = tag_name_parts[1]

    table.remove(tag_name_parts, 1)
    local depth = #tag_name_parts

    --- @type vault.Tag.children
    local children = {}
    --- @type vault.Tag.children
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
