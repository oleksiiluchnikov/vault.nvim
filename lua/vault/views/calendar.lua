local function target()
    return require("vault.bases.views.calendar")
end

return setmetatable({}, {
    __index = function(_, key)
        return target()[key]
    end,
    __newindex = function(_, key, value)
        target()[key] = value
    end,
    __call = function(_, ...)
        return target()(...)
    end,
})
