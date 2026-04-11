local state = require("vault.core.state")

local CACHE_KEY = "notes.link_index"

--- @class vault.NotesLinkIndex
--- @field paths table<string, table>
--- @field wikilinks table<string, vault.Wikilink>
--- @field outlinks_by_source table<string, vault.Wikilinks.map>
--- @field inlinks_by_target table<string, table<string, vault.Wikilink[]>>
--- @field targets table<string, true>
--- @field has_inlinks table<string, true>
--- @field has_outlinks table<string, true>
--- @field has_unresolved_outlinks table<string, true>

local M = {
    CACHE_KEY = CACHE_KEY,
}

--- @param wikilinks table<string, vault.Wikilink>
--- @return vault.NotesLinkIndex
local function build_index(wikilinks)
    --- @type vault.NotesLinkIndex
    local index = {
        has_inlinks = {},
        has_outlinks = {},
        has_unresolved_outlinks = {},
        inlinks_by_target = {},
        outlinks_by_source = {},
        paths = {},
        targets = {},
        wikilinks = wikilinks,
    }

    for _, wikilink in pairs(wikilinks) do
        local data = wikilink.data or {}
        local sources = data.sources or {}
        local target = data.target
        local resolved = type(target) == "string" and target ~= ""

        if resolved then
            index.targets[target] = true
        end

        for source, _ in pairs(sources) do
            local outlinks = index.outlinks_by_source[source]
            if outlinks == nil then
                outlinks = {}
                index.outlinks_by_source[source] = outlinks
            end
            outlinks[data.slug] = wikilink
            index.has_outlinks[source] = true

            if resolved then
                local inlinks = index.inlinks_by_target[target]
                if inlinks == nil then
                    inlinks = {}
                    index.inlinks_by_target[target] = inlinks
                end

                local source_links = inlinks[source]
                if source_links == nil then
                    source_links = {}
                    inlinks[source] = source_links
                end

                source_links[#source_links + 1] = wikilink
                index.has_inlinks[target] = true
            else
                index.has_unresolved_outlinks[source] = true
            end
        end
    end

    return index
end

--- @return vault.NotesLinkIndex
function M.get()
    local cached = state.get_global_key(CACHE_KEY)
    if type(cached) == "table" then
        return cached
    end

    local Scanner = require("vault.scanner")
    local paths, wikilinks = Scanner.paths_and_wikilinks_cached()
    local index = build_index(wikilinks)
    index.paths = paths
    state.set_global_key(CACHE_KEY, index)
    return index
end

--- @return table<string, table>
function M.paths()
    return M.get().paths
end

--- @return table<string, vault.Wikilink>
function M.wikilinks()
    return M.get().wikilinks
end

--- @param slug string
--- @return vault.Wikilinks.map
function M.outlinks(slug)
    return M.get().outlinks_by_source[slug] or {}
end

--- @param slug string
--- @return table<string, vault.Wikilink[]>
function M.inlinks(slug)
    return M.get().inlinks_by_target[slug] or {}
end

return M
