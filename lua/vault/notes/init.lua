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
local config = require("vault.config")
local log = require("vault.log").scope("notes")

---@class vault.Notes.MoveSpec
---@field from string
---@field to string

---@class vault.Notes.MoveManyOpts
---@field update_links? boolean
---@field force? boolean
---@field verbose? boolean
---@field silent? boolean

---@class vault.Notes.MoveTreeOpts: vault.Notes.MoveManyOpts
---@field from_dir string
---@field to_dir string
---@field preserve_subdirs? boolean

---@class vault.Notes.MoveReport
---@field moved integer
---@field patched_files integer
---@field skipped integer
---@field renames vault.Watcher.RenameSpec[]

---@param path string
---@return string
local function normalize_path(path)
    return vim.fs.normalize(vim.fn.fnamemodify(path, ":p"))
end

---@param path string
---@return boolean
local function is_note_path(path)
    return type(path) == "string" and path:sub(-#config.options.ext) == config.options.ext
end

---@param dir string
---@return string
local function normalize_dir(dir)
    local normalized = normalize_path(dir)
    return normalized:gsub("/+$", "")
end

---@param path string
---@param dir string
---@return boolean
local function path_is_within_dir(path, dir)
    return path == dir or path:sub(1, #dir + 1) == (dir .. "/")
end

---@param path string
---@param dir string
---@return string
local function relative_to_dir(path, dir)
    if path == dir then
        return ""
    end
    return path:sub(#dir + 2)
end

---@param notes vault.Notes
---@param renames vault.Watcher.RenameSpec[]
local function refresh_notes_collection_maps(notes, renames)
    if #renames == 0 then
        return
    end

    for _, rename in ipairs(renames) do
        local note = notes.map[rename.old_slug] or notes._map[rename.old_slug]
        if note then
            notes.map[rename.old_slug] = nil
            notes._map[rename.old_slug] = nil
            note.data.path = rename.new_path
            note.data.slug = rename.new_slug
            note.data.relpath = utils.path_to_relpath(rename.new_path)
            notes.map[rename.new_slug] = note
            notes._map[rename.new_slug] = note
        end
    end

    local notes_global = state.get_global_key("notes")
    if notes_global and notes_global ~= notes then
        for _, rename in ipairs(renames) do
            local note = notes_global.map[rename.old_slug] or notes_global._map[rename.old_slug]
            if note then
                notes_global.map[rename.old_slug] = nil
                notes_global._map[rename.old_slug] = nil
                note.data.path = rename.new_path
                note.data.slug = rename.new_slug
                note.data.relpath = utils.path_to_relpath(rename.new_path)
                notes_global.map[rename.new_slug] = note
                notes_global._map[rename.new_slug] = note
            end
        end
    end
end

---@param renames vault.Watcher.RenameSpec[]
---@param update_links boolean
---@param silent boolean
---@return integer
local function patch_wikilinks_after_moves(renames, update_links, silent)
    if not update_links or #renames == 0 then
        return 0
    end

    local Watcher = require("vault.watcher")
    local watcher = Watcher()
    watcher:disable_oil_guard()

    local rename_specs = {}
    for _, rename in ipairs(renames) do
        table.insert(rename_specs, {
            old_path = rename.old_path,
            new_path = rename.new_path,
        })
    end

    return watcher:handle_renames(rename_specs, silent) or 0
end

---@param notes vault.Notes
---@param note_map table<string, vault.Note>
---@param opts vault.Notes.MoveManyOpts
---@return vault.Notes.MoveReport
local function move_notes(notes, note_map, opts)
    opts = opts or {}
    local update_links = opts.update_links
    if update_links == nil then
        local watcher_conf = (config.options and config.options.watcher) or {}
        update_links = watcher_conf.auto_update_links
        if update_links == nil then
            update_links = true
        end
    end

    local force = opts.force == true
    local verbose = opts.verbose ~= false
    local silent = opts.silent == true

    if next(note_map) == nil then
        return {
            moved = 0,
            patched_files = 0,
            skipped = 0,
            renames = {},
        }
    end

    --- @type string[]
    local errors = {}
    local target_seen = {}

    for old_path, note in pairs(note_map) do
        if vim.fn.filereadable(old_path) == 0 then
            table.insert(errors, "source does not exist: " .. old_path)
        end

        local new_path = note.data.path
        if old_path == new_path then
            table.insert(errors, "source and target are identical: " .. old_path)
        end

        if target_seen[new_path] then
            table.insert(errors, "duplicate target path: " .. new_path)
        else
            target_seen[new_path] = true
        end

        if not force and vim.fn.filereadable(new_path) == 1 then
            table.insert(errors, "target already exists: " .. new_path)
        end
    end

    if #errors > 0 then
        error(table.concat(errors, "\n"))
    end

    --- @type vault.Watcher.RenameSpec[]
    local renames = {}
    local moved = 0
    for old_path, note in pairs(note_map) do
        local new_path = note.data.path
        local target_dir = vim.fn.fnamemodify(new_path, ":p:h")
        if vim.fn.isdirectory(target_dir) == 0 then
            vim.fn.mkdir(target_dir, "p")
        end

        local ok, err = (vim.uv or vim.loop).fs_rename(old_path, new_path)
        if not ok then
            error(
                "failed to move note: " .. old_path .. " -> " .. new_path .. " :: " .. tostring(err)
            )
        end

        local old_slug = utils.path_to_slug(old_path)
        local new_slug = utils.path_to_slug(new_path)
        note.data.path = new_path
        note.data.slug = new_slug
        note.data.relpath = utils.path_to_relpath(new_path)

        table.insert(renames, {
            old_path = old_path,
            new_path = new_path,
            old_slug = old_slug,
            new_slug = new_slug,
        })
        moved = moved + 1
    end

    local patched_files = patch_wikilinks_after_moves(renames, update_links, silent)
    refresh_notes_collection_maps(notes, renames)

    if verbose then
        if update_links then
            log.info("moved %d notes • %d files patched", moved, patched_files)
        else
            log.info("moved %d notes (wikilink update skipped)", moved)
        end
    end

    return {
        moved = moved,
        patched_files = patched_files,
        skipped = 0,
        renames = renames,
    }
end

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
    -- Only clear note-specific caches, NOT the entire global state.
    -- state.clear_all() was wiping class registrations, tags, wikilinks, etc.
    state.set_global_key("notes", nil)
    state.set_global_key("notes.linked", nil)
    state.set_global_key("notes.internals", nil)
    state.set_global_key("notes.leaves", nil)
    state.set_global_key("notes.orphans", nil)

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
    -- Example of paths structure:
    -- ["Example Note"] = {
    --   basename = "Example Note",
    --   frontmatter = {
    --     categories = "[[Docs]]",
    --     created = 20251223125059,
    --     tags = {},
    --     type = "reference"
    --   },
    --   path = "~/knowledge/Example Note.md",
    --   relpath = "Example Note.md",
    --   slug = "Example Note",
    --   title = "20251223125059"
    -- },
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

--- Move multiple notes in a single batch and rewrite wikilinks once.
--- @param moves vault.Notes.MoveSpec[]
--- @param opts? vault.Notes.MoveManyOpts
--- @return vault.Notes.MoveReport
function Notes:move_many(moves, opts)
    if type(moves) ~= "table" then
        error(Error.INVALID_VALUE("moves", "table"))
    end

    --- @type table<string, vault.Note>
    local note_map = {}
    for _, move in ipairs(moves) do
        if type(move) ~= "table" or type(move.from) ~= "string" or type(move.to) ~= "string" then
            error("move_many expects entries like { from = '/old.md', to = '/new.md' }")
        end

        local old_path = normalize_path(move.from)
        local new_path = normalize_path(move.to)
        if not is_note_path(old_path) or not is_note_path(new_path) then
            error("move_many only supports note paths ending with " .. config.options.ext)
        end

        local note = Note(old_path)
        note.data.path = new_path
        note.data.slug = utils.path_to_slug(new_path)
        note.data.relpath = utils.path_to_relpath(new_path)
        note_map[old_path] = note
    end

    return move_notes(self, note_map, opts)
end

--- Move all notes under one directory tree into another directory tree.
--- @param opts vault.Notes.MoveTreeOpts
--- @return vault.Notes.MoveReport
function Notes:move_tree(opts)
    if type(opts) ~= "table" then
        error(Error.INVALID_VALUE("opts", "table"))
    end

    if type(opts.from_dir) ~= "string" or opts.from_dir == "" then
        error(Error.MISSING_PARAMETER("from_dir"))
    end
    if type(opts.to_dir) ~= "string" or opts.to_dir == "" then
        error(Error.MISSING_PARAMETER("to_dir"))
    end

    local from_dir = normalize_dir(opts.from_dir)
    local to_dir = normalize_dir(opts.to_dir)
    local preserve_subdirs = opts.preserve_subdirs ~= false
    if from_dir == to_dir then
        error("from_dir and to_dir must differ")
    end

    --- @type vault.Notes.MoveSpec[]
    local moves = {}
    for _, note in pairs(self.map) do
        local old_path = normalize_path(note.data.path)
        if path_is_within_dir(old_path, from_dir) then
            local suffix
            if preserve_subdirs then
                suffix = relative_to_dir(old_path, from_dir)
            else
                suffix = vim.fn.fnamemodify(old_path, ":t")
            end
            table.insert(moves, {
                from = old_path,
                to = to_dir .. "/" .. suffix,
            })
        end
    end

    if #moves == 0 then
        if opts.verbose ~= false then
            log.info("no notes found under %s", from_dir)
        end
        return {
            moved = 0,
            patched_files = 0,
            skipped = 0,
            renames = {},
        }
    end

    return self:move_many(moves, opts)
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
    local linked = self:to_group()

    for slug, note in pairs(linked.map) do
        local outlinks = note.data.outlinks
        local inlinks = note.data.inlinks
        if next(outlinks) == nil and next(inlinks) == nil then
            linked.map[slug] = nil
        end
    end

    state.set_global_key("notes.linked", linked)
    return linked
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
    local internals = self:to_group()

    for slug, note in pairs(internals.map) do
        if next(note.data.outlinks) == nil or next(note.data.inlinks) == nil then
            internals.map[slug] = nil
        end
    end

    state.set_global_key("notes.internals", internals)
    return internals
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
    local resolved = self:to_group()

    for slug, note in pairs(resolved.map) do
        -- Should have outlinks
        local outlinks = note.data.outlinks
        if not outlinks or next(outlinks) == nil then
            resolved.map[slug] = nil
            goto continue
        end
        -- Should have only resolved links
        for _, wikilink in pairs(outlinks) do
            if not wikilink.data.target or wikilink.data.target == "" then
                resolved.map[slug] = nil
                goto continue
            end
        end
        ::continue::
    end

    return resolved
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
    local unresolved = self:to_group()

    for slug, note in pairs(unresolved.map) do
        local outlinks = note.data.outlinks
        if not outlinks or next(outlinks) == nil then
            unresolved.map[slug] = nil
            goto continue
        end
        -- Keep only notes that have at least one unresolved link
        local has_unresolved = false
        for _, wikilink in pairs(outlinks) do
            if not wikilink.data.target then
                has_unresolved = true
                break
            end
        end
        if not has_unresolved then
            unresolved.map[slug] = nil
        end
        ::continue::
    end

    return unresolved
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
