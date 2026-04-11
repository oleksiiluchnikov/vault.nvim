local picker_cache = require("telescope._extensions.vault.pickers.cache")
local state = require("vault.core.state")

local CACHE_KEY = "tags.default"

local M = {}

---@return vault.Tags.list
local function build_default_prep()
    local tags = state.get_global_key("tags") or require("vault.tags")()
    local list = tags:list()
    table.sort(list, function(a, b)
        return a.data.count > b.data.count
    end)
    return list
end

---@return vault.Tags.list
function M.get_or_prepare()
    return picker_cache.get_or_set(CACHE_KEY, build_default_prep)
end

return M
