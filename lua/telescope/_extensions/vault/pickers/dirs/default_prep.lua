local picker_cache = require("telescope._extensions.vault.pickers.cache")
local state = require("vault.core.state")
local link_index = require("vault.notes.link_index")

local CACHE_KEY = "dirs.default"

local M = {}

---@class vault.DirsPickerPrepared
---@field by_count vault.Dirs.list
---@field dir_counts table<string, integer>

---@param paths table<string, table>
---@param dir_counts table<string, integer>
---@return nil
local function count_notes_per_dir(paths, dir_counts)
    for slug, _ in pairs(paths) do
        local start = 1
        while true do
            local slash = string.find(slug, "/", start, true)
            if not slash then
                break
            end

            local relpath = string.sub(slug, 1, slash - 1)
            if dir_counts[relpath] ~= nil then
                dir_counts[relpath] = dir_counts[relpath] + 1
            end
            start = slash + 1
        end
    end
end

---@return vault.DirsPickerPrepared
local function build_default_prep()
    local dirs = state.get_global_key("dirs") or require("vault.dirs")()
    local list = dirs:list()
    local counts = {} --- @type table<string, integer>
    for _, dir in ipairs(list) do
        counts[dir.data.relpath] = 0
    end

    count_notes_per_dir(link_index.paths(), counts)

    return {
        by_count = list,
        dir_counts = counts,
    }
end

---@return vault.DirsPickerPrepared
function M.get_or_prepare()
    return picker_cache.get_or_set(CACHE_KEY, build_default_prep)
end

return M
