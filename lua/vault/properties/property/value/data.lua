--- @alias vault.Property.Value.Data.name string - The name of the property value. e.g., "foo-bar".
--- @alias vault.Property.Value.Data.type
--- | "text"     # Plain text value (default)
--- | "list"     # YAML list / multi-value
--- | "number"   # Integer or float value
--- | "checkbox" # true / false boolean
--- | "date"     # ISO 8601 date  (YYYY-MM-DD)
--- | "datetime" # ISO 8601 datetime (YYYY-MM-DDThh:mm:ss+hh:mm)
--- @alias vault.Property.Value.Data.sources vault.Notes.Data.slugs - The note slugs that carry this property value.
--- @alias vault.Property.Value.Data.documentation vault.PropertyValue.documentation
--- @alias vault.Property.Value.Data.count number - The number of notes with this property value.

--- @class vault.Property.Value.Data
--- @field name vault.Property.Value.Data.name - The display name of the value.
--- @field type vault.Property.Value.Data.type - The Obsidian property-type inferred from the value string.
--- @field sources vault.Sources.map - Map of note slugs that carry this value.
--- @field documentation vault.PropertyValue.documentation
--- @field count number - The number of notes carrying this value.

--- @alias vault.Sources.map table<vault.slug, boolean|vault.source.lnums>
--- @alias vault.source.lnums integer[]

--- Parser / lazy-loader table for `vault.Property.Value.Data`.
--- Each key is an optional computed field; calling `data[key](property_data)` returns
--- the resolved value, which is then cached directly on the instance.
--- @class vault.PropertyValue.Data.parser
--- @field name   fun(property_data: vault.Property.Value.Data): vault.Property.Value.Data.name
--- @field sources fun(property_data: vault.Property.Value.Data): nil
--- @field documentation fun(property_data: vault.Property.Value.Data): nil
--- @field type   fun(property_data: vault.Property.Value.Data): vault.Property.Value.Data.type
--- @field values fun(property_data: vault.Property.Value.Data): table<string, vault.Property.Value.Data>|nil
---@type vault.PropertyValue.Data.parser
local data = {}

--- @param property_data vault.Property.Value.Data
--- @return vault.Property.Value.Data.name
data.name = function(property_data)
    return property_data.name
end

--- No-op: sources are populated by the scanner, not lazily computed.
--- @param _property_data vault.Property.Value.Data
--- @return nil
data.sources = function(_property_data) end

--- No-op: documentation is not yet implemented.
--- @param _property_data vault.Property.Value.Data
--- @return nil
data.documentation = function(_property_data)
    return nil
end

--- @param property_data vault.Property.Value.Data
--- @return vault.Property.Value.Data.type
data.type = function(property_data)
    return property_data.type
end

--- Return the values sub-table already stored on the data object.
--- @param property_data vault.Property.Value.Data
--- @return table<string, vault.Property.Value.Data>|nil
data.values = function(property_data)
    local property_name = property_data.name
    if not property_name then
        error("scann_values(property_name) - property_name is nil", 2)
    end
    return property_data.values
end

return data
