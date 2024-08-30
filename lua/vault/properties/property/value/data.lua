local PropertyValueDocumentation = require("vault.propertys.property.documentation")
--- @alias vault.Property.Value.data.name string - The name of the property. e.g., "foo-bar".
--- @alias vault.Property.Value.data.type string - The type of the property.
--- @alias vault.Property.Value.data.values vault.PropertyValue.data.value[] - The values of the property.
--- @alias vault.Property.Value.data.sources vault.Notes.data.slugs - The notes slugs of notes with the property.
--- @alias vault.Property.Value.data.documentation vault.PropertyValue.documentation
--- @alias vault.Property.Value.data.count number - The number of notes with the property.

--- @class vault.Property.Value.data
--- @field name vault.Property.Value.data.name - The name of the property. e.g., "foo-bar".
--- @field type vault.Property.data.type - The type of the property.
--- | "text" -- https://help.obsidian.md/Editing+and+formatting/Properties#^text-list
--- | "list"
--- | "number"
--- | "checkbox"
--- | "date"
--- | "datetime"
--- @field sources vault.Sources.map - The notes slugs of notes with the property.
--- @field documentation vault.PropertyValue.documentation
--- @field count number - The number of notes with the property.

--- @class vault.PropertyValue.data.parser
--- @field sources fun(property_data: vault.Property.Value.data): vault.Notes.data.slugs - The notes slugs of notes with the property.
--- @field children fun(property_data: vault.Property.Value.data): vault.PropertyValueChildren - The children of the property.
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
--- @param property_data vault.Property.Value.data
--- @return vault.PropertyValueChildren
data.values = function(property_data)
    local property_name = property_data.name
    if not property_name then
        error("fetch_values(property_name) - property_name is nil", 2)
    end
    return property_data.values
end

return data
