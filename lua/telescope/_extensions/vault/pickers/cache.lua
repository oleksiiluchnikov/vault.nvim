local config = require("vault.config")
local state = require("vault.core.state")

local ROOT_KEY = "cache.telescope._extensions.vault.pickers"

local M = {
    ROOT_KEY = ROOT_KEY,
}

--- @return string
local function current_root()
    local options = config.options or {}
    return tostring(options.root or "")
end

--- @return table<string, { root: string, value: any }>
local function cache_root()
    local cached = state.get_global_key(ROOT_KEY)
    if type(cached) == "table" then
        return cached
    end

    cached = {}
    state.set_global_key(ROOT_KEY, cached)
    return cached
end

--- @param key string
--- @return any
function M.get(key)
    local cached = state.get_global_key(ROOT_KEY)
    if type(cached) ~= "table" then
        return nil
    end

    local entry = cached[key]
    if type(entry) ~= "table" or entry.root ~= current_root() then
        return nil
    end

    return entry.value
end

--- @param key string
--- @param value any
--- @return any
function M.set(key, value)
    local cached = cache_root()
    cached[key] = {
        root = current_root(),
        value = value,
    }
    return value
end

--- @param key string
--- @param producer fun(): any
--- @return any
function M.get_or_set(key, producer)
    local cached = M.get(key)
    if cached ~= nil then
        return cached
    end

    return M.set(key, producer())
end

return M
