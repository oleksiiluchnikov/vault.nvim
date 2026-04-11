local picker_cache = require("telescope._extensions.vault.pickers.cache")
local state = require("vault.core.state")

local CACHE_KEY = "properties.default"

local M = {}

---@class vault.PropertiesPickerPrepared
---@field list vault.Properties.list
---@field map vault.Properties.map

---@return vault.PropertiesPickerPrepared
local function build_default_prep()
    local properties = state.get_global_key("properties") or require("vault.properties")()
    local list = properties:list()
    table.sort(list, function(a, b)
        return a.data.count > b.data.count
    end)
    return {
        list = list,
        map = properties.map,
    }
end

---@return vault.PropertiesPickerPrepared
function M.get_or_prepare()
    return picker_cache.get_or_set(CACHE_KEY, build_default_prep)
end

return M
