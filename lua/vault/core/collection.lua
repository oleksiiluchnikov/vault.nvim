local Object = require("vault.core.object")
local state = require("vault.core.state")
local utils = require("vault.utils")
local Filter = require("vault.filter")
local Error = require("vault.utils.error")

--- @class vault.CollectionEntryWithSources: vault.CollectionEntryLike
--- @field data vault.CollectionEntryData & { sources?: table<vault.slug, table>, name?: string, line?: string, stem?: string }

--- @alias vault.CollectionValuesMapOpts { lowercase?: boolean, as_value?: boolean }
--- @alias vault.CollectionSlugList vault.slug[]
--- @alias vault.CollectionFilterInput string|vault.CollectionSlugList|vault.Filter|vault.Filter.option.partial|vault.Filter.option.partial[]

--- @class vault.CollectionGroup: vault.Collection

--- Base Collection class for managing groups of related objects
--- @class vault.Collection: vault.Object
--- @field map vault.CollectionMap<vault.CollectionEntryLike> Map of items in the collection
--- @field _map vault.CollectionMap<vault.CollectionEntryLike>
local Collection = Object("VaultCollection")

function Collection:init()
    --- @type vault.CollectionMap<vault.CollectionEntryLike>
    self.map = {}
    --- @type vault.CollectionMap<vault.CollectionEntryLike>
    self._map = {}
end

--- @return integer Number of items in the collection
function Collection:__len()
    return vim.tbl_count(self.map)
end

function Collection.load(_)
    error("Load method not implemented")
end

--- Push an item into the collection
--- @param item? vault.CollectionEntryLike Item to add
function Collection:push(item)
    if not item then
        return
    end
    if not item.data then
        error("Item must have a data field")
    end
    if not item.data.slug then
        error("Item must have a slug field")
    end
    self._map[item.data.slug] = item
    self.map[item.data.slug] = item
end

function Collection:push_all(items)
    --- @cast items vault.CollectionEntryLike[]
    for _, item in pairs(items) do
        self:push(item)
    end
end

--- Returns the number of items in the collection
--- @return integer Number of items
function Collection:count()
    return #vim.tbl_keys(self.map)
end

--- Convert collection to a list
--- @return vault.CollectionEntryLike[] List of items
function Collection:list()
    --- @type vault.CollectionEntryLike[]
    return vim.tbl_values(self.map)
end

--- Get a random item from the collection
--- @return vault.CollectionEntryLike|nil Random item from collection
function Collection:get_random()
    local items = self:list()
    if next(items) == nil then
        return nil
    end
    return items[math.random(#items)]
end

--- Check if a collection has entry with a specific key
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
--- @return boolean
--- @param key string Key to check
--- @param query? string Query to match
--- @param match_opt? vault.enum.MatchOpts.key Match option
--- @param case_sensitive? boolean Case sensitive match. Default: false
function Collection:has(key, query, match_opt, case_sensitive)
    if not key then
        local random_item = self:get_random()
        local item_keys = vim.tbl_keys(random_item.data)
        error(
            Error.MISSING_PARAMETER("key") .. " Available keys: " .. table.concat(item_keys, ", ")
        )
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

    for _, entry in pairs(self.map) do
        local data = entry.data
        if not data then
            return false
        end

        if not data[key] then
            return false
        end

        if not query then
            return true
        end

        if type(data[key]) ~= "string" then
            return false
        end

        local value = data[key]
        if case_sensitive == false then
            value = value:lower()
        end

        if utils.match(value, query, match_opt) then
            return true
        end
    end

    return false
end

--- Get values by a specific key from all items
--- @param key string Key to get values for
--- @return any[] Values for the key
function Collection:get_values_by_key(key)
    if not key then
        error(Error.MISSING_PARAMETER("key"))
    end
    local values = {}
    for _, item in pairs(self.map) do
        if item.data and item.data[key] then
            table.insert(values, item.data[key])
        end
    end
    return values
end

--- --- Filter collection by key/value
--- --- @param key string The key to filter by
--- --- @param value? string The value to filter by
--- --- @param match_opt? string The match option to use (default: "exact")
--- --- @return vault.Collection
--- function Collection:filter(key, value, match_opt)
---     if not key then
---         error(Error.MISSING_PARAMETER("key"))
---     end
---     match_opt = match_opt or "exact"
---
---     local filtered = {}
---     for id, item in pairs(self.map) do
---         if item.data and item.data[key] then
---             if not value or utils.match(item.data[key], value, match_opt) then
---                 filtered[id] = item
---             end
---         end
---     end
---     self.map = filtered
---     return self
--- end
---
--- --- Scann items that match the given key-value criteria
--- ---
--- --- @param search_keys string|string[] - The key(s) to search by.
--- --- @param pattern? string - The search pattern to match.
--- --- @param match_strategy? vault.enum.MatchOpts.key - The match strategy to use.
--- --- @param is_case_sensitive? boolean - Whether to use case sensitive search. Default: false
--- --- @return vault.CollectionGroup
--- function Collection:filter(search_keys, pattern, match_strategy, is_case_sensitive)
---     if not search_keys then
---         error(Error.MISSING_PARAMETER("search_keys"))
---     end
---
---     if type(search_keys) == "string" then
---         search_keys = { search_keys }
---     end
---
---     pattern = pattern or ""
---     match_strategy = match_strategy or "exact"
---     is_case_sensitive = is_case_sensitive or false
---
---     for item_key, entry in pairs(self.map) do
---         for _, search_key in ipairs(search_keys) do
---             --- @type string|nil
---             local field_value = entry.data[search_key]
---             if type(field_value) ~= "string" then
---                 goto continue
---             end
---             if not is_case_sensitive then
---                 field_value = field_value:lower()
---                 pattern = pattern:lower()
---             end
---             if not utils.match(field_value, pattern, match_strategy) then
---                 self.map[item_key] = nil
---             end
---             ::continue::
---         end
---     end
---
---     return self:to_group()
--- end

--- Converts the Collection instance to its corresponding Group type
--- For example, a VaultNotes collection becomes a VaultNotesGroup
---
--- Example:
--- ```lua
--- local notes = require("vault.notes")()
--- assert(notes.class.name == "VaultNotes")
---
--- local notes_group = notes:to_group()
--- assert(notes_group.class.name == "VaultNotesGroup")
--- ```
---
--- Details:
--- - Attempts to get the Group class from global state first
--- - Falls back to requiring the group module if not found in state
--- - Automatically derives the group class name from the collection class name
--- - Creates and returns a new Group instance with current collection data
---
--- @return vault.CollectionGroup
function Collection:to_group()
    local group_name = self.class.name:gsub("Vault", "")
    local Group = state.get_global_key(string.format("class.vault.%sGroup", group_name))
    if not Group then
        local ok, required = pcall(require, string.format("vault.%s.group", group_name:lower()))
        if ok then
            Group = required
        end
    end
    if Group then
        return Group(self)
    end

    --- @type vault.CollectionGroup
    local copy = self.class()
    copy.map = {}
    for k, v in pairs(self.map) do
        copy.map[k] = v
    end
    return copy
end

--- Apply filter to collection
--- @param opts table|vault.Filter Filter options. Can be:
--- - A table with: search_term (string), include (string[]), exclude (string[]), match_opt (string), mode (string), case_sensitive (boolean)
--- - A key (string) and value (string) pair for simple filtering
--- - A vault.Filter object
--- @param value? string Optional value when using simple key/value filtering
--- @param match_opt? vault.enum.MatchOpts.key Optional match option for simple filtering
--- @param case_sensitive? boolean Optional case sensitivity for simple filtering
--- @return vault.CollectionGroup
function Collection:filter(opts, value, match_opt, case_sensitive)
    if not opts then
        error(Error.MISSING_PARAMETER("opts"))
    end

    -- Handle simple key/value filtering
    if type(opts) == "string" then
        local key = opts
        match_opt = match_opt or "exact"
        --- @type vault.CollectionMap<vault.CollectionEntryLike>
        local filtered = {}
        for id, item in pairs(self.map) do
            if item.data and item.data[key] then
                if not value or utils.match(item.data[key], value, match_opt) then
                    filtered[id] = item
                end
            end
        end
        self.map = filtered
        return self:to_group()
    end

    -- Handle slug-array filtering: filter({ "slug-a", "slug-b", ... })
    -- Keeps only items whose map key (or data.slug) appears in the list.
    if vim.islist(opts) and #opts > 0 and type(opts[1]) == "string" then
        -- Disambiguate from positional Filter args like { "tags", {...}, {}, "startswith", "all" }
        -- by checking that opts[1] is NOT a known NoteData search_term field.
        local NoteData = require("vault.notes.note.data")
        if not NoteData[opts[1]] then
            --- @type table<vault.slug, boolean>
            local slug_set = {}
            for _, slug in ipairs(opts) do
                slug_set[slug] = true
            end
            --- @type vault.CollectionMap<vault.CollectionEntryLike>
            local filtered = {}
            for id, item in pairs(self.map) do
                local item_slug = (item.data and item.data.slug) or id
                if slug_set[item_slug] or slug_set[id] then
                    filtered[id] = item
                end
            end
            self.map = filtered
            return self:to_group()
        end
    end

    -- Handle VaultFilter or filter options table
    if not opts.class or opts.class.name ~= "VaultFilter" then
        opts = Filter(opts).opts
    end

    --- @cast opts vault.Filter.option.normalized[]

    for _, opt in ipairs(opts) do
        --- @type string[]
        local search_keys = type(opt.search_term) == "string" and { opt.search_term }
            or opt.search_term
        local pattern = table.concat(opt.include or {}, " ")
        local exclude_pattern = table.concat(opt.exclude or {}, " ")
        case_sensitive = case_sensitive or opt.case_sensitive or false
        local match_strategy = opt.match_opt or "exact"

        for item_key, entry in pairs(self.map) do
            local should_keep = false
            for _, search_key in ipairs(search_keys) do
                local field_value = entry.data[search_key]
                if type(field_value) ~= "string" then
                    goto continue
                end

                if not case_sensitive then
                    field_value = field_value:lower()
                    pattern = pattern:lower()
                    exclude_pattern = exclude_pattern:lower()
                end

                -- Check includes
                if pattern ~= "" and utils.match(field_value, pattern, match_strategy) then
                    should_keep = true
                end

                -- Check excludes
                if
                    exclude_pattern ~= ""
                    and utils.match(field_value, exclude_pattern, match_strategy)
                then
                    should_keep = false
                    break
                end

                ::continue::
            end

            if not should_keep then
                self.map[item_key] = nil
            end
        end
    end

    return self:to_group()
end

--- Get sources map for collection items
--- @return vault.CollectionSourcesMap<vault.CollectionEntryWithSources> Map of sources
function Collection:sources()
    --- @type vault.CollectionSourcesMap<vault.CollectionEntryWithSources>
    local sources_map = {}

    for _, item in pairs(self.map) do
        --- @cast item vault.CollectionEntryWithSources
        if item.data and item.data.sources then
            for slug, _ in pairs(item.data.sources) do
                if not sources_map[slug] then
                    sources_map[slug] = {}
                end
                local key = item.data.name or item.data.line or item.data.stem
                if key and not sources_map[slug][key] then
                    sources_map[slug][key] = item
                end
            end
        end
    end

    return sources_map
end

--- Get a notes with duplicate value for a specific key
--- @param key string Key to check for duplicates
--- @return vault.GroupedValuesMap<vault.CollectionEntryLike> Table with values as keys and arrays of duplicate items
--- ```lua
--- local notes = require("vault.notes")()
--- local duplicates = notes:duplicates("name")
--- for value, items in pairs(duplicates) do
---     assert(#items > 1) -- Each entry has at least 2 items
--- end
--- ```
function Collection:duplicates(key)
    if not key then
        error(Error.MISSING_PARAMETER("key"))
    end
    local list = self:list()

    --- @type vault.GroupedValuesMap<vault.CollectionEntryLike>
    local value_map = {}
    --- @type vault.GroupedValuesMap<vault.CollectionEntryLike>
    local duplicates = {}

    -- First pass: collect items by their key values
    for _, item in ipairs(list) do
        local value = item.data[key]
        if value then
            if not value_map[value] then
                value_map[value] = {}
            end
            table.insert(value_map[value], item)
        end
    end

    -- Second pass: only keep groups with duplicates
    for value, items in pairs(value_map) do
        if #items > 1 then
            duplicates[value] = items
        end
    end

    return duplicates
end

--- Get map of values by a specific key.
--- This function creates a lookup map from an array of items based on a specified key.
--- It's optimized for performance and handles various data types elegantly.
---
--- Features:
--- - Fast O(n) performance with single-pass iteration
--- - Support for string, number, and boolean values
--- - Optional case-insensitive mapping
--- - Flexible value storage modes
--- - Built-in error handling and validation
---
--- Example usage:
--- ```lua
--- local values = {
---   { data = { basename = "foo.md", size = 1024 } },
---   { data = { basename = "bar.md", size = 2048 } }
--- }
---
--- -- Create a case-insensitive lookup map for basenames
--- local basename_map = values_map_by_key(values, "basename", { lowercase = true })
--- -- Result: { ["foo.md"] = true, ["bar.md"] = true }
---
--- -- Create a map with actual values for sizes
--- local size_map = values_map_by_key(values, "size", { as_value = true })
--- -- Result: { ["1024"] = 1024, ["2048"] = 2048 }
--- ```
---
--- @param self.map table[] Array of items, each containing a 'data' field
--- @param key string The key to extract from item.data
--- @param opts? vault.CollectionValuesMapOpts Optional configuration
--- @return vault.CollectionValueLookup Lookup map where keys are stringified values
--- @error "items must be a table" when items parameter is not a table
--- @error "key must be a string" when key parameter is not a string
--- @error "items table is empty" when items table has no elements
--- @error "invalid key '{key}'. Available keys: ..." when specified key doesn't exist
--- Reduce the collection to a single value
--- @generic T
--- @param reducer fun(accumulator: T, current: any): T Function to reduce items
--- @param initial? T Initial value (optional)
--- @return T|nil The final reduced value, or nil if collection is empty and no initial value
function Collection:reduce(reducer, initial)
    local items = self:list()
    if #items == 0 then
        return initial
    end

    local acc = initial or items[1]
    local start = initial and 1 or 2

    for i = start, #items do
        acc = reducer(acc, items[i])
    end

    return acc
end

--- Get map of values by a specific key.
function Collection:values_map_by_key(key, opts)
    -- Fast parameter validation
    if type(self.map) ~= "table" then
        error("items must be a table")
    end
    if type(key) ~= "string" then
        error("key must be a string")
    end

    -- Quick sample validation with early return for empty tables
    local sample_item = self.map[next(self.map)]
    if not sample_item then
        error("items table is empty")
    end

    -- Comprehensive key validation with helpful error message
    if not sample_item.data or not sample_item.data[key] then
        local available_keys = vim.tbl_keys(sample_item.data or {})
        error(
            string.format(
                "invalid key '%s'. Available keys: %s",
                key,
                table.concat(available_keys, ", ")
            )
        )
    end

    -- Optimize options access
    if type(opts) ~= "table" then
        opts = {}
    end
    opts = vim.tbl_extend("force", { lowercase = false, as_value = false }, opts)
    --- @cast opts { lowercase: boolean, as_value: boolean }
    local lowercase = opts.lowercase
    local as_value = opts.as_value

    -- Pre-allocate result table with expected size
    --- @type vault.CollectionValueLookup
    local result = {}

    -- Single-pass iteration with optimized value extraction
    for _, item in ipairs(self.map) do -- Using ipairs for faster sequential access
        local value = item.data[key]
        if value ~= nil then
            -- Optimize string conversion and case handling
            local map_key = lowercase and type(value) == "string" and tostring(value):lower()
                or tostring(value)

            result[map_key] = as_value and value or true
        end
    end

    return result
end

--- Reset the collection to initial state
function Collection:reset()
    state.clear_all()
    self:init()
end

--- Filter items by source slug
--- @param source_slug string The source slug to filter by
--- @param match_opt? vault.enum.MatchOpts.key Match option for the slug (default: "exact")
--- @param case_sensitive? boolean Case sensitive match (default: false)
--- @return vault.CollectionGroup Collection containing only items with matching source
function Collection:filter_by_source(source_slug, match_opt, case_sensitive)
    if not source_slug then
        error(Error.MISSING_PARAMETER("source_slug"))
    end

    match_opt = match_opt or "exact"
    case_sensitive = case_sensitive or false

    --- @type vault.CollectionMap<vault.CollectionEntryLike>
    local filtered = {}
    local search_slug = case_sensitive and source_slug or source_slug:lower()

    for id, item in pairs(self.map) do
        if item.data and item.data.sources then
            local found = false

            for slug, _ in pairs(item.data.sources) do
                local item_slug = case_sensitive and slug or slug:lower()

                if utils.match(item_slug, search_slug, match_opt) then
                    found = true
                    break
                end
            end

            if found then
                filtered[id] = item
            end
        end
    end

    self.map = filtered
    return self
end

state.set_global_key("class.vault.Collection", Collection)

--- @alias vault.CollectionPrefilterOpts table<string, string>

--- @alias vault.Collection.constructor fun(filter_opts: VaultCollectionPrefilterOpts?): vault.Notes
--- @type vault.Collection.constructor|vault.Collection
local VaultCollection = Collection
--- ```lua
--- local notes = require("vault.notes")()
---
--- assert(notes.class.name == "VaultNotes")
--- ```
--- @type vault.Collection.constructor|vault.Collection
return VaultCollection
