local Object = require("vault.core.object")
local utils = require("vault.utils")
local state = require("vault.core.state")
--- @type vault.Config|vault.Config.options
local config = require("vault.config")
local Wikilink = require("vault.wikilinks.wikilink")
local fetcher = require("vault.fetcher")

local Job = require("plenary.job")

--- @class vault.Wikilinks.Group: vault.Wikilinks -- TODO: Make external module
--- @field inlinks vault.Wikilinks.map
--- @field outlinks vault.Wikilinks.map
--- @field resolved vault.Wikilinks.map
--- @field unresolved vault.Wikilinks.map

--- @class vault.Wikilinks: vault.Object
--- @field map vault.Wikilinks.map
--- @field groups table<string, vault.Wikilinks.Group>
local Wikilinks = Object("VaultWikilinks")

--- Map of |vault.Wikilink| objects.
--- Each key is the |vault.slug| of the wikilink.
--- ```lua
--- local map = {
---   ["foo"] = Wikilink("foo"),
---   ["bar"] = Wikilink("bar"),
---   ["baz/qux"] = Wikilink("baz/qux"),
--- }
---
--- assert(map["foo"].data.target == "foo")
--- assert(map["bar"].class.name == "VaultWikilink")
--- ```
--- @alias vault.Wikilinks.map table<vault.stem, vault.Wikilink>

--- @example
--- ```lua
--- local map = {
---     Wikilink("foo"),
---     Wikilink("bar"),
---     Wikilink("baz/qux"),
--- }
--- ```
--- @alias vault.Wikilinks.list vault.Wikilink[]

--- @param notes vault.Notes
function Wikilinks:init(notes)
    -- if not notes then
    --     notes = state.get_global_key("notes") or require("vault.notes")()

    self.map = {}

    if not notes then
        self.map = fetcher.wikilinks()
    else
        -- Collect wikilinks from notes
        for slug, note in pairs(notes.map) do
            --- @type vault.Wikilinks.list
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
    end

    state.set_global_key("wikilinks", self)
end

--- Wikilinks that don't have a target key.
--- @return vault.Wikilinks
function Wikilinks:unresolved()
    for stem, wikilink in pairs(self.map) do
        if wikilink.data.target and wikilink.data.target ~= "" then
            self.map[stem] = nil
        end
    end
    return self
end

--- Wikilinks that have a target key.
--- @return vault.Wikilinks
function Wikilinks:resolved()
    for stem, wikilink in pairs(self.map) do
        if not wikilink.data.target or wikilink.data.target == "" then
            self.map[stem] = nil
        end
    end
    return self
end

--- @return vault.Notes.Data.slugs
function Wikilinks:targets()
    local targets = {}
    for _, wikilink in pairs(self.map) do
        if wikilink.data.target then
            targets[wikilink.data.target] = true
        end
    end
    return targets
end

--- @return vault.Wikilinks.list
function Wikilinks:list()
    return vim.tbl_values(self.map)
end

--- Get wikilinks length
--- @return integer
function Wikilinks:len()
    return vim.tbl_count(self:list())
end

--- Get values by key
--- @param key string
--- @return table
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

--- @param slug vault.slug
--- @param match_opt vault.enum.MatchOpts.key
--- @param case_sensitive? boolean
--- @return vault.Wikilinks.map
function Wikilinks:by_target(slug, match_opt, case_sensitive)
    if not slug then
        error("`target` is required")
    end

    match_opt = match_opt or "exact"
    case_sensitive = case_sensitive or false

    local wikilinks = {}
    for slug, wikilink in pairs(self.map) do
        -- if wikilink.target == target then
        --   table.insert(wikilinks, wikilink)
        -- end
        if utils.match(wikilink.data.target, slug, match_opt, case_sensitive) then
            wikilinks[slug] = wikilink
        end
    end

    return wikilinks
end

--- @return vault.Notes.Data.slugs
function Wikilinks:sources()
    --- @type vault.Notes.data.slugs
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

--- @return vault.Wikilinks.map
function Wikilinks:embeds()
    local embeds = {}
    for _, wikilink in pairs(self.map) do
        if wikilink.data.embedded then
            embeds[wikilink.data.stem] = wikilink
        end
    end
    return embeds
end

--- @alias vault.Wikilinks.constructor fun(notes: vault.Notes|vault.Notes.Group?): vault.Wikilinks
--- @type vault.Wikilinks|vault.Wikilinks.constructor
local M = Wikilinks

state.set_global_key("class.vault.Wikilinks", M)
return M
