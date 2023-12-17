local data = {}

---@param tags VaultTags
data.nested = function(tags)
  for slug, tag in pairs(tags.map) do
    if next(tag.data.children) == nil then
      tags.map[slug] = nil
    end
  end
  return tags
end

return data
