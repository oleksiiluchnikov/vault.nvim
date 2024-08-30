--- @class vault.TagsData
local data = {}

--- @param tags vault.Tags
--- @return vault.Tags
data.nested = function(tags)
    for slug, tag in pairs(tags.map) do
        if next(tag.data.children) == nil then
            tags.map[slug] = nil
        end
    end
    return tags
end

return data
