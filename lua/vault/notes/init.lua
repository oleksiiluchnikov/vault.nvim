---@type VaultConfig.options|VaultConfig
local config = require("vault.config")
local error_formatter = require("vault.utils.error_formatter")
local utils = require("vault.utils")
local state = require("vault.core.state")
local fetcher = require("vault.fetcher")
local Object = require("vault.core.object")
local Filter = require("vault.filter")
local Tags = require("vault.tags")
local Note = require("vault.notes.note")

---@param paths_map VaultMap.paths - The list of paths to filter.
---@param tags_filter_opts VaultNotesPrefilterOpts - The filter options.
local function filter_paths_by_tags(paths_map, tags_filter_opts)
    local is_exclude_only = false
    local note_filter_opts_tbl_copy = vim.deepcopy(notes_filter_opts)
    note_filter_opts_tbl_copy.by = nil
    local tags_filter_opts_tbl = note_filter_opts_tbl_copy

    if #notes_filter_opts.include == 0 and #notes_filter_opts.exclude > 0 then
        tags_filter_opts_tbl.include = notes_filter_opts.exclude
        tags_filter_opts_tbl.exclude = {}
        is_exclude_only = true
    end

    local tags_filter_opts = FilterOpts(tags_filter_opts_tbl)
    ---@type VaultTags
    local tags = Tags(tags_filter_opts)

    if is_exclude_only then
        -- local slugs_to_exclude = vim.tbl_flatten(tags:get_values_by_key("sources"))
        local slugs_to_exclude = tags:sources()
        paths_map = vim.tbl_filter(function(path)
            for _, note_path in ipairs(slugs_to_exclude) do
                if path == note_path then
                    return false
                end
            end
            return true
        end, paths_map)
    else
        paths_map = tags:get_values_by_key("sources")
    end
    return paths_map
end

---@return VaultMap.notes
local function filter_paths_by_basename(paths_map, notes_filter_opts)
    paths_map = vim.tbl_filter(function(path)
        path = path:lower()
        local path_basename = vim.fn.fnamemodify(path, ":t")
        local is_exclude_only = false
        if next(notes_filter_opts.include) == nil and next(notes_filter_opts.exclude) ~= nil then
            is_exclude_only = true
        end
        if is_exclude_only then
            return not vim.tbl_contains(notes_filter_opts.exclude, path_basename)
        else
            return vim.tbl_contains(notes_filter_opts.include, path_basename)
        end
    end, paths_map)
    return paths_map
end

--- Filter notes paths.
---
---@param paths_map VaultMap.paths - The list of paths to filter.
---@param prefilter_opts VaultNotesPrefilterOpts - The filter options.
---@return VaultMap.paths - The list of paths to filter.
local function prefilter_paths(paths_map, prefilter_opts)
    if not paths_map then
        error(error_formatter.missing_parameter("paths"))
    end
    if not prefilter_opts then
        error(error_formatter.missing_parameter("filter_opts"))
    end

    local notes_filter_opts = prefilter_opts

    local filter_by = notes_filter_opts.by
    if type(filter_by) == "string" then
        filter_by = { filter_by }
    end

    for _, key in ipairs(filter_by) do
        if key == "tags" then
            paths_map = filter_paths_by_tags(paths_map, notes_filter_opts)
        elseif "basename" then
            paths_map = filter_paths_by_basename(paths_map, notes_filter_opts)
        else
            error("Invalid `filter_by` argument: " .. vim.inspect(filter_by))
        end
    end
    return paths_map
end

--- Check if path is configured to be ignored.
---
---@param slug string - The `VaultSlug` to check.
---@return boolean
local function is_path_to_ignore(slug)
    for _, ignore_pattern in ipairs(config.ignore) do
        if utils.match(slug, ignore_pattern, "startswith") then
            return true
        end
    end
    return false
end

---@alias VaultMap.notes table<string, VaultNote>
---@alias VaultMap.notes.groups table<string, VaultNotesGroup>
---@alias VaultArray.notes VaultNote[]

---@class VaultNotes: VaultObject -- The `VaultNotes` class. It holds all the notes.
--- This is the main object that holds all the notes.
--- It responsible for filtering, sorting, and grouping notes.
---@field all VaultNotes - The initial `VaultNotes` object.
---@field _raw_map VaultMap.notes - The read-only map of notes. Do not modify directly. Please.
---@field map VaultMap.notes - The dynamic map of notes. Dynamically updated when using `VaultNotes` methods.
---@field groups VaultMap.notes.groups - The map of `VaultNotesGroup` objects.
---@field current function|VaultNotesGroup - The map of notes. Dynamically updated when using `VaultNotes` methods.
---@field linked function|VaultNotesGroup - `VaultNotesGroup` object with linked notes only. (notes with any incoming or outgoing links)
---@field orphans function|VaultNotesGroup - `VaultNotesGroup` object with orphan notes only. (notes without any incoming or outgoing links)
---@field leaves function|VaultNotesGroup - `VaultNotesGroup` object with leaf notes only. (notes without outgoing links)
---@field wikilinks function|VaultWikilinks - `VaultWikilinks` object.
---@field tags VaultTags - `VaultTags` object.
---@field count number|fun(self: VaultNotes): number - The count of the dynamic map of notes.
---@field duplicates table<string, table<string, string>> - The list of tables with duplicate pathes
local Notes = Object("VaultNotes")

function Notes:load_with_ripgrep()
    local map = fetcher.paths()
    for _, data in pairs(map) do
        self:add_note(Note(data))
    end
end

function Notes:load_with_glob()
    ---@type VaultArray.paths
    local paths = vim.fn.globpath(config.root, "**/*" .. config.ext, true, true)
    ---@type VaultMap.paths
    local paths_map = {}

    -- Filter out ignored paths.
    for _, path in ipairs(paths) do
        if not is_path_to_ignore(path) then -- FIXME: This is not working.
            paths_map[path] = true
        end
    end

    if filter_opts then
        -- TODO: This is not working. Make it work.
        paths_map = prefilter_paths(paths_map, NotesFilterOpts(filter_opts))
    end

    state.set_global_key("paths.map", paths_map)

    ---@type VaultMap.slugs
    local slugs_map = {}
    for _, path in ipairs(paths) do
        local slug = utils.path_to_slug(path)
        if is_path_to_ignore(path) then
            goto continue
        end

        slugs_map[slug] = true
        paths_map[path] = true

        self:add_note(Note({
            path = path,
            slug = slug,
        }))

        ::continue::
    end
end

--- Create a new Notes object.
---
---@param filter_opts VaultNotesPrefilterOpts? -- Optional: The filter options to use.
function Notes:init()
    state.clear_all()

    self.map = {}
    self._raw_map = {}

    self:load_with_ripgrep()

    self._raw_map = self.map
    ---@type VaultMap.notes.groups
    self.groups = {}

    state.set_global_key("slugs.map", vim.tbl_keys(self.map))
    state.set_global_key("notes", self)
end

--- Create a `VaultNotesGroup` instance from `VaultNotes`
---
---@return VaultNotesGroup
function Notes:to_group()
    local NotesGroup = state.get_global_key("_class.VaultNotesGroup")
        or require("vault.notes.group")
    return NotesGroup(self)
end

--- Create a `VaultNotesCluster` instance from `VaultNotes`
---
---@param note VaultNote
---@param depth integer
---@return VaultNotesCluster
function Notes:to_cluster(note, depth)
    local NotesCluster = state.get_global_key("_class.VaultNotesCluster")
        or require("vault.notes.cluster")
    return NotesCluster(self, note, depth)
end

--- Return `VaultWikilinks` object from current set of notes.
---
---@return VaultWikilinks
function Notes:wikilinks()
    local Wikilinks = require("vault.wikilinks")
    return Wikilinks(self)
end

--- Get list of notes.
---
---@return VaultArray.notes
function Notes:list()
    return vim.tbl_values(self.map)
end

--- Get map of notes key values.
--- Value expected to be string. Later may be extended to other types.
---
---@param key string - The key to get the map of values by.
---@param lowercase boolean? - If value expected to be string, whether to lowercase it. Default: false
---@return VaultMap - The map of values.
---```lua
---local map_with_basenames = Notes():value_map_with_key("basename", true)
---assert(map_with_basenames == { ["foo.md"] = true, ["bar.md"] = true, ["baz.md"] = true })
---```
function Notes:value_map_with_key(key, lowercase)
    if not key then
        error(error_formatter.missing_parameter("key"))
    end

    ---@type VaultMap
    local map = {}
    for _, note in pairs(self.map) do
        if not note.data[key] then
            goto continue
        end
        if type(note.data[key]) == "string" then
            ---@type string
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
---
---@return integer
function Notes:count()
    return #vim.tbl_keys(self.map)
end

--- Get average content count of notes.
---
---@return number
function Notes:average_chars()
    ---@type number
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
---@return table<string, table<string, string>> - The list of tables with duplicate pathes
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
---
---@return VaultNote
function Notes:get_random_note()
    local notes_list = self:list()
    local random_note = notes_list[math.random(#notes_list)]

    return random_note
end

--- Check if note exists.
---
---@param key VaultNoteDataString - The key to search by.
---@param query string? - The value to search by.
---@param match_opt VaultMatchOptsKey? - The match option to use.
---@param case_sensitive boolean? - Whether to use case sensitive search. Default: false
---@return boolean
function Notes:has_note(key, query, match_opt, case_sensitive)
    if not key then
        error(error_formatter.missing_parameter("key"))
    end

    match_opt = match_opt or "exact"
    case_sensitive = case_sensitive or false

    if case_sensitive then
        key = key:lower()
        if query and type(query) == "string" then
            query = query:lower()
        end
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
            if case_sensitive then
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
---
---@param note VaultNote - The note to add.
---@return nil
function Notes:add_note(note)
    if not note then
        error(error_formatter.missing_parameter("note"))
    end
    if not self.map then
        error(error_formatter.missing_parameter("self.map"))
    end
    if note.class == nil or note.class.name ~= "VaultNote" then
        error(error_formatter.invalid_value("note", "VaultNote"))
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

    ---@type VaultNotes
    local notes_global_key = state.get_global_key("notes")
    -- Update global notes object if exists.
    if notes_global_key then
        notes_global_key.map[slug] = note
        notes_global_key._raw_map[slug] = note
    end
end

--- Fetch first `VaultNote` by `VaultNote.data[key]` value.
--- Since it could return more than one note if `VaultNote.data[key]` value is not unique.
--- It will return the first note in the list.
---
---@param search_term VaultNotesSearchTerm - The key to search by.
---@param query string - The value to search by.
---@param match_opt VaultMatchOptsKey? - The match option to use. Default: "exact"
---@param case_sensitive boolean? - Whether to use case sensitive search. Default: false
---@return VaultNote|nil
function Notes:fetch_note_by(search_term, query, match_opt, case_sensitive)
    if not search_term then
        error(error_formatter.missing_parameter("search_term"))
    end
    if not query then
        error(error_formatter.missing_parameter("query"))
    end
    if not match_opt then
        error(error_formatter.missing_parameter("match_opt"))
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
---@param query string - The query to search by.
---@param match_opt VaultMatchOptsKey? - The match option to use. Default: "exact"
---@param case_sensitive boolean? - Whether to use case sensitive search. Default: false
---@return VaultNote|nil
function Notes:fetch_note_by_slug(query, match_opt, case_sensitive)
    if not query then
        error(error_formatter.missing_parameter("slug"))
    end
    match_opt = match_opt or "exact"

    return self:fetch_note_by("slug", query, match_opt, case_sensitive)
end

--- Find note by path.
---
---@param query string - The query to search by.
---@param match_opt VaultMatchOptsKey? - The match option to use. Default: "exact"
---@param case_sensitive boolean? - Whether to use case sensitive search. Default: false
---@return VaultNote|nil
function Notes:fetch_note_by_path(query, match_opt, case_sensitive)
    if not query then
        error(error_formatter.missing_parameter("path"))
    end
    match_opt = match_opt or "exact"

    return self:fetch_note_by("path", query, match_opt, case_sensitive)
end

--- Fetch note by relpath.
---
---@param query string - The query to search by.
---@param match_opt VaultMatchOptsKey? - The match option to use. Default: "exact"
---@param case_sensitive boolean? - Whether to use case sensitive search. Default: false
---@return VaultNote|nil
function Notes:fetch_note_by_relpath(query, match_opt, case_sensitive)
    if not query then
        error(error_formatter.missing_parameter("relpath"))
    end
    match_opt = match_opt or "exact"

    return self:fetch_note_by("relpath", query, match_opt, case_sensitive)
end

--- Filter notes with `VaultFilterOpts`.
---
---@param opts VaultFilter|VaultFilter.option - The filter options to use.
---```lua
---local notes = require("vault.notes")()
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
---}
---local filtered_notes = notes:filter(opts)
---assert(filtered_notes:count() < notes:count())
---```
---@return VaultNotesGroup
function Notes:filter(opts)
    if not opts then
        error(error_formatter.missing_parameter("opts"))
    end

    if not opts.class then
        opts = Filter(opts).opts
    end

    for _, opt in ipairs(opts) do
        if opt.search_term == "tags" then
            self:filter_by_tags(opt)
        end
    end

    return self:to_group()
end

--- Get notes filtered by tags.
---
---@param opts VaultFilter.option.tags|VaultFilter - The filter options to use.
---@return VaultNotesGroup
function Notes:filter_by_tags(opts)
    if not opts then
        error(error_formatter.missing_parameter("opts"))
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
---@param key NoteMetadataKey - The key to search by.
---@return VaultNotesGroup
function Notes:with_key(key)
    if not key then
        error(error_formatter.missing_parameter("key"))
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
---@param search_term VaultNotesSearchTerm - The key to search by.
---@param query string - The query to search by.
---@param match_opt VaultMatchOptsKey - The match option to use.
---@param case_sensitive boolean? - Whether to use case sensitive search. Default: false
---@return VaultNotesGroup
function Notes:with(search_term, query, match_opt, case_sensitive)
    if not search_term then
        error(error_formatter.missing_parameter("key"))
    end
    if not query then
        error(error_formatter.missing_parameter("query"))
    end
    if not match_opt then
        error(error_formatter.missing_parameter("match_opt"))
    end

    for slug, note in pairs(self.map) do
        ---@type string|nil
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
---@param query string - The query to search by.
---@param match_opt VaultMatchOptsKey? - The match option to use. Default: "exact"
---@param case_sensitive boolean? - Whether to use case sensitive search. Default: false
---@return VaultNotesGroup
function Notes:with_slug(query, match_opt, case_sensitive)
    if not query then
        error(error_formatter.missing_parameter("query"))
    end
    match_opt = match_opt or "exact"

    self = self:with("slug", query, match_opt, case_sensitive)

    return self:to_group()
end

--- Get notes with `VaultNote.data.path` that matches the query.
--- If no query is provided, it will return `VaultNotesGroup` that have `VaultNote.data.path` set
---
---@param query string - The query to search by.
---@param match_opt VaultMatchOptsKey? - The match option to use. Default: "startswith"
---@param case_sensitive boolean? - Whether to use case sensitive search. Default: false
---@return VaultNotesGroup
function Notes:with_path(query, match_opt, case_sensitive)
    if not query then
        error(error_formatter.missing_parameter("query"))
    end
    match_opt = match_opt or "startswith"

    self = self:with("path", query, match_opt, case_sensitive)

    return self:to_group()
end

--- Get notes with `VaultNote.data.relpath`.
--- If no query is provided, it will return `VaultNotesGroup` that have `VaultNote.data.relpath` set
--- Useful for filtering notes that are in the same directory.
---
---@param query string - The query to search by.
---@param match_opt VaultMatchOptsKey? - The match option to use. Default: "startswith"
---@param case_sensitive boolean? - Whether to use case sensitive search. Default: false
---@return VaultNotesGroup
function Notes:with_relpath(query, match_opt, case_sensitive)
    if not query then
        error(error_formatter.missing_parameter("query"))
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
---@param query string - The query to search by.
---@param match_opt VaultMatchOptsKey? - The match option to use. Default: "startswith"
---@param case_sensitive boolean? - Whether to use case sensitive search. Default: false
---@return VaultNotesGroup
function Notes:with_basename(query, match_opt, case_sensitive)
    if not query then
        error(error_formatter.missing_parameter("query"))
    end
    match_opt = match_opt or "startswith"

    self = self:with("basename", query, match_opt, case_sensitive)

    return self:to_group()
end

--- Get notes with `VaultNote.data.stem`.
--- If no query is provided, it will return `VaultNotesGroup` that have `VaultNote.data.stem` set
---
---@param query string - The query to search by.
---@param match_opt VaultMatchOptsKey? - The match option to use. Default: "startswith"
---@param case_sensitive boolean? - Whether to use case sensitive search. Default: false
---@return VaultNotesGroup
function Notes:with_stem(query, match_opt, case_sensitive)
    if not query then
        error(error_formatter.missing_parameter("query"))
    end
    match_opt = match_opt or "startswith"

    self = self:with("stem", query, match_opt, case_sensitive)

    return self:to_group()
end

--- Get notes with `VaultNote.data.title`.
--- If no query is provided, it will return `VaultNotesGroup` that have `VaultNote.data.title` set
---
---@param query string? - The query to search by.
---@param match_opt VaultMatchOptsKey? - The match option to use. Default: "startswith"
---@param case_sensitive boolean? - Whether to use case sensitive search. Default: false
---@return VaultNotesGroup
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
---@param query string? - The query to search by.
---@param match_opt VaultMatchOptsKey? - The match option to use. Default: "contains"
---@param case_sensitive boolean? - Whether to use case sensitive search. Default: false
---@return VaultNotesGroup
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
---@param query string? - The query to search by.
---@param match_opt VaultMatchOptsKey? - The match option to use. Default: "contains"
---@param case_sensitive boolean? - Whether to use case sensitive search. Default: false
---@return VaultNotesGroup
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
---@param query string?- The query to search by.
---@param match_opt VaultMatchOptsKey? - The match option to use. Default: "contains"
---@param case_sensitive boolean? - Whether to use case sensitive search. Default: false
---@return VaultNotesGroup
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
---@param query string? - The query to search by.
---@param match_opt VaultMatchOptsKey? - The match option to use. Default: "exact"
---@param case_sensitive boolean? - Whether to use case sensitive search. Default: false
---@return VaultNotesGroup
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
---
---@param query string - The query to search by.
---@param match_opt VaultMatchOptsKey? - The match option to use. Default: "exact"
---@param case_sensitive boolean? - Whether to use case sensitive search. Default: false
---@return VaultNotesGroup
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
---
---@return VaultNotesGroup
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
---
---@return VaultNotesGroup
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
---
---@return VaultNotesGroup
function Notes:leaves()
    ---@type VaultWikilinks
    local wikilinks = self:wikilinks()
    ---@type VaultMap.slugs
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
---
---@see VaultWikilink
---@return VaultNotesGroup
function Notes:orphans()
    ---@type VaultWikilinks
    local wikilinks = self:wikilinks()
    ---@type VaultMap.slugs
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
---
---@return VaultNotesGroup
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

--- Get notes that has resolved links(Only)
---
--- Notes that have wikilinks that have corresponding note
---
---@return VaultNotesGroup
function Notes:with_outlinks_unresolved()
    -- Exclude notes that have no outlinks
    ---@type VaultMap.notes
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
---@param lowercase boolean? - Whether to lowercase title and stem. Default: true
---@return VaultNotesGroup
---```lua
---local notes = Notes():with_title_mismatched()
---local note = notes:get_random_note()
---assert(note.data.title ~= note.data.stem)
---```
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
---
---@return VaultNotes
function Notes:reset()
    self.map = self._raw_map
    return self
end

---@alias VaultNotes.constructor fun(filter_opts: VaultNotesPrefilterOpts?): VaultNotes
---@type VaultNotes|VaultNotes.constructor
local VaultNotes = Notes

state.set_global_key("_class.VaultNotes", VaultNotes)
return VaultNotes
