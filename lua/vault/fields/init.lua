-- Fields is key value pairs in the frontmatter, and dataview indlines.
local Object = require("vault.core.object")
local fetcher = require("vault.fetcher")

---@class VaultFields: VaultObject - Fields is key value pairs in the frontmatter, and dataview inlines.
---@field map table<string, VaultField> - A map of fields.
---@field list fun(self: VaultFields): VaultField[] - A list of fields.
---@field text fun(self: VaultFields): string - The text of the fields.
---@field sources fun(self: VaultFields): string[] - The sources of the fields.
local Fields = Object("VaultFields")

--- Create a new `VaultFields` instance.
---
---@return nil
function Fields:init()
    self.map = fetcher.inline_fields()
end

--- Get a map of keys to fields.
---
---@return table<string, boolean>
function Fields:keys()
    local keys = {}
    for k, _ in pairs(self.map) do
        keys[k] = true
    end
    return keys
end

--- Get a map of keys to values.
---
---@return table<string, VaultField.value>
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
---@return VaultField[]
function Fields:list()
    local list = {}
    for key, field in pairs(self.map) do
        for value, data in pairs(self.map) do
            table.insert(list, data)
        end
    end
    return list
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

-- print(vim.inspect(Fields():sources()))
-- local fields = Fields()
-- print(vim.inspect(fields:flatten()))
-- print(vim.inspect(fields:datas()))
