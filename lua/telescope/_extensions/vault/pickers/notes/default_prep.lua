local picker_cache = require("telescope._extensions.vault.pickers.cache")
local state = require("vault.core.state")
local link_index = require("vault.notes.link_index")
local note_stats = require("telescope._extensions.vault.pickers.notes.stats")

local CACHE_KEY = "notes.default"

local M = {}

---@return { link_counts: table<string, vault.NotePickerLinkCounts>, notes: vault.Notes, results: vault.Note[] }
local function build_default_prep()
    local notes = state.get_global_key("notes") or require("vault.notes")()
    local wikilinks_map = link_index.wikilinks()
    local results = notes:list()
    local link_counts = note_stats.collect(results, wikilinks_map)

    local ftime = {} --- @type table<string, integer>
    for _, note in ipairs(results) do
        ftime[note.data.path] = vim.fn.getftime(note.data.path)
    end

    table.sort(results, function(a, b)
        return ftime[a.data.path] < ftime[b.data.path]
    end)

    return {
        link_counts = link_counts,
        notes = notes,
        results = results,
    }
end

---@return { link_counts: table<string, vault.NotePickerLinkCounts>, notes: vault.Notes, results: vault.Note[] }
function M.get_or_prepare()
    return picker_cache.get_or_set(CACHE_KEY, build_default_prep)
end

return M
