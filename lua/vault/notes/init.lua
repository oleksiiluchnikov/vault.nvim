local utils = require("vault.utils")
local fmt_error = require("vault.utils.fmt.error")
local state = require("vault.core.state")
local fetcher = require("vault.fetcher")
local Object = require("vault.core.object")
local Filter = require("vault.filter")
local Tags = require("vault.tags")
local Note = require("vault.notes.note")

--- A map of |vault.slug| (unique identifier) to |vault.Note| objects.
--- @alias vault.Notes.map table<vault.slug, vault.Note>
--- A filtered map of |vault.Note| objects keyed by |vault.slug| (unique identifier).
--- @alias VaultNotes.groups.map table<vault.slug, vault.Notes.Group>
--- A list of |vault.slug| (unique identifier).
--- @alias VaultNotes.Data.slugs.list vault.slug[]

--- This is the main object that holds all the notes.
--- It responsible for filtering, sorting, and grouping notes.
--- @class vault.Notes: vault.Object -- The `VaultNotes` class. It holds all the notes.
--- @field all vault.Notes - The initial `VaultNotes` object.
--- @field _raw_map vault.Notes.map - The read-only map of notes. Do not modify directly. Please.
--- @field map vault.Notes.map - The dynamic map of notes. Dynamically updated when using `VaultNotes` methods.
--- @field groups VaultNotes.groups.map - The map of `VaultNotesGroup` objects.
--- @field current function|vault.Notes.Group - The map of notes. Dynamically updated when using `VaultNotes` methods.
--- @field linked function|vault.Notes.Group - `VaultNotesGroup` object with linked notes only. (notes with any incoming or outgoing links)
--- @field orphans function|vault.Notes.Group - `VaultNotesGroup` object with orphan notes only. (notes without any incoming or outgoing links)
--- @field leaves function|vault.Notes.Group - `VaultNotesGroup` object with leaf notes only. (notes without outgoing links)
--- @field wikilinks function|vault.Wikilinks - `VaultWikilinks` object.
--- @field tags vault.Tags - `VaultTags` object.
--- @field count number|fun(self: vault.Notes): number - The count of the dynamic map of notes.
--- @field duplicates fun(self: vault.Notes): table<string, table<string, string>> - The list of tables with duplicate pathes

--- @class vault.Notes: vault.Object
local Notes = Object("VaultNotes")

--- Loads notes by fetching |vault.path| with ripgrep and creating |vault.Note| objects.
--- It will ignore paths that are configured to be ignored.
--- ```lua
--- local notes = require("vault.notes")()
--- notes.map = {}
--- notes:load()
---
--- assert(notes.class.name == "VaultNotes")
--- assert(notes.map == {
---     [foo] = VaultNote,
---     [foo/bar] = VaultNote,
---     [foo/bar/baz] = VaultNote,
--- )}
--- @return vault.Notes
function Notes:load()
    --- @type vault.Notes.map
    local map = fetcher.paths()
    for _, data in pairs(map) do
        self:add_note(Note(data))
    end
    return self
end

--- |VaultNotes| constructor.
--- ```lua
--- local notes = require("vault.notes")()
---
--- assert(notes.class.name == "VaultNotes")
--- ```
--- @return nil
function Notes:init()
    state.clear_all()

    self.map = {}
    self._raw_map = {}

    self:load()

    self._raw_map = self.map
    --- @type VaultNotes.groups.map
    self.groups = {}

    state.set_global_key("notes", self)
end

--- Converts |VaultNotes| to a |VaultNotesGroup| instance.
--- ```lua
--- local notes = require("vault.notes")()
--- assert(notes.class.name == "VaultNotes")
---
--- local notes_group = notes:to_group()
--- assert(notes_group.class.name == "VaultNotesGroup")
--- ```
--- @return vault.Notes.Group
function Notes:to_group()
    --- @type VaultNotesGroup.constructor|vault.Notes.Group
    local NotesGroup = state.get_global_key("class.vault.NotesGroup")
        or require("vault.notes.group")

    --- @cast NotesGroup vault.Notes.Group
    return NotesGroup(self)
end

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
--- @return VaultNotesCluster
function Notes:to_cluster(note, depth)
    --- @type VaultNotesCluster.constructor|VaultNotesCluster
    local NotesCluster = state.get_global_key("class.vault.NotesCluster")
        or require("vault.notes.cluster")
    --- @cast NotesCluster VaultNotesCluster
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

--- Get list of |vault.Note| objects.
--- ```lua
--- local notes = require("vault.notes")()
--- local notes_list = notes:list()
---
--- assert(notes_list == {
---    [1] = VaultNote,
---    [2] = VaultNote,
---    [3] = VaultNote,
---    ...
--- })
--- ```
--- @return vault.Notes.list
function Notes:list()
    return vim.tbl_values(self.map)
end

--- Get map of notes key values. Value expected to be string. Later may be extended to other types.
--- Value expected to be string. Later may be extended to other types.
--- TODO: Extend to other types?
---
--- ```lua
--- --local map_with_basenames = Notes():values_map_with_key("basename", true)
--- local notes = require("vault.notes")()
--- local map = notes:values_map_with_key("basename", true)
---
--- assert(map == {
---    ["foo.md"] = true,
---    ["bar.md"] = true,
---    ["baz.md"] = true,
--- })
--- ```
--- @param key string - The key to get the map of values by.
--- @param lowercase? boolean - If value expected to be string, whether to lowercase it. Default: false
--- @return vault.map - The map of values.
function Notes:values_map_by_key(key, lowercase)
    if not key then
        local note = self:get_random_note()
        local note_object_keys = vim.tbl_keys(note.data)
        error(fmt_error.MISSING_PARAMETER("key", vim.inspect(note_object_keys)))
    end

    --- @type vault.map
    local map = {}
    for _, note in pairs(self.map) do
        if not note.data[key] then
            goto continue
        end
        if type(note.data[key]) == "string" then
            --- @type string
            local note_value = note.data[key]
            if lowercase then
                note_value = note_value:lower()
            end
            if not map[note_value] then
                map[note_value] = true
            end
        end
        ::continue::
    end

    return map
end

--- Get the count of the dynamic map of notes.
--- ```lua
---  local notes = require("vault.notes")()
---  local count = notes:count()
---
---  assert(count == #vim.tbl_keys(notes.map))
--- ```
--- @return integer
function Notes:count()
    return #vim.tbl_keys(self.map)
end

--- Get average content count of notes.
--- ```lua
---  local notes = require("vault.notes")()
---  local average_content_count = notes:average_chars()
---
---  assert(average_content_count == 100)
--- ```
--- @return number
function Notes:average_content_chars()
    local total_content_count = 0
    for _, note in pairs(self.map) do
        local note_content = note.data.content
        local note_content_count = #note_content
        total_content_count = total_content_count + note_content_count
    end

    local average_chars = total_content_count / self:count()

    average_chars = math.floor(average_chars * 100) / 100
    return average_chars
end

--- Get map of the duplicated notes.
---
--- ```lua
---  local notes = require("vault.notes")()
---  local duplicates = notes:duplicates()
---
---  -- TODO: Add assert
--- ```
--- @return table<string, table<string, string>> - The list of tables with duplicate pathes
function Notes:duplicates()
    local duplicates = {}
    local notes_with_count = {}

    for _, note in pairs(self.map) do
        if not notes_with_count[note.data.slug] then
            notes_with_count[note.data.slug] = {}
        end
        table.insert(notes_with_count[note.data.slug], note.data.path)
        if #notes_with_count[note.data.slug] > 1 then
            duplicates[note.data.slug] = notes_with_count[note.data.slug]
        end
    end

    return duplicates
end

--- Get random note.
--- ```lua
--- local notes = require("vault.notes")()
--- local random_note = notes:get_random_note()
---
--- assert(random_note.class.name == "VaultNote")
--- ```
--- @return vault.Note|nil
function Notes:get_random_note()
    local notes_list = self:list()
    if next(notes_list) == nil then
        vim.notify("No notes found")
        return nil
    end
    local random_note = notes_list[math.random(#notes_list)]

    return random_note
end

--- Check if note exists.
--- ```lua
--- local notes = require("vault.notes")()
--- local note = notes:get_random_note()
--- local key = "stem"
--- local query = note.data.stem
--- local match_opt = "exact"
--- local case_sensitive = false
---
--- local has_note = notes:has_note(key, query, match_opt, case_sensitive)
---
--- assert(has_note == true)
--- ```
--- @param key vault.Note.Data._key - The key to search by.
--- @param query? string - The value to search by.
--- @param match_opt? vault.enum.MatchOpts.key - The match option to use.
--- @param case_sensitive? boolean - Whether to use case sensitive search. Default: false
--- @return boolean
function Notes:has_note(key, query, match_opt, case_sensitive)
    if not key then
        local random_note = self:get_random_note()
        local note_object_keys = vim.tbl_keys(random_note.data)
        error(fmt_error.MISSING_PARAMETER("key", vim.inspect(note_object_keys)))
    end

    match_opt = match_opt or "exact"
    case_sensitive = case_sensitive or false

    if case_sensitive == false then
        key = key:lower()
        if not query then
            error(fmt_error.MISSING_PARAMETER("query"))
        end
        query = query:lower()
    end

    for _, note in pairs(self.map) do
        local data = note.data
        if data[key] then
            if query == nil then -- if only key is provided
                return true
            end

            if type(data[key]) ~= "string" then
                return false
            end

            local note_data_value = data[key]
            if case_sensitive == false then
                note_data_value = note_data_value:lower()
            end

            if utils.match(note_data_value, query, match_opt) then
                return true
            end
        end
    end

    return false
end

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
--- @return nil
function Notes:add_note(note)
    if not note then
        error(fmt_error.MISSING_PARAMETER("note", "@see `VaultNote`"))
    end
    if note.class == nil or note.class.name ~= "VaultNote" then
        error(fmt_error.INVALID_VALUE("note", "VaultNote"))
    end

    local slug = note.data.slug

    if self.map[slug] then
        error(
            "Note already exists: "
            .. vim.inspect(self.map[slug])
            .. " compared to "
            .. vim.inspect(note)
        )
    end

    self.map[slug] = note
    self._raw_map[slug] = note

    --- @type vault.Notes
    local notes_global_key = state.get_global_key("notes")
    -- Update global notes object if exists.
    if not notes_global_key then
        return
    end

    notes_global_key.map[slug] = note
    notes_global_key._raw_map[slug] = note
end

--- Delete note by key.
--- @param key vault.Note.Data._key - The key to search by.
function Notes:delete_note_by_key(key, query, match_opt, case_sensitive)
    if not key then
        error(fmt_error.MISSING_PARAMETER("key"))
    end
    match_opt = match_opt or "exact"
    case_sensitive = case_sensitive or false

    if case_sensitive == false then
        key = key:lower()
        if not query then
            error(fmt_error.MISSING_PARAMETER("query"))
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

--- Fetch first `VaultNote` by `VaultNote.data[key]` value.
--- Since it could return more than one note if `VaultNote.data[key]` value is not unique.
--- It will return the first note in the list.
--- ```lua
--- local notes = require("vault.notes")()
--- local note = notes:get_random_note()
--- local key = "stem"
--- local query = note.data.stem
--- local match_opt = "exact"
--- local case_sensitive = false
---
--- local note = notes:fetch_note_by(key, query, match_opt, case_sensitive)
---
--- assert(note.class.name == "VaultNote")
--- ```
--- @param search_term VaultNotesSearchTerm - The key to search by.
--- @param query string - The value to search by.
--- @param match_opt? vault.enum.MatchOpts.key - The match option to use. Default: "exact"
--- @param case_sensitive? boolean - Whether to use case sensitive search. Default: false
--- @return vault.Note|nil
function Notes:fetch_note_by(search_term, query, match_opt, case_sensitive)
    if not search_term then
        error(fmt_error.MISSING_PARAMETER("search_term"))
    end
    if not query then
        error(fmt_error.MISSING_PARAMETER("query"))
    end
    if not match_opt then
        error(fmt_error.MISSING_PARAMETER("match_opt"))
    end

    self = self:with(search_term, query, match_opt, case_sensitive)
    -- TODO: Im not sure if I need.to stay with nil if more than 1 note.
    if vim.tbl_isempty(self.map) or self:count() > 1 then
        return nil
    end

    return self:list()[1]
end

--- Find note by slug.
---
--- @param query string - The query to search by.
--- @param match_opt? vault.enum.MatchOpts.key - The match option to use. Default: "exact"
--- @param case_sensitive? boolean - Whether to use case sensitive search. Default: false
--- @return vault.Note|nil
function Notes:fetch_note_by_slug(query, match_opt, case_sensitive)
    if not query then
        error(fmt_error.MISSING_PARAMETER("slug"))
    end
    match_opt = match_opt or "exact"

    return self:fetch_note_by("slug", query, match_opt, case_sensitive)
end

--- Find note by |vault.Note.data.path|.
---
--- @param query string - The query to search by.
--- @param match_opt? vault.enum.MatchOpts.key - The match option to use. Default: "exact"
--- @param case_sensitive? boolean - Whether to use case sensitive search. Default: false
--- @return vault.Note|nil
function Notes:fetch_note_by_path(query, match_opt, case_sensitive)
    if not query then
        error(fmt_error.MISSING_PARAMETER("path"))
    end
    match_opt = match_opt or "exact"

    return self:fetch_note_by("path", query, match_opt, case_sensitive)
end

--- Fetch note by relpath.
--- ```lua
--- local notes = require("vault.notes")()
--- local note = notes:get_random_note()
--- --TODO: Add assert more descriptive
--- local key = "slug"
--- local query = note.data.stem
--- local match_opt = "exact"
--- local case_sensitive = false
---
--- local note = notes:fetch_note_by(key, query, match_opt, case_sensitive)
---
--- assert(note.class.name == "VaultNote")
--- ```
--- @param query string - The query to search by.
--- @param match_opt? vault.enum.MatchOpts.key - The match option to use. Default: "exact"
--- @param case_sensitive? boolean - Whether to use case sensitive search. Default: false
--- @return vault.Note|nil
function Notes:fetch_note_by_relpath(query, match_opt, case_sensitive)
    if not query then
        error(fmt_error.MISSING_PARAMETER("relpath"))
    end
    match_opt = match_opt or "exact"

    return self:fetch_note_by("relpath", query, match_opt, case_sensitive)
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
function Notes:filter(opts)
    if not opts then
        error(fmt_error.MISSING_PARAMETER("opts"))
    end

    if not opts.class or opts.class.name ~= "VaultFilter" then
        opts = Filter(opts).opts
    end

    for _, opt in ipairs(opts) do
        if opt.search_term == "tags" then
            self:filter_by_tags(opt)
        end
        if opt.search_term == "content" then
            self:with_content(opt.include, opt.match_opt, opt.case_sensitive)
        end
    end

    return self:to_group()
end

--- Get notes filtered by tags.
---
--- @param opts vault.Filter.option.tags|vault.Filter - The filter options to use.
--- @return vault.Notes.Group
function Notes:filter_by_tags(opts)
    if not opts then
        error(fmt_error.MISSING_PARAMETER("opts"))
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

function Notes:with_slugs(slugs)
    local notes_with_slugs = {}
    for _, slug in ipairs(slugs) do
        notes_with_slugs[slug] = self.map[slug]
    end
    self.map = notes_with_slugs
    return self:to_group()
end

-- Notes():filter_by_tags({
--     search_term = "tags",
--     include = {},
--     exclude = { "type" },
--     match_opt = "startswith",
--     mode = "all",
--     case_sensitive = false,
-- })
--
-- Notes():filter_by_tags({
--     search_term = "tags",
--     include = { "3D" },
--     exclude = {},
--     match_opt = "startswith",
--     mode = "all",
--     case_sensitive = false,
-- })

--- Get `VaultNotes` where `VaultNote.data[key]` is
---
--- @param key NoteMetaDataKey - The key to search by.
--- @return vault.Notes.Group
function Notes:with_key(key)
    if not key then
        error(fmt_error.MISSING_PARAMETER("key"))
    end

    for slug, note in pairs(self.map) do
        if not note.data[key] then
            self.map[slug] = nil
        end
    end

    return self:to_group()
end

--- Fetch notes by key value.
---
--- @param search_term VaultNotesSearchTerm - The key to search by.
--- @param query string - The query to search by.
--- @param match_opt vault.enum.MatchOpts.key - The match option to use.
--- @param case_sensitive? boolean - Whether to use case sensitive search. Default: false
--- @return vault.Notes.Group
function Notes:with(search_term, query, match_opt, case_sensitive)
    if not search_term then
        error(fmt_error.MISSING_PARAMETER("key"))
    end
    if not query then
        error(fmt_error.MISSING_PARAMETER("query"))
    end
    if not match_opt then
        error(fmt_error.MISSING_PARAMETER("match_opt"))
    end

    for slug, note in pairs(self.map) do
        --- @type string|nil
        local value = note.data[search_term]
        if type(value) ~= "string" then
            goto continue
        end
        if not case_sensitive then
            value = value:lower()
            query = query:lower()
        end
        if not utils.match(value, query, match_opt) then
            self.map[slug] = nil
        end
        ::continue::
    end

    return self:to_group()
end

--- Get notes with `VaultNote.data.slug`.
--- If no query is provided, it will return `VaultNotesGroup` that have `VaultNote.data.slug` set
---
--- @param query string - The query to search by.
--- @param match_opt? vault.enum.MatchOpts.key - The match option to use. Default: "exact"
--- @param case_sensitive? boolean - Whether to use case sensitive search. Default: false
--- @return vault.Notes.Group
function Notes:with_slug(query, match_opt, case_sensitive)
    if not query then
        error(fmt_error.MISSING_PARAMETER("query"))
    end
    match_opt = match_opt or "exact"

    self = self:with("slug", query, match_opt, case_sensitive)

    return self:to_group()
end

--- Get notes with `VaultNote.data.path` that matches the query.
--- If no query is provided, it will return `VaultNotesGroup` that have `VaultNote.data.path` set
---
--- @param query string - The query to search by.
--- @param match_opt? vault.enum.MatchOpts.key - The match option to use. Default: "startswith"
--- @param case_sensitive? boolean - Whether to use case sensitive search. Default: false
--- @return vault.Notes.Group
function Notes:with_path(query, match_opt, case_sensitive)
    if not query then
        error(fmt_error.MISSING_PARAMETER("query"))
    end
    match_opt = match_opt or "startswith"

    self = self:with("path", query, match_opt, case_sensitive)

    return self:to_group()
end

--- Get notes with `string`.
--- If no query is provided, it will return `VaultNotesGroup` that have `string` set
--- Useful for filtering notes that are in the same directory.
---
--- @param query string - The query to search by.
--- @param match_opt? vault.enum.MatchOpts.key - The match option to use. Default: "startswith"
--- @param case_sensitive? boolean - Whether to use case sensitive search. Default: false
--- @return vault.Notes.Group
function Notes:with_relpath(query, match_opt, case_sensitive)
    if not query then
        error(fmt_error.MISSING_PARAMETER("query"))
    end
    match_opt = match_opt or "startswith"

    for slug, _ in pairs(self.map) do
        local relpath = self.map[slug].data.relpath
        if not utils.match(relpath, query, match_opt, case_sensitive) then
            self.map[slug] = nil
        end
    end

    return self:to_group()
end

--- Get notes with `VaultNote.data.basename`.
--- If no query is provided, it will return `VaultNotesGroup` that have `VaultNote.data.basename` set
---
--- @param query string - The query to search by.
--- @param match_opt? vault.enum.MatchOpts.key - The match option to use. Default: "startswith"
--- @param case_sensitive? boolean - Whether to use case sensitive search. Default: false
--- @return vault.Notes.Group
function Notes:with_basename(query, match_opt, case_sensitive)
    if not query then
        error(fmt_error.MISSING_PARAMETER("query"))
    end
    match_opt = match_opt or "startswith"

    self = self:with("basename", query, match_opt, case_sensitive)

    return self:to_group()
end

--- Get notes with `VaultNote.data.stem`.
--- If no query is provided, it will return `VaultNotesGroup` that have `VaultNote.data.stem` set
---
--- @param query string - The query to search by.
--- @param match_opt? vault.enum.MatchOpts.key - The match option to use. Default: "startswith"
--- @param case_sensitive? boolean - Whether to use case sensitive search. Default: false
--- @return vault.Notes.Group
function Notes:with_stem(query, match_opt, case_sensitive)
    if not query then
        error(fmt_error.MISSING_PARAMETER("query"))
    end
    match_opt = match_opt or "startswith"

    self = self:with("stem", query, match_opt, case_sensitive)

    return self:to_group()
end

--- Get notes with `VaultNote.data.title`.
--- If no query is provided, it will return `VaultNotesGroup` that have `VaultNote.data.title` set
---
--- @param query? string - The query to search by.
--- @param match_opt? vault.enum.MatchOpts.key - The match option to use. Default: "startswith"
--- @param case_sensitive? boolean - Whether to use case sensitive search. Default: false
--- @return vault.Notes.Group
function Notes:with_title(query, match_opt, case_sensitive)
    if not query then
        for slug, note in pairs(self.map) do
            if not note.data.title or note.data.title == "" then
                self.map[slug] = nil
            end
        end
        return self:to_group()
    end
    match_opt = match_opt or "startswith"

    self = self:with("title", query, match_opt, case_sensitive)

    return self:to_group()
end

--- Get notes with not empty `VaultNote.data.content`.
--- If no query is provided, it will return `VaultNotesGroup` that have not empty `VaultNote.data.content` set
---
--- @param query? string - The query to search by.
--- @param match_opt? vault.enum.MatchOpts.key - The match option to use. Default: "contains"
--- @param case_sensitive? boolean - Whether to use case sensitive search. Default: false
--- @return vault.Notes.Group
function Notes:with_content(query, match_opt, case_sensitive)
    if not query then
        for slug, note in pairs(self.map) do
            if note.data.content == "" then
                self.map[slug] = nil
            end
        end
        return self:to_group()
    end
    match_opt = match_opt or "contains"

    self = self:with("content", query, match_opt, case_sensitive)

    return self:to_group()
end

--- Get notes with `VaultNote.data.frontmatter`.
--- If no query is provided, it will return `VaultNotesGroup` that have `VaultNote.data.frontmatter` set
---
--- @param query? string - The query to search by.
--- @param match_opt? vault.enum.MatchOpts.key - The match option to use. Default: "contains"
--- @param case_sensitive? boolean - Whether to use case sensitive search. Default: false
--- @return vault.Notes.Group
function Notes:with_frontmatter(query, match_opt, case_sensitive)
    if not query then
        for slug, note in pairs(self.map) do
            if not note.data.frontmatter or vim.tbl_isempty(note.data.frontmatter) then
                self.map[slug] = nil
            end
        end
        return self:to_group()
    end
    match_opt = match_opt or "contains"

    self = self:with("frontmatter", query, match_opt, case_sensitive)

    return self:to_group()
end

--- Get notes with `VaultNote.data.body`.
--- If no query is provided, it will return `VaultNotesGroup` that have not empty `VaultNote.data.body` set
---
--- @param query? string- The query to search by.
--- @param match_opt? vault.enum.MatchOpts.key - The match option to use. Default: "contains"
--- @param case_sensitive? boolean - Whether to use case sensitive search. Default: false
--- @return vault.Notes.Group
function Notes:with_body(query, match_opt, case_sensitive)
    if not query then
        for slug, note in pairs(self.map) do
            if note.data.body == "" then
                self.map[slug] = nil
            end
        end
        return self:to_group()
    end
    match_opt = match_opt or "contains"

    self = self:with("body", query, match_opt, case_sensitive)

    return self:to_group()
end

--- Get notes with `VaultNote.data.type`.
--- If no query is provided, it will return `VaultNotesGroup` that have `VaultNote.data.type` set
---
--- @param query? string - The query to search by.
--- @param match_opt? vault.enum.MatchOpts.key - The match option to use. Default: "exact"
--- @param case_sensitive? boolean - Whether to use case sensitive search. Default: false
--- @return vault.Notes.Group
function Notes:with_type(query, match_opt, case_sensitive)
    if not query then
        for slug, note in pairs(self.map) do
            if not note.data.type then
                self.map[slug] = nil
            end
        end
        return self:to_group()
    end
    match_opt = match_opt or "exact"

    self = self:with("type", query, match_opt, case_sensitive)

    return self:to_group()
end

--- Get notes with `VaultNote.data.status`.
--- If no query is provided, it will return `VaultNotesGroup` that have `VaultNote.data.status` set
--- @param query string - The query to search by.
--- @param match_opt? vault.enum.MatchOpts.key - The match option to use. Default: "exact"
--- @param case_sensitive? boolean - Whether to use case sensitive search. Default: false
--- @return vault.Notes.Group
function Notes:with_status(query, match_opt, case_sensitive)
    if not query then
        for slug, note in pairs(self.map) do
            if not note.data.status then
                self.map[slug] = nil
            end
        end
        return self:to_group()
    end
    match_opt = match_opt or "exact"

    self = self:with("status", query, match_opt, case_sensitive)

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
    --- @type vault.Notes.data.slugs
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
    --- @type vault.Notes.data.slugs
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
        local title = note.data.title
        local stem = note.data.stem
        if lowercase then
            title = note.data.title:lower()
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
    self.map = self._raw_map
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

--- Get notes with duplicate value for the given key.
--- ```lua
--- local notes = require("vault.notes")()
--- local notes_with_duplicate_stem = notes:with_duplicate("stem")
--- local note = notes:get_random_note()
---
--- assert(note.data.stem ~= note.data.title)
--- assert(notes_with_duplicate_stem.class.name == "VaultNotesGroup")
--- ```
--- @param key VaultNotesSearchTerm
--- @return vault.Notes.Group
function Notes:with_duplicate(key)
    local notes_with_duplicates = {}
    local seen_values = {}
    for slug, note in pairs(self.map) do
        local value = note.data[key]
        if seen_values[value] then
            local prev_note = seen_values[value]
            local prev_note_slug = prev_note.data.slug
            notes_with_duplicates[prev_note_slug] = prev_note
            notes_with_duplicates[slug] = note
        else
            seen_values[value] = note
        end
    end

    self.map = notes_with_duplicates

    return self:to_group()
end

--- @alias vault.Notes.constructor fun(filter_opts: VaultNotesPrefilterOpts?): vault.Notes
--- ```lua
--- local notes = require("vault.notes")()
---
--- assert(notes.class.name == "VaultNotes")
--- ```
--- @type vault.Notes|vault.Notes.constructor
local VaultNotes = Notes

state.set_global_key("class.vault.Notes", VaultNotes)
return VaultNotes
