local Object = require("vault.core.object")
local utils = require("vault.utils")
local state = require("vault.core.state")
---@type VaultConfig|VaultConfig.options
local config = require("vault.config")
local Wikilink = require("vault.wikilinks.wikilink")
local fetcher = require("vault.fetcher")

local Job = require("plenary.job")

---@alias VaultMap.wikilinks table<VaultWikilink.data.stem, VaultWikilink>
---@class VaultWikilinksGroup: VaultWikilinks -- TODO: Make external module
---@field inlinks VaultMap.wikilinks
---@field outlinks VaultMap.wikilinks
---@field resolved VaultMap.wikilinks
---@field unresolved VaultMap.wikilinks

---@class VaultWikilinks: VaultObject
---@field map VaultMap.wikilinks
---@field groups table<string, VaultWikilinksGroup>
local Wikilinks = Object("VaultWikilinks")

---@param notes VaultNotes
function Wikilinks:init(notes)
    -- if not notes then
    --     notes = state.get_global_key("notes") or require("vault.notes")()

    self.map = {}

    if notes then
        -- Collect wikilinks from notes
        for slug, note in pairs(notes.map) do
            ---@type VaultWikilinksList
            local note_outlinks = note.data.outlinks

            for wikilink_stem, wikilink in pairs(note_outlinks) do
                if not self.map[wikilink_stem] then
                    self.map[wikilink_stem] = wikilink
                end

                if not self.map[wikilink_stem].data.sources[slug] then
                    self.map[wikilink_stem].data.sources[slug] = {}
                end
            end
        end
    else
        self.map = fetcher.wikilinks()
    end

    state.set_global_key("wikilinks", self)
end

--- Wikilinks that don't have a target key.
---@return VaultWikilinks
function Wikilinks:unresolved()
    for stem, wikilink in pairs(self.map) do
        if wikilink.data.target and wikilink.data.target ~= "" then
            self.map[stem] = nil
        end
    end

    return self
end

--- Wikilinks that have a target key.
---
---@return VaultWikilinks
function Wikilinks:resolved()
    for stem, wikilink in pairs(self.map) do
        if not wikilink.data.target or wikilink.data.target == "" then
            self.map[stem] = nil
        end
    end

    return self
end

--- Get targets
---@return VaultMap.slugs
function Wikilinks:targets()
    local targets = {}
    for _, wikilink in pairs(self.map) do
        if wikilink.data.target then
            targets[wikilink.data.target] = true
        end
    end
    return targets
end

---@alias VaultWikilinksList VaultWikilink[]

---@return VaultWikilinksList
function Wikilinks:list()
    return vim.tbl_values(self.map)
end

--- Get wikilinks length
---@return number
function Wikilinks:len()
    return vim.tbl_count(self:list())
end

--- Get values by key
---@param key string
---@return table
function Wikilinks:get_values_by_key(key)
    if not key then
        error("`key` is required")
    end

    local values = {}
    for _, wikilink in pairs(self.map) do
        if wikilink.data[key] then
            table.insert(values, wikilink.data[key])
        end
    end

    return values
end

--- Get wikilinks by target
---
---@param target string
---@param match_opt VaultMatchOptsKey
---@param case_sensitive boolean?
---@return VaultMap.wikilinks
function Wikilinks:by_target(target, match_opt, case_sensitive)
    if not target then
        error("`target` is required")
    end

    match_opt = match_opt or "exact"
    case_sensitive = case_sensitive or false

    local wikilinks = {}
    for slug, wikilink in pairs(self.map) do
        -- if wikilink.target == target then
        --   table.insert(wikilinks, wikilink)
        -- end
        if utils.match(wikilink.data.target, target, match_opt, case_sensitive) then
            wikilinks[slug] = wikilink
        end
    end

    return wikilinks
end

--- Get map of `VaultWikilink.source` values.
---
---@return VaultMap.slugs
function Wikilinks:sources()
    ---@type VaultMap.slugs
    local sources = {}
    for _, wikilink in pairs(self.map) do
        for source, _ in pairs(wikilink.data.sources) do
            if not sources[source] then
                sources[source] = true
            end
        end
    end
    return sources
end

--- Get embeds
---
---@return VaultMap.wikilinks
function Wikilinks:embeds()
    local embeds = {}
    for _, wikilink in pairs(self.map) do
        if wikilink.data.embedded then
            embeds[wikilink.data.stem] = wikilink
        end
    end
    return embeds
end

---@alias VaultWikilinks.constructor fun(notes: VaultNotes|VaultNotesGroup?): VaultWikilinks
---@type VaultWikilinks|VaultWikilinks.constructor
local VaultWikilinks = Wikilinks

return VaultWikilinks
