-- local PropertyDocumentation = require("vault.propertys.property.documentation")

--- @alias vault.Property.Data.name string - The name of the property. e.g., "foo-bar".
--- @alias vault.Property.Data.values vault.Property.Value[] - The values of the property.
--- @alias vault.Property.Data.sources vault.Notes.Data.slugs - The note slugs of notes that carry this property.
--- @alias vault.Property.Data.documentation vault.Property.documentation
--- @alias vault.Property.Data.count number - The number of notes with the property.

--- @class vault.Property.Data
--- @field name vault.Property.Data.name - The name of the property. e.g., "foo-bar".
--- @field values table<string, vault.Property.Value> - Map of value-name → Property.Value.
--- @field sources vault.Sources.map - Map of note slugs that carry this property.
--- @field documentation vault.Property.documentation
--- @field count number - The number of notes with the property.

--- Parser / lazy-loader table for `vault.Property.Data`.
--- Each key is an optional computed field; calling `data[key](property_data)` returns
--- the resolved value, which is then cached directly on the instance.
--- @class vault.Property.Data.parser
--- @field name   fun(property_data: vault.Property.Data): vault.Property.Data.name
--- @field count  fun(property_data: vault.Property.Data): number
--- @field values fun(property_data: vault.Property.Data): table<string, vault.Property.Value>
---@type vault.Property.Data.parser
local data = {}

--- @param property_data vault.Property.Data
--- @return vault.Property.Data.name
data.name = function(property_data)
    return property_data.name
end

-- data.sources = function(property_data) end

--- Count the number of source notes for this property.
--- @param property_data vault.Property.Data
--- @return number
data.count = function(property_data)
    local count = 0
    for _ in pairs(property_data.sources) do
        count = count + 1
    end
    return count
end

-- data.documentation = function(property_data)
--     return PropertyDocumentation(property_data.name)
-- end

--- Return the values map already stored on the data object.
--- @param property_data vault.Property.Data
--- @return table<string, vault.Property.Value>
data.values = function(property_data)
    local property_name = property_data.name
    if not property_name then
        error("scann_values(property_name) - property_name is nil", 2)
    end
    return property_data.values
end

return data
