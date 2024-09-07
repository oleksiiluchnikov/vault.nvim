-- local PropertyDocumentation = require("vault.propertys.property.documentation")
--- @alias vault.Property.Data.name string - The name of the property. e.g., "foo-bar".
--- @alias vault.Property.Data.values vault.Property.Value[] - The values of the property.
--- @alias vault.Property.Data.sources vault.Notes.Data.slugs - The notes slugs of notes with the property.
--- @alias vault.Property.Data.documentation vault.Property.documentation
--- @alias vault.Property.Data.count number - The number of notes with the property.

--- @class vault.Property.Data
--- @field name vault.Property.Data.name - The name of the property. e.g., "foo-bar".
--- @field values vault.Property.Data.values - The values of the property.
--- @field sources vault.Sources.map - The notes slugs of notes with the property.
--- @field documentation vault.Property.documentation
--- @field count number - The number of notes with the property.

--- @class vault.Property.Data.parser
--- @field sources fun(property_data: vault.Property.Data): vault.Notes.Data.slugs - The notes slugs of notes with the property.
--- @field children fun(property_Data: vault.Property.Data): vault.PropertyChildren - The children of the property.
local data = {}

data.name = function(property_data)
    return property_data.name
end

-- data.sources = function(property_data) end

data.count = function(property_data)
    local count = 0
    for _, value in ipairs(property_data.sources) do
        count = count + 1
    end
    return count
end

-- data.documentation = function(property_data)
--     return PropertyDocumentation(property_data.name)
-- end

--- Fetch the values of a property.
--- @param property_Data vault.Property.Data
--- @return vault.Property.Value[]
data.values = function(property_data)
    local property_name = property_data.name
    if not property_name then
        error("fetch_values(property_name) - property_name is nil", 2)
    end
    return property_data.values
end

return data
