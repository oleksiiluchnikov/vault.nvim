local Object = require("vault.core.object")
local fetcher = require("vault.fetcher")

--- @alias vault.Field.map table<string, vault.Field>

--- @class vault.Fields: vault.Object - Fields is key value pairs in the frontmatter, and Dataview inlines.
--- The Fields module provides an object oriented interface for working with the
--- key-value pairs in the frontmatter and dataview inlines of a Vault note.
--- @field map vault.Field.map - A map of keys to fields.
--- @field list fun(self: vault.Fields): vault.Field[] - A list of fields.
--- @field text fun(self: vault.Fields): string - The text of the fields.
--- @field sources fun(self: vault.Fields): string[] - The sources of the fields.
local Fields = Object("VaultFields")

--- Create a new `VaultFields` instance.
---
--- @return nil
function Fields:init()
    self.map = fetcher.fields()
end

--- Get a map of keys to fields.
---
--- @return table<string, boolean>
function Fields:keys()
    local keys = {}
    for k, _ in pairs(self.map) do
        keys[k] = true
    end
    return keys
end

--- Get a map of keys to values.
---
--- @return table<string, vault.Field.value>
function Fields:key_values()
    local key_values = {}
    for k, v in pairs(self.map) do
        table.insert(key_values, {
            key = k,
            value = v,
        })
    end
    return key_values
end

--- Get a list of fields.
---
--- @return vault.Field[]
function Fields:list()
    local list = {}
    for key, field in pairs(self.map) do
        for value, data in pairs(self.map) do
            table.insert(list, data)
        end
    end
    return list
end

--- Get list of keys with values count.
--- @return {key: string, count: number}[]
function Fields:keys_with_values_count()
    local keys = {}
    for key, field in pairs(self.map) do
        -- keys[key] = #vim.tbl_keys(field)
        table.insert(keys, {
            key = key,
            count = #vim.tbl_keys(field),
        })
    end
    table.sort(keys, function(a, b)
        return a.count > b.count
    end)
    return keys
end

function Fields:sources()
    local sources = {}
    for key, values in pairs(self.map) do
        for value, data in pairs(values) do
            for slug, source in pairs(data.sources) do
                if not sources[slug] then
                    sources[slug] = source
                else
                    for line_number, source_line in pairs(source) do
                        if not sources[slug][line_number] then
                            sources[slug][line_number] = source_line
                        else
                            for column, source_column in pairs(source_line) do
                                if not sources[slug][line_number][column] then
                                    sources[slug][line_number][column] = source_column
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    return sources
end

function Fields:datas()
    local datas = {}
    for key, field in pairs(self.map) do
        for value, data in pairs(field) do
            table.insert(datas, data)
        end
    end
    return datas
end

function Fields:flatten()
    local flattened = {}
    for key, field in pairs(self.map) do
        for value, data in pairs(field) do
            for slug, source in pairs(data.sources) do
                for line_number, source_line in pairs(source) do
                    for column, source_column in pairs(source_line) do
                        table.insert(flattened, source_column)
                    end
                end
            end
        end
    end
    return flattened
end

function Fields:text()
    local text = ""
    for key, field in pairs(self.map) do
        for value, data in pairs(field) do
            text = text .. value .. "\n"
        end
    end
    return text
end

-- print(vim.inspect(Fields():sources()))
function Fields:sources_with_few_fields()
    local sources = self:sources()
    local same_line = {}
    for slug, source in pairs(sources) do
        for row, cols in pairs(source) do
            if #cols > 1 then
                print(vim.inspect(cols))
            end
        end
    end
    return same_line
end

return Fields
-- print(vim.inspect(Fields():sources()))
-- local fields = Fields()
-- print(vim.inspect(fields:flatten()))
-- print(vim.inspect(fields:datas()))
