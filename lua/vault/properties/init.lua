local state = require("vault.core.state")
local utils = require("vault.utils")
local Filter = require("vault.filter")
local function scanner()
    return require("vault.scanner")
end

local Collection = require("vault.core.collection")

---@param map vault.Properties.map|nil
---@return vault.Properties.map
local function copy_map(map)
    local copy = {}
    for key, value in pairs(map or {}) do
        copy[key] = value
    end
    return copy
end

--- @alias vault.Properties.map  table<string, vault.Property>
--- @alias vault.Properties.list table<integer, vault.Property>
--- @alias vault.Properties.sources table<string, table>

--- Represents a collection of |vault.Property| objects.
--- @class vault.Properties: vault.Object
--- @field map     vault.Properties.map
--- @field sources fun(self: vault.Properties): vault.Properties.sources
--- @field list    fun(self: vault.Properties): vault.Properties.list
local Properties = Collection:extend("VaultProperties")

--- Initialises the `vault.Properties` object by scanning all properties from the vault.
--- Sets the properties map and registers the collection globally.
function Properties:init()
    local cached = state.get_global_key("properties")
    if type(cached) == "table" and type(cached.map) == "table" then
        self.map = copy_map(cached.map)
        return
    end

    self.map = scanner().properties()
    state.set_global_key("properties", self)
end

--- Filter the properties collection using the provided filter options.
--- Removes any properties that do not match the include rules or that match the exclude rules.
--- @param opts vault.Filter|vault.Filter.option|vault.Filter.option[] Filter options
--- @return vault.Properties  Updated (mutated) instance with only matching properties.
function Properties:filter(opts)
    if not opts then
        error("invalid argument: must be a table: " .. vim.inspect(opts))
    end

    if not opts.class then
        opts = Filter(opts, "properties")
    end

    opts = opts.opts

    --- Apply include/exclude filter rules to a single property name.
    --- Properties are removed from `self.map` when they fail an include rule or
    --- match an exclude rule.
    --- @param property_name   string                   The property name being tested.
    --- @param queries         string[]                 List of query strings to match against.
    --- @param match_result    boolean                  Remove property when `utils.match` returns this value.
    --- @param match_opt       vault.enum.MatchOpts.key Match strategy.
    --- @param case_sensitive  boolean                  Whether matching is case-sensitive.
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

--- Return the subset of properties that have at least one empty-key value entry.
--- Mutates `self.map` in-place and returns `self`.
--- @return vault.Properties
function Properties:with_empty_values()
    --- @type vault.Properties.map
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
