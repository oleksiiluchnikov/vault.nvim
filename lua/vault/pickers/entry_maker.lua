local entry_makers = {}
--- @param tag vault.Tag
--- @return vault.TelescopeEntry
entry_maker.tag = function(tag)
    return {
        value = tag,
        ordinal = tag.data.name .. " " .. tostring(tag.data.count),
        display = make_display,
    }
end
