---@class vault.telescope.NoteLinkCounts
---@field outlinks integer
---@field inlinks integer
---@field dangling integer

local M = {}

---@param notes vault.Note[]
---@return table<string, vault.telescope.NoteLinkCounts>
function M.collect(notes)
    local counts = {}
    local inbound_sources = {}

    for _, note in ipairs(notes or {}) do
        local slug = note.data.slug
        if type(slug) == "string" and slug ~= "" then
            counts[slug] = {
                outlinks = 0,
                inlinks = 0,
                dangling = 0,
            }
            inbound_sources[slug] = {}
        end
    end

    local wikilinks = require("vault.wikilinks")()
    for _, wikilink in pairs(wikilinks.map or {}) do
        local target = wikilink.data.target
        local unresolved = target == nil or target == ""
        for source_slug, _ in pairs(wikilink.data.sources or {}) do
            local source_counts = counts[source_slug]
            if source_counts then
                source_counts.outlinks = source_counts.outlinks + 1
                if unresolved then
                    source_counts.dangling = source_counts.dangling + 1
                end
            end
            if target and inbound_sources[target] then
                inbound_sources[target][source_slug] = true
            end
        end
    end

    for slug, sources in pairs(inbound_sources) do
        if counts[slug] then
            counts[slug].inlinks = vim.tbl_count(sources)
        end
    end

    return counts
end

---@param counts vault.telescope.NoteLinkCounts|nil
---@return string
function M.format(counts)
    counts = counts or { outlinks = 0, inlinks = 0, dangling = 0 }
    return string.format("out %d  in %d  dang %d", counts.outlinks, counts.inlinks, counts.dangling)
end

---@param counts vault.telescope.NoteLinkCounts|nil
---@return string, string, string
function M.columns(counts)
    counts = counts or { outlinks = 0, inlinks = 0, dangling = 0 }
    return string.format("out %d", counts.outlinks),
        string.format("in %d", counts.inlinks),
        string.format("dang %d", counts.dangling)
end

return M
