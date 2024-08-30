local Object = require("vault.core.object")
local error_formatter = require("vault.utils.fmt.error")

local state = require("vault.core.state")
local data = require("vault.properties.property.data")

--- @class vault.Property.Value.data: vault.Object
local PropertyValueData = Object("VaultPropertyValueData")

--- @alias vault.Property.Value.Data.Partial table - The partial data of the property.

--- Parse the type of the value. According to the Obsidian dcumentation.
--- @param v string
local function get_type(v)
    -- local text_pattern = [[^('|").*('|")$]]
    local list_pattern = "^%s*%-%s+.-%s*(%s*%-%s+.-%s*)*$"
    local number_pattern = "^%d+$"
    local checkbox_pattern = "^(true|false)$"
    local date_pattern = "^%d%d%d%d%-%d%d%-%d%d$"
    local datetime_pattern = "^%d%d%d%d%-%d%d%-%d%d%s%d%d%:%d%d$"

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
    end
    return "text"
end
--- @param this VaultPropertyValue.data.name|vault.Property.Value.Data.Partial
function PropertyValueData:init(this)
    if not this then
        error(error_formatter.missing_parameter("this"), 2)
    end
    self.name = this.name
    self.type = this.type or get_type(this.name or "")
    self.sources = this.sources or nil
    self.count = this.count or 1
end

--- Fetch the data if it is not already cached.
---
--- @param key string -- `VaultPropertyValue.data` key
--- @return any
function PropertyValueData:__index(key)
    --- @type fun(self: vault.Property.Value.data): any
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

--- @class vault.Property.Value: vault.Object
--- @field data vault.Property.Value.data - The data of the property.
--- @field init fun(self: vault.Property.Value, this: VaultPropertyValue.data.name|vault.Property.Value.Data.Partial): vault.Property.Value
--- @field add_slug fun(self: vault.Property.Value, slug: string): vault.Property.Value - Add a slug to the `self.data.sources` table.
local PropertyValue = Object("VaultPropertyValue")

--- Create a new `VaultPropertyValue` instance.
---
--- @param this VaultPropertyValue.data.name|vault.Property.Value.Data.Partial
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

--- Add a slug to the `self.data.sources` `VaultMap`.
---
--- @param slug string
--- @return vault.Property.Value
function PropertyValue:add_slug(slug)
    if not self.data.sources[slug] then
        self.data.sources[slug] = true
    end
    return self
end

--- @alias vault.Property.Value.constructor fun(this: vault.Property.Value|table|string): vault.Property.Value
--- @type vault.Property.Value.constructor|vault.Property.Value
local VaultPropertyValue = PropertyValue
state.set_global_key("class.vault.Property.Value", VaultPropertyValue)

return VaultPropertyValue
