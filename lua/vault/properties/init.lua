local state = require("vault.core.state")
local utils = require("vault.utils")
local Filter = require("vault.filter")
local scanner = require("vault.scanner")
local Collection = require("vault.core.collection")

--- @alias vault.Properties.map table<string, vault.Property>
--- @alias vault.Properties.list table<integer, vault.Property>
--- @alias vault.Properties.sources table<string, table>

--- Represents a collection of |vault.Property| objects.
--- @class vault.Properties: vault.Object
--- @field map vault.Properties.map
--- @field sources fun(self: vault.Properties): vault.Properties.sources
--- @field list fun(self: vault.Properties): vault.Properties.list
local Properties = Collection:extend("VaultProperties")

--- Initializes the vault.Properties object by scanning all properties from the vault.
--- Sets the properties map and registers the properties globally.
function Properties:init()
    self.map = scanner.properties()
    state.set_global_key("properties", self)
end

--- Filters the properties based on the provided filter options.
--- Removes any properties that don't match the include rules or match the exclude rules.
--- @param opts vault.Filter|vault.Filter.option|vault.Filter.option[] Filter options
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
local VaultProperties = Properties

state.set_global_key("class.vault.Properties", VaultProperties)
return VaultProperties
