local utils = require("vault.utils")
local state = require("vault.core.state")

local function scanner()
    return require("vault.scanner")
end

local Collection = require("vault.core.collection")

--- Map of |vault.Wikilink| objects, keyed by wikilink slug.
--- ```lua
--- local map = {
---   ["foo"] = Wikilink("foo"),
---   ["bar"] = Wikilink("bar"),
---   ["baz/qux"] = Wikilink("baz/qux"),
--- }
--- assert(map["foo"].data.target == "foo")
--- assert(map["bar"].class.name == "VaultWikilink")
--- ```
--- @alias vault.Wikilinks.map table<vault.slug, vault.Wikilink>

--- Ordered list of |vault.Wikilink| objects.
--- @alias vault.Wikilinks.list vault.Wikilink[]

--- Per-note wikilink grouping (inlinks / outlinks / resolved / unresolved).
--- @class vault.Wikilinks.Group: vault.Wikilinks
--- @field inlinks vault.Wikilinks.map Wikilinks pointing *into* the note.
--- @field outlinks vault.Wikilinks.map Wikilinks pointing *out of* the note.
--- @field resolved vault.Wikilinks.map Subset of wikilinks with a known target.
--- @field unresolved vault.Wikilinks.map Subset of wikilinks with no known target.

--- Constructor method contract for Wikilinks (used by tooling / documentation only).
--- @class vault.WikilinksConstructor
--- @field init fun(self: vault.Wikilinks, notes?: vault.Notes): nil
--- @field unresolved fun(self: vault.Wikilinks): vault.Wikilinks
--- @field resolved fun(self: vault.Wikilinks): vault.Wikilinks
--- @field targets fun(self: vault.Wikilinks): vault.Notes.Data.slugs
--- @field by_target fun(self: vault.Wikilinks, slug: vault.slug, match_opt?: vault.enum.MatchOpts.key, case_sensitive?: boolean): vault.Wikilinks.map
--- @field embeds fun(self: vault.Wikilinks): vault.Wikilinks.map

--- Collection of |vault.Wikilink| objects, indexed by slug.
--- Extends |vault.Collection| which provides generic filter/map/reduce helpers.
--- @class vault.Wikilinks: vault.Collection
--- @field map vault.Wikilinks.map Primary keyed map of all wikilinks.
--- @field groups table<string, vault.Wikilinks.Group> Named subgroups (e.g. per-note groupings).
--- @type vault.Wikilinks|vault.WikilinksConstructor
local Wikilinks = Collection:extend("VaultWikilinks")

--- Create a Wikilinks collection from an already-built map.
--- @param map? vault.Wikilinks.map
--- @return vault.Wikilinks
function Wikilinks.from_map(map)
    --- @type vault.Wikilinks
    local instance = setmetatable({ class = Wikilinks }, Wikilinks.__meta)
    instance.map = map or {}
    instance.groups = {}
    state.set_global_key("wikilinks", instance)
    return instance
end

--- Initialise the Wikilinks collection.
---
--- When `notes` is provided, outlinks are collected directly from each note's
--- pre-parsed `data.outlinks` map, which avoids a second scanner pass.
--- When `notes` is omitted, the raw scanner result is used and filtered
--- through `Wikilink.is_valid_slug` to reject code artifacts.
---
--- @param notes? vault.Notes Optional pre-loaded notes collection.
--- @return nil
function Wikilinks:init(notes)
    ---@type vault.Wikilinks.map
    self.map = {}

    if not notes then
        local Wikilink = require("vault.wikilinks.wikilink")
        ---@type vault.Wikilinks.map
        local raw_map = scanner().wikilinks()
        -- Filter out entries with slugs that look like code artifacts
        for slug, wl in pairs(raw_map) do
            local check_slug = (wl.data and wl.data.slug) or slug
            if Wikilink.is_valid_slug(check_slug) then
                self.map[slug] = wl
            end
        end
    else
        -- Collect wikilinks from notes
        for slug, note in pairs(notes.map) do
            --- @type vault.Wikilinks.map
            local note_outlinks = note.data.outlinks

            for wikilink_slug, wikilink in pairs(note_outlinks) do
                if not self.map[wikilink_slug] then
                    self.map[wikilink_slug] = wikilink
                end

                if not self.map[wikilink_slug].data.sources[slug] then
                    self.map[wikilink_slug].data.sources[slug] = {}
                end
            end
        end
    end

    state.set_global_key("wikilinks", self)
end

--- Return a new Wikilinks-like table containing only wikilinks that don't
--- resolve to any note (i.e. `data.target` is nil or empty).
--- Non-destructive — does not mutate the receiver.
--- @nodiscard
--- @return vault.Wikilinks wikilinks_subset Filtered view with only unresolved entries.
function Wikilinks:unresolved()
    ---@type vault.Wikilinks.map
    local filtered = {}
    for wikilink_slug, wikilink in pairs(self.map) do
        if not wikilink.data.target or wikilink.data.target == "" then
            filtered[wikilink_slug] = wikilink
        end
    end
    -- Return a lightweight copy with filtered map
    return setmetatable({ map = filtered }, { __index = self })
end

--- Return a new Wikilinks-like table containing only wikilinks that resolve
--- to an existing note (i.e. `data.target` is set and non-empty).
--- Non-destructive — does not mutate the receiver.
--- @nodiscard
--- @return vault.Wikilinks wikilinks_subset Filtered view with only resolved entries.
function Wikilinks:resolved()
    ---@type vault.Wikilinks.map
    local filtered = {}
    for wikilink_slug, wikilink in pairs(self.map) do
        if wikilink.data.target and wikilink.data.target ~= "" then
            filtered[wikilink_slug] = wikilink
        end
    end
    return setmetatable({ map = filtered }, { __index = self })
end

--- Return a set of all resolved target slugs across the collection.
--- The map value is `true` for each slug that appears as at least one target.
--- @nodiscard
--- @return vault.Notes.Data.slugs targets Set of target slugs (`{[slug] = true}`).
function Wikilinks:targets()
    ---@type vault.Notes.Data.slugs
    local targets = {}
    for _, wikilink in pairs(self.map) do
        if wikilink.data.target then
            targets[wikilink.data.target] = true
        end
    end
    return targets
end

--- Return a subset of the map containing only wikilinks whose target matches `slug`.
--- The match strategy is controlled by `match_opt` (default `"exact"`).
--- @param slug vault.slug The target slug to match against.
--- @param match_opt? vault.enum.MatchOpts.key Match strategy (default: `"exact"`).
--- @param case_sensitive? boolean Whether the match is case-sensitive (default: `false`).
--- @return vault.Wikilinks.map wikilinks Map of wikilinks whose target matches `slug`.
function Wikilinks:by_target(slug, match_opt, case_sensitive)
    if not slug then
        error("`target` is required")
    end

    match_opt = match_opt or "exact"
    case_sensitive = case_sensitive or false

    ---@type vault.Wikilinks.map
    local wikilinks = {}
    for wikilink_slug, wikilink in pairs(self.map) do
        local target = wikilink.data.target or ""
        if utils.match(target, slug, match_opt, case_sensitive) then
            wikilinks[wikilink_slug] = wikilink
        end
    end

    return wikilinks
end

--- Return a subset of the map containing only embedded wikilinks (e.g. ![[image.png]]).
--- Keyed by `wikilink.data.slug`, not by the map key from `self.map`.
--- @nodiscard
--- @return vault.Wikilinks.map embeds Map of embedded wikilinks.
function Wikilinks:embeds()
    ---@type vault.Wikilinks.map
    local embeds = {}
    for _, wikilink in pairs(self.map) do
        if wikilink.data.embedded then
            embeds[wikilink.data.slug] = wikilink
        end
    end
    return embeds
end

--- Constructor alias — the module itself is callable:
--- ```lua
--- local wikilinks = require("vault.wikilinks")()      -- scan all
--- local wikilinks = require("vault.wikilinks")(notes) -- build from notes
--- ```
--- @alias vault.Wikilinks.constructor fun(notes?: vault.Notes|vault.Notes.Group): vault.Wikilinks

--- @type vault.Wikilinks|vault.Wikilinks.constructor
local M = Wikilinks

state.set_global_key("class.vault.Wikilinks", M)
return M
