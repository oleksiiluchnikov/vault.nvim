local Object = require("vault.core.object")
local utils = require("vault.utils")
local state = require("vault.core.state")
--- @type vault.Config|vault.Config.options
local config = require("vault.config")
local Wikilink = require("vault.wikilinks.wikilink")

local function scanner()
    return require("vault.scanner")
end

local Collection = require("vault.core.collection")

local Job = require("plenary.job")

--- @class vault.Wikilinks.Group: vault.Wikilinks -- TODO: Make external module
--- @field inlinks vault.Wikilinks.map
--- @field outlinks vault.Wikilinks.map
--- @field resolved vault.Wikilinks.map
--- @field unresolved vault.Wikilinks.map

--- @class vault.Wikilinks: vault.Object
--- @field map vault.Wikilinks.map
--- @field groups table<string, vault.Wikilinks.Group>
local Wikilinks = Collection:extend("VaultWikilinks")

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
        self.map = scanner().wikilinks()
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
    -- P(self.map[slug])
    -- error("asd")

    local wikilinks = {}
    for target_slug, wikilink in pairs(self.map) do
        -- if wikilink.target == target then
        --   table.insert(wikilinks, wikilink)
        -- end
        if utils.match(target_slug, slug, match_opt, case_sensitive) then
            wikilinks[slug] = wikilink
        end
    end

    return wikilinks
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
