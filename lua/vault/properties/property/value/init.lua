local Object = require("vault.core.object")
local error_formatter = require("vault.utils.error")

local state = require("vault.core.state")
local data = require("vault.properties.property.value.data")

--- @alias VaultPropertyValue.Data.name vault.Property.Value.Data.name

--- Partial constructor input accepted by `PropertyValueData:init`.
--- All fields are optional because the caller may pass only what it knows.
--- @alias vault.Property.Value.Data.Partial { name?: string, type?: vault.Property.Value.Data.type, sources?: vault.Sources.map, properties?: table<string, vault.Property>|nil, count?: number }

--- @class vault.Property.Value.Data: vault.Object
--- @field name    vault.Property.Value.Data.name      - Display name of this value.
--- @field type    vault.Property.Value.Data.type      - Obsidian property type inferred at construction time.
--- @field sources vault.Sources.map|nil               - Map of note slugs that contain this value.
--- @field properties table<string, vault.Property>|nil - Properties that reference this value (rarely used).
--- @field count   number                              - Number of notes carrying this value.
local PropertyValueData = Object("VaultPropertyValueData")

--- Parse the type of the value according to the Obsidian documentation.
--- @param v string Raw value string
--- @return vault.Property.Value.Data.type
local function get_type(v)
    -- local text_pattern = [[^('|").*('|")$]]
    local list_pattern = "^%s*%-%s+.-%s*(%s*%-%s+.-%s*)*$"
    local number_pattern = "^%d+$"
    local checkbox_pattern = "(true|false)"
    local date_pattern = "^%d%d%d%d%-%d%d%-%d%d$"
    local datetime_pattern = "^%d%d%d%d%-%d%d%-%d%dT%d%d%:%d%d%:%d%d%+%d%d%:%d%d$"

    if v:match(list_pattern) then
        return "list"
    elseif v:match(number_pattern) then
        return "number"
    elseif v:match(checkbox_pattern) then
        return "checkbox"
    elseif v:match(datetime_pattern) then
        return "datetime"
    elseif v:match(date_pattern) then
        return "date"
    else
        return "text"
    end
end

--- Initialise a `VaultPropertyValueData` instance.
--- @param this VaultPropertyValue.Data.name|vault.Property.Value.Data.Partial
function PropertyValueData:init(this)
    if not this then
        error(error_formatter.missing_parameter("this"), 2)
    end
    self.name = this.name
    self.properties = this.properties or nil
    self.type = this.type or get_type(this.name or "")
    self.sources = this.sources or nil
    self.count = this.count or 1
end

--- Lazy-load a computed field from the `data` parser table.
--- If the key exists in `data`, the resolver is called and the result is cached.
--- @param key string Field name to resolve
--- @return any
function PropertyValueData:__index(key)
    --- @type fun(self: vault.Property.Value.Data): any
    local func = data[key]
    if func then
        local value = func(self)
        self[key] = value
    end
    if self[key] == nil then
        error(
            "Invalid key: "
                .. vim.inspect(key)
                .. ". Valid keys: "
                .. vim.inspect(vim.tbl_keys(data))
        )
    end
    return self[key]
end

--- A single observed value for a property, e.g. the string `"2024-01-01"` for a `date` property.
--- @class vault.Property.Value: vault.Object
--- @field data vault.Property.Value.Data  - Resolved data bag for this value instance.
--- @field init fun(self: vault.Property.Value, this: VaultPropertyValue.Data.name|vault.Property.Value.Data.Partial): vault.Property.Value
--- @field add_slug fun(self: vault.Property.Value, slug: vault.slug): vault.Property.Value - Register a note slug as a source for this value.
local PropertyValue = Object("VaultPropertyValue")

--- Create a new `VaultPropertyValue` instance.
---
--- @param this VaultPropertyValue.Data.name|vault.Property.Value.Data.Partial
function PropertyValue:init(this)
    if not this then
        error(error_formatter.missing_parameter("this"), 2)
    end
    if type(this) == "string" then
        this = { name = this }
    end

    if not this.name then
        error(error_formatter.missing_parameter("name"), 2)
    end

    self.data = PropertyValueData(this)
end

--- Register a note slug as a source for this value in `self.data.sources`.
---
--- @param slug vault.slug
--- @return vault.Property.Value
function PropertyValue:add_slug(slug)
    if not self.data.sources then
        self.data.sources = {}
    end
    if not self.data.sources[slug] then
        self.data.sources[slug] = true
    end
    return self
end

--- @alias vault.Property.Value.constructor fun(this: vault.Property.Value|vault.Property.Value.Data.Partial|string): vault.Property.Value
--- @type vault.Property.Value.constructor|vault.Property.Value
local VaultPropertyValue = PropertyValue
state.set_global_key("class.vault.Property.Value", VaultPropertyValue)

return VaultPropertyValue
