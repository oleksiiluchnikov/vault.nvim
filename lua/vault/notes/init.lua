local utils = require("vault.utils")
local Error = require("vault.utils.error")

local state = require("vault.core.state")

local function scanner()
    return require("vault.scanner")
end

local Collection = require("vault.core.collection")
local Filter = require("vault.filter")
local Tags = require("vault.tags")
local Note = require("vault.notes.note")
local VaultNotesStats = require("vault.notes.stats")

--[[
================================================================================
VaultNotes
================================================================================

A powerful abstraction for managing and organizing vault notes.

Main features:
• Note metadata and content management
• Advanced filtering and searching
• Link tracking and graph analysis
• Tag and property organization
• Stats and insights

Examples: >lua
    -- Initialize notes
    local notes = require("vault.notes")()

    -- Load and filter by tag
    notes:load():filter({
      search_term = "tags",
      include = {"project"}
    })

    -- Get orphaned notes
    local orphans = notes:orphans()
<

See also:
• |vault.Note|
• |vault.Filter|
• |vault.Tags|
]]
--- @class vault.Notes: vault.Collection
--- Read-only reference map of all notes - DO NOT MODIFY! 🚫
--- @field private _map vault.Notes.map
--- Dynamic note collection that updates with operations
--- @field public map vault.Notes.map
--- Organized note groups
--- @field public groups VaultNotes.groups.map
--- Reference to initial unfiltered notes
--- @field public all vault.Notes
--- Tag management system
--- @field private tags vault.Tags
---
--- Wiki-style links
--- @field public wikilinks fun(self: vault.Notes): vault.Wikilinks
--- Number of notes in current set
--- @field public count fun(self: vault.Notes): number
---
--- Find duplicate notes
--- @field public duplicates fun(self: vault.Notes): {[string]: {[string]: string}}
--- Smart filtering
--- @field public with fun(self: vault.Notes, key: string, query: string, match_opt: string, case_sensitive: boolean): vault.Notes.Group
--- Filter notes
--- @field public filter fun(self: vault.Notes, opts: vault.Filter.option, value: string, match_opt: string, case_sensitive: boolean): vault.Notes.Group
--- Convert to note group
--- @field public to_group fun(self: vault.Notes): vault.Notes.Group
--- Create note cluster
--- @field public to_cluster fun(self: vault.Notes, note: vault.Note, depth: integer): vault.Notes.Cluster
--- Load notes from filesystem
--- @field public load fun(self: vault.Notes): vault.Notes
--- Get all wiki-style links
--- @field public wikilinks fun(self: vault.Notes): vault.Wikilinks
---
--- Get current working set
--- @field public current fun(self: vault.Notes): vault.Notes.Group
--- Notes with connections
--- @field public linked fun(self: vault.Notes): vault.Notes.Group
--- Notes without links
--- @field public orphans fun(self: vault.Notes): vault.Notes.Group
--- End-point notes
--- @field public leaves fun(self: vault.Notes): vault.Notes.Group
--- Notes with connections
--- @field public internals fun(self: vault.Notes): vault.Notes.Group
--- Notes with resolved links
--- @field public with_outlinks_resolved_only fun(self: vault.Notes): vault.Notes.Group
--- Notes with unresolved links
--- @field public with_outlinks_unresolved fun(self: vault.Notes): vault.Notes.Group
--- Notes with mismatched title and stem
--- @field public with_title_mismatched fun(self: vault.Notes, lowercase: boolean): vault.Notes.Group
--- Notes without properties
--- @field public without_properties fun(self: vault.Notes, properties: table<string, boolean>): vault.Notes.Group
--- Notes without tags
--- @field public without_tags fun(self: vault.Notes, tags: table<string, boolean>): vault.Notes.Group
--- Notes with duplicate titles
--- @field public duplicates fun(self: vault.Notes): vault.Notes.Group
--- Notes with tags
--- @field public filter_by_tags fun(self: vault.Notes, tags: table<string, boolean>): vault.Notes.Group
--- Reset notes to initial state
--- @field public reset fun(self: vault.Notes): vault.Notes
--- Add a note to the collection
--- @field public push fun(self: vault.Notes, note: vault.Note): nil
--- Add a note to the collection
--- @field public push_all fun(self: vault.Notes, notes: table<string, vault.Note>): nil
--- Delete note by key
--- @field public delete_note_by_key fun(self: vault.Notes, key: string, query: string, match_opt: string, case_sensitive: boolean): nil
--- Get values by key
--- @field public get_values_by_key fun(self: vault.Notes, key: string, query: string, match_opt: string, case_sensitive: boolean): table<string, vault.Note>
--- Get random notes
--- @field public get_random fun(self: vault.Notes, count: number): table<string, vault.Note>
--- Get values by key
--- @field public values_map_by_key fun(self: vault.Notes, key: string, query: string, match_opt: string, case_sensitive: boolean): table<string, table<string, vault.Note>>
--- Get list of notes
--- @field public list fun(self: vault.Notes): table<string, vault.Note>

--- @class vault.Notes: vault.Object
local Notes = Collection:extend("VaultNotes")

--- |VaultNotes| constructor.
--- ```lua
--- local notes = require("vault.notes")()
---
--- assert(notes.class.name == "VaultNotes")
--- ```
--- @return nil
function Notes:init()
    state.clear_all()

    --- @alias vault.Notes.map table<vault.slug, vault.Note> # Map of unique note identifiers to Note objects
    self.map = {}
    self._map = {}

    self:load()

    self._map = self.map

    --- @alias VaultNotes.groups.map table<vault.slug, vault.Notes.Group> # Map of filtered note groups
    self.groups = {}

    state.set_global_key("notes", self)
end

--- Loads notes by scanning paths with ripgrep and creating Note objects.
--- Paths that match configured ignore patterns are skipped.
---
--- Example:
--- ```lua
--- local notes = require("vault.notes")()
--- notes.map = {} -- Start with empty map
--- notes:load() -- Load notes from vault paths
---
--- -- Notes are now loaded into the map keyed by slug:
--- --   notes.map = {
--- --     ["foo"] = <Note>,
--- --     ["foo/bar"] = <Note>,
--- --     ["foo/bar/baz"] = <Note>
--- --   }
--- ```
--- @return vault.Notes - Returns self for method chaining
function Notes:load()
    --- @type table<string, table<string, string>>
    local paths = scanner().paths()
    for _, data in pairs(paths) do
        self:push(Note(data))
    end
    return self
end

--- function Notes:to_group()
---     --- @type VaultNotesGroup.constructor|vault.Notes.Group
---     local NotesGroup = state.get_global_key("class.vault.NotesGroup")
---         or require("vault.notes.group")
---
---     --- @cast NotesGroup vault.Notes.Group
---     return NotesGroup(self)
--- end

--- Converts |VaultNotes| to a |VaultNotesCluster| instance.
--- ```lua
--- local notes = require("vault.notes")()
--- local note = notes:get_random_note()
--- local notes_cluster = notes:to_cluster(note, 0)
---
--- assert(notes_cluster.class.name == "VaultNotesCluster")
--- ```
--- @param note vault.Note -- The `VaultNote` to create cluster from.
--- @param depth integer -- The initial depth of the cluster to start with.
--- @return vault.Notes.Cluster
function Notes:to_cluster(note, depth)
    --- @type VaultNotesCluster.constructor|vault.Notes.Cluster
    local NotesCluster = state.get_global_key("class.vault.NotesCluster")
        or require("vault.notes.cluster")
    --- @cast NotesCluster vault.Notes.Cluster
    return NotesCluster(self, note, depth)
end

--- Returns a |VaultWikilinks| from current set of notes.
--- ```lua
--- local notes = require("vault.notes")()
--- local wikilinks = notes:wikilinks()
---
--- assert(wikilinks.class.name == "VaultWikilinks")
--- ```
--- @return vault.Wikilinks
function Notes:wikilinks()
    --- @type vault.Wikilinks.constructor|vault.Wikilinks
    local Wikilinks = state.get_global_key("class.vault.Wikilinks") or require("vault.wikilinks")

    --- @cast Wikilinks vault.Wikilinks
    return Wikilinks(self)
end

function Notes:stats()
    return VaultNotesStats(self)
end
--
-- --- Get map of the duplicated notes.
-- ---
-- --- ```lua
-- ---  local notes = require("vault.notes")()
-- ---  local duplicates = notes:duplicates()
-- ---
-- ---  -- TODO: Add assert
-- --- ```
-- --- @return table<string, table<string, string>> - The list of tables with duplicate pathes
-- function Notes:duplicates()
--     local duplicates = {}
--     local notes_with_count = {}
--
--     for _, note in pairs(self.map) do
--         if not notes_with_count[note.data.slug] then
--             notes_with_count[note.data.slug] = {}
--         end
--         table.insert(notes_with_count[note.data.slug], note.data.path)
--         if #notes_with_count[note.data.slug] > 1 then
--             duplicates[note.data.slug] = notes_with_count[note.data.slug]
--         end
--     end
--
--     return duplicates
-- end

--- Add note to the global notes map.
--- ```lua
--- local notes = require("vault.notes")()
--- local path = "foo/bar.md"
--- assert(notes.map["foo/bar"] == nil)
---
--- local note = require("vault.notes.note")(path)
--- notes:add_note(note)
---
--- assert(notes.map["foo/bar"].class.name == "VaultNote")
--- assert(notes.map["foo/bar"] == note)
--- ```
--- @param note vault.Note - The note to add.
--- @return boolean
function Notes:push(note)
    if not note then
        error(Error.MISSING_PARAMETER("note", "@see `VaultNote`"))
    end
    if note.class == nil or note.class.name ~= "VaultNote" then
        error(Error.INVALID_VALUE("note", "VaultNote"))
    end

    local slug = note.data.slug

    if self.map[slug] then
        -- error(
        --     "Note already exists: "
        --         .. vim.inspect(self.map[slug])
        --         .. " compared to "
        --         .. vim.inspect(note)
        -- )
        return false
    end

    self.map[slug] = note
    self._map[slug] = note

    --- @type vault.Notes
    local notes_global_key = state.get_global_key("notes")
    -- Update global notes object if exists.
    if not notes_global_key then
        return false
    end

    notes_global_key.map[slug] = note
    notes_global_key._map[slug] = note
    return true
end

--- Delete note by key.
--- @param key vault.Note.Data._key - The key to search by.
function Notes:delete_note_by_key(key, query, match_opt, case_sensitive)
    if not key then
        error(Error.MISSING_PARAMETER("key"))
    end
    match_opt = match_opt or "exact"
    case_sensitive = case_sensitive or false

    if case_sensitive == false then
        key = key:lower()
        if not query then
            error(Error.MISSING_PARAMETER("query"))
        end
        query = query:lower()
    end

    for slug, note in pairs(self.map) do
        local data = note.data
        if data[key] then
            if query == nil then -- if only key is provided
                self.map[slug] = nil
                goto continue
            end

            local note_data_value = data[key]
            if case_sensitive == false then
                note_data_value = note_data_value:lower()
            end

            if utils.match(note_data_value, query, match_opt) then
                self.map[slug] = nil
            end
        end
        ::continue::
    end
end

--- Filter notes with `VaultFilterOpts`.
---
--- @param opts vault.Filter|vault.Filter.option - The filter options to use.
--- ```lua
--- local notes = require("vault.notes")()
--- local opts = {
---    {
---    search_term = "tags",
---    include = { "foo" },
---    exclude = { "bar" },
---    match_opt = "exact",
---    mode = "all",
---    case_sensitive = false,
---    },
---    {
---    search_term = "tags",
---    include = { "baz" },
---    exclude = { "qux" },
---    match_opt = "exact",
---    mode = "all",
---    case_sensitive = false,
---    },
--- }
--- local filtered_notes = notes:filter(opts)
--- assert(filtered_notes:count() < notes:count())
--- ```
--- @return vault.Notes.Group
function Notes:filter(opts, value, match_opt, case_sensitive)
    if opts and opts.search_term == "tags" then
        opts = Filter(opts, "tags")
        return self:filter_by_tags(opts)
    end
    --- @diagnostic disable-next-line: undefined-field
    return self.class.super.filter(self, opts, value, match_opt, case_sensitive)
end

--- Get notes filtered by tags.
---
--- @param opts vault.Filter.option.tags|vault.Filter - The filter options to use.
--- @return vault.Notes.Group
function Notes:filter_by_tags(opts)
    if not opts then
        error(Error.MISSING_PARAMETER("opts"))
    end
    opts = Filter(opts, "tags").opts
    for _, opt in ipairs(opts) do
        local is_exclude_only = false
        if #opt.include == 0 and #opt.exclude > 0 then
            opt.include = opt.exclude
            opt.exclude = {}
            is_exclude_only = true
        end

        local tags = Tags():filter(opt)
        local sources = tags:sources() -- where tag exists

        for slug, _ in pairs(self.map) do
            if is_exclude_only then
                if sources[slug] then
                    self.map[slug] = nil
                end
            else
                if not sources[slug] then
                    self.map[slug] = nil
                end
            end
        end
    end

    return self:to_group()
end

--- Get linked notes. (Notes that have inlinks or outlinks)
--- ```lua
--- local notes = require("vault.notes")()
--- local note = notes:get_random_note()
--- local outlinks = note.data.outlinks
--- local inlinks = note.data.inlinks
---
--- --TODO: Add assert
--- local links = inlinks or outlinks
---
--- assert(links ~= nil)
--- @return vault.Notes.Group
function Notes:linked()
    for slug, note in pairs(self.map) do
        local outlinks = note.data.outlinks
        local inlinks = note.data.inlinks
        if next(outlinks) == nil and next(inlinks) == nil then
            self.map[slug] = nil
        end
    end

    state.set_global_key("notes.linked", self)
    return self:to_group()
end

--- Get internal notes. (Notes that have inlinks AND outlinks)
--- ```lua
--- local notes = require("vault.notes")()
--- local internals = notes:internals()
--- local note = notes:get_random_note()
--- local outlinks = note.data.outlinks
--- local inlinks = note.data.inlinks
---
--- assert(outlinks ~= nil)
--- assert(inlinks ~= nil)
--- assert(internals.class.name == "VaultNotesGroup")
--- ```
--- @return vault.Notes.Group
function Notes:internals()
    for slug, note in pairs(self.map) do
        if next(note.data.outlinks) == nil or next(note.data.inlinks) == nil then
            self.map[slug] = nil
        end
    end

    state.set_global_key("notes.internals", self)
    return self:to_group()
end

--- Get leaves notes. (Notes that don't have outgoing links, but have incoming links)
--- ```lua
--- local notes = require("vault.notes")()
--- local leaves = notes:leaves()
--- local note = notes:get_random_note()
---
--- local outlinks = note.data.outlinks
--- local inlinks = note.data.inlinks
---
--- assert(outlinks == nil)
--- assert(inlinks ~= nil)
--- assert(leaves.class.name == "VaultNotesGroup")
--- ```
--- @return vault.Notes.Group
function Notes:leaves()
    --- @type vault.Wikilinks
    local wikilinks = self:wikilinks()
    --- @type vault.Notes.Data.slugs
    local targets = wikilinks:targets()
    local leaves = self:to_group()

    for slug, note in pairs(self.map) do
        -- if note in targets then it is linked.
        if not targets[slug] then
            leaves.map[slug] = nil
            goto continue
        end
        local outlinks = note.data.outlinks

        -- if note has outlinks then it is not a leaf
        if outlinks and next(outlinks) then
            -- self.map[slug] = nil
            leaves.map[slug] = nil
        end
        ::continue::
    end

    state.set_global_key("notes.leaves", leaves)
    return leaves
end

--- Get orphans notes. (Notes that don't have any inlinks and outlinks)
--- ```lua
--- local notes = require("vault.notes")()
--- local orphans = notes:orphans()
--- local note = notes:get_random_note()
---
--- local outlinks = note.data.outlinks
--- local inlinks = note.data.inlinks
---
--- assert(outlinks == nil)
--- assert(inlinks == nil)
--- assert(orphans.class.name == "VaultNotesGroup")
--- ```
--- @see VaultWikilink
--- @return vault.Notes.Group
function Notes:orphans()
    --- @type vault.Wikilinks
    local wikilinks = self:wikilinks()
    --- @type vault.Notes.Data.slugs
    local targets = wikilinks:targets()
    local orphans = self:to_group()

    for slug, note in pairs(self.map) do
        local outlinks = note.data.outlinks
        if outlinks and next(outlinks) then
            orphans.map[slug] = nil
            goto continue
        end
        if targets[slug] then
            orphans.map[slug] = nil
        end
        ::continue::
    end

    state.set_global_key("notes.orphans", orphans)
    return orphans
end

--- Notes that have resolved `VaultWikilinks`(Only)
--- ```lua
--- local notes = require("vault.notes")()
--- local notes_with_resolved_links_only = notes:with_outlinks_resolved_only()
--- local note = notes:get_random_note()
--- local outlinks = note.data.outlinks
---
--- for _, wikilink in pairs(outlinks) do
---    assert(wikilink.data.target ~= nil)
--- end
--- assert(notes_with_resolved_links_only.class.name == "VaultNotesGroup")
--- ```
--- @return vault.Notes.Group
function Notes:with_outlinks_resolved_only()
    -- Exclude notes that have unresolved links
    -- Exclude notes that have no links

    for slug, note in pairs(self.map) do
        -- Should have outlinks
        local outlinks = note.data.outlinks
        if not outlinks or next(outlinks) == nil then
            self.map[slug] = nil
            goto continue
        end
        -- Should have only resolved links
        for _, wikilink in pairs(outlinks) do
            if not wikilink.data.target or wikilink.data.target == "" then
                self.map[slug] = nil
                goto continue
            end
        end
        ::continue::
    end

    return self:to_group()
end

--- Get notes with unresolved links.
--- ```lua
--- local notes = require("vault.notes")()
--- local notes_with_unresolved_links = notes:with_outlinks_unresolved()
--- local note = notes:get_random_note()
--- local outlinks = note.data.outlinks
---
--- --TODO: Add assert
--- assert(unresolved_links == unresolved_links[1].class.name == "VaultWikilink")
--- assert(notes_with_unresolved_links.class.name == "VaultNotesGroup")
--- ```
--- @return vault.Notes.Group
function Notes:with_outlinks_unresolved()
    -- Exclude notes that have no outlinks
    --- @type vault.Notes.map
    local notes_map_with_unresolved_links = {}
    for slug, note in pairs(self.map) do
        local outlinks = note.data.outlinks
        if not outlinks or next(outlinks) == nil then
            self.map[slug] = nil
            goto continue
        end
        -- Exclude notes that have only resolved links
        for _, wikilink in pairs(outlinks) do
            if not wikilink.data.target then
                notes_map_with_unresolved_links[slug] = note
            end
        end
        ::continue::
    end

    self.map = notes_map_with_unresolved_links

    return self:to_group()
end

--- Get list of notes where title not matches stem
---
--- Notes without a title or with matching title and stem are excluded.
--- @param lowercase? boolean - Whether to lowercase title and stem. Default: true
--- @return vault.Notes.Group
--- ```lua
--- local notes = require("vault.notes")()
--- local note = notes:get_random_note()
---
--- assert(note.data.title ~= note.data.stem)
--- ```
function Notes:with_title_mismatched(lowercase)
    for slug, note in pairs(self.map) do
        if not note.data.title or note.data.title == "" then
            self.map[slug] = nil
            goto continue
        end
        local title = note.data.title.text
        local stem = note.data.stem
        if lowercase then
            title = title:lower()
            stem = note.data.stem:lower()
        end

        if title == stem then
            self.map[slug] = nil
        end
        ::continue::
    end

    return self:to_group()
end

--- Reset the `Notes` object.
--- After reset the `Notes` object will be the same as it was after initialization.
--- ```lua
--- local notes = require("vault.notes")()
--- local init_length = notes:count()
---
--- notes:reset()
---
--- assert(notes:count() == init_length)
--- ```
--- @return vault.Notes
function Notes:reset()
    self.map = self._map
    return self
end

--- Notes without VaultProperties
--- ```lua
--- local notes = require("vault.notes")()
--- local notes_without_properties = notes:without_properties()
--- local note = notes:get_random_note()
--- local note_properties = note.data.properties
---
--- assert(note_properties == nil)
--- assert(notes_without_properties.class.name == "VaultNotesGroup")
--- ```
--- @return vault.Notes
function Notes:without_properties()
    -- local properties = state.get_global_key("properties") or require("vault.properties")()
    local sources_with_properties = require("vault.properties")():sources()

    --- @type vault.Notes.map
    local notes_without_properties = {}
    for slug, note in pairs(self.map) do
        if not sources_with_properties[slug] then
            notes_without_properties[slug] = note
        end
    end
    self.map = notes_without_properties
    return self:to_group()
end

--- Notes without VaultTags
--- ```lua
--- local notes = require("vault.notes")()
--- local notes_without_tags = notes:without_tags()
--- local note = notes:get_random_note()
--- local note_tags = note.data.tags
---
--- assert(note_tags == nil)
--- assert(notes_without_properties.class.name == "VaultNotesGroup")
--- ```
--- @return vault.Notes
function Notes:without_tags()
    -- local tags = state.get_global_key("tags") or require("vault.tags")()
    local sources_with_tags = require("vault.tags")():sources()

    --- @type vault.Notes.map
    local notes_without_tags = {}
    for slug, note in pairs(self.map) do
        if not sources_with_tags[slug] then
            notes_without_tags[slug] = note
        end
    end
    self.map = notes_without_tags
    return self:to_group()
end

--- @alias vault.NotesPrefilterOpts table<string, string|table<string, string>>
--- @alias vault.Notes.constructor fun(filter_opts: vault.NotesPrefilterOpts?): vault.Notes
--- ```lua
--- local notes = require("vault.notes")()
---
--- assert(notes.class.name == "VaultNotes")
--- assert(notes.map["foo/bar].class.name == "VaultNote")
---
--- notes:push(require("vault.notes.note")("/Users/johndoe/vault/foo/bar.md"))
--- assert(notes.map["foo/bar"].data.title == "Foo Bar")
--- ```
--- @type vault.Notes|vault.Notes.constructor
local VaultNotes = Notes

state.set_global_key("class.vault.Notes", VaultNotes)
return VaultNotes
