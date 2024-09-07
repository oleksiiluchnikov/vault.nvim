local PropertyValueDocumentation = require("vault.propertys.property.documentation")
--- @alias vault.Property.Value.Data.name string - The name of the property. e.g., "foo-bar".
--- @alias vault.Property.Value.Data.type string - The type of the property.
--- @alias vault.Property.Value.Data.values vault.PropertyValue.Data.value[] - The values of the property.
--- @alias vault.Property.Value.Data.sources vault.Notes.Data.slugs - The notes slugs of notes with the property.
--- @alias vault.Property.Value.Data.documentation vault.PropertyValue.documentation
--- @alias vault.Property.Value.Data.count number - The number of notes with the property.

--- @class vault.Property.Value.Data
--- @field name vault.Property.Value.Data.name - The name of the property. e.g., "foo-bar".
--- @field type vault.Property.Data.type - The type of the property.
--- | "text" -- https://help.obsidian.md/Editing+and+formatting/Properties#^text-list
--- | "list"
--- | "number"
--- | "checkbox"
--- | "date"
--- | "datetime"
--- @field sources vault.Sources.map - The notes slugs of notes with the property.
--- @field documentation vault.PropertyValue.documentation
--- @field count number - The number of notes with the property.

--- @class vault.PropertyValue.Data.parser
--- @field sources fun(property_data: vault.Property.Value.Data): vault.Notes.Data.slugs - The notes slugs of notes with the property.
--- @field children fun(property_Data: vault.Property.Value.Data): vault.PropertyValueChildren - The children of the property.
local data = {}

data.name = function(property_data)
    return property_data.name
end

data.sources = function(property_data) end

data.documentation = function(property_data)
    return PropertyValueDocumentation(property_data.name)
end

data.type = function(property_data)
    return property_data.type
end

--- Fetch the values of a property.
--- @param property_Data vault.Property.Value.Data
--- @return vault.PropertyValueChildren
data.values = function(property_data)
    local property_name = property_data.name
    if not property_name then
        error("fetch_values(property_name) - property_name is nil", 2)
    end
    return property_data.values
end

return data
