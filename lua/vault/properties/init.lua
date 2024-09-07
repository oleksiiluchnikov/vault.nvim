local Object = require("vault.core.object")
local state = require("vault.core.state")
local utils = require("vault.utils")
local Filter = require("vault.filter")
local fetcher = require("vault.fetcher")

--- @alias vault.Properties.map table<string, vault.Property>
--- @alias vault.Properties.list table<integer, vault.Property>
--- @alias vault.Properties.sources table<string, table>

--- Represents a collection of |vault.Property| objects.
--- @class vault.Properties: vault.Object
--- @field map vault.Properties.map
--- @field sources fun(self: vault.Properties): vault.Properties.sources
--- @field list fun(self: vault.Properties): vault.Properties.list
local Properties = Object("VaultProperties")

--- Initializes the vault.Properties object by fetching all properties from the vault.
--- Sets the properties map and registers the properties globally.
function Properties:init()
    self.map = fetcher.properties()
    state.set_global_key("properties", self)
end

--- @return integer
function Properties:count()
    return #vim.tbl_keys(self.map)
end

--- @return vault.Properties.list
function Properties:list()
    return vim.tbl_values(self.map)
end

--- Filters the properties based on the provided filter options.
--- Removes any properties that don't match the include rules or match the exclude rules.
--- @param opts vault.Filter.option.properties|vault.Filter.option.properties[] Filter options
--- @return vault.Properties -- Updated instance of vault.Properties with filtered properties
function Properties:filter(opts)
    if not opts then
        error("invalid argument: must be a table: " .. vim.inspect(opts))
    end

    if not opts.class then
        opts = Filter(opts, "properties")
    end

    opts = opts.opts

    --- Applies include filters to properties.
    --- Removes properties that don't match any include rules.
    --- @param property_name string Property name
    --- @param queries vault.List List of query strings
    --- @param match_result boolean
    --- @param match_opt vault.enum.MatchOpts.key Match option
    --- @param case_sensitive boolean Case sensitive
    local function apply_filter(property_name, queries, match_result, match_opt, case_sensitive)
        for _, query in ipairs(queries) do
            if utils.match(property_name, query, match_opt, case_sensitive) == match_result then
                self.map[property_name] = nil
            end
        end
    end

    for _, opt in ipairs(opts) do
        for property_name, _ in pairs(self.map) do
            apply_filter(property_name, opt.include, false, opt.match_opt, opt.case_sensitive)
            apply_filter(property_name, opt.exclude, true, opt.match_opt, opt.case_sensitive)
        end
    end

    return self
end

--- Return a list of values for a key from properties.
--- @param key string -- |vault.Property.Data| key to get values for
--- @return any[] -- Values for the key
function Properties:get_values_by_key(key)
    local values = {}
    for _, property in pairs(self.map) do
        if property.data[key] then
            table.insert(values, property.data[key])
        end
    end
    return values
end

--- @return vault.Property
function Properties:get_random_property()
    local properties = self:list()
    local random_property = properties[math.random(#properties)]
    return random_property
end

--- Filter properties by a specific key and value.
---@param key string The key to filter by. |vault.Property.Data| key to filter by.
---@param value? string The value to filter by. If not provided, all properties with the specified key will be returned.
---@param match_opt? vault.enum.MatchOpts.key The match option to use for filtering. Defaults to "exact" if not provided.
---@return vault.Properties.map A table containing the filtered properties.
---@usage
---```lua
--- -- Filter properties by name "created"
--- local properties = Properties():by("name", "created")
---
--- -- Filter properties by notes paths containing "journal"
--- local properties = Properties():by("notes_paths", "journal", "contains")
--- ```
function Properties:by(key, value, match_opt)
    assert(key, "missing `key` argument: string")
    match_opt = match_opt or "exact"
    local properties = self:list()
    local filtered_properties = {}
    for _, property in pairs(properties) do
        if utils.match(property.data[key], value, match_opt) then
            table.insert(filtered_properties, property)
        end
    end
    return filtered_properties
end

--- Return a map of all |vault.Property| objects by their sources.
--- ```lua
--- local properties = require("vault.properties")()
--- local sources_map = properties:sources()
---
--- -- Assert that the sources_map has the expected structure
--- assert(type(sources_map) == "table")
--- for slug, properties_map in pairs(sources_map) do
---     assert(type(slug) == "string")
---     assert(type(properties_map) == "table")
---     for property_name, property in pairs(properties_map) do
---         assert(type(property_name) == "string")
---         assert(type(property) == "table")
---         assert(property:is_a(vault.Property))
---     end
--- end
--- @return vault.Properties.sources
function Properties:sources()
    --- @type vault.Properties.sources
    local sources_map = {}
    for _, property in pairs(self.map) do
        for path, _ in pairs(property.data.sources) do
            local slug = utils.path_to_slug(path)
            if not sources_map[slug] then
                sources_map[slug] = {}
            end
            if not sources_map[slug][property.data.name] then
                sources_map[slug][property.data.name] = property
            end
        end
    end

    return sources_map
end

--- Return properties with empty values.
--- @return vault.Properties.list
function Properties:with_empty_values()
    local map = {}
    for _, property in pairs(self.map) do
        for key, value in pairs(property.data) do
            if key == "" then
                map[property.data.name] = value
                break
            end
        end
    end
    self.map = map
    return self
end

--- @alias vault.Properties.constructor fun(filter_opts?: table): vault.Properties
--- @type vault.Properties.constructor|vault.Properties
local M = Properties

state.set_global_key("class.vault.Properties", M)
return M
