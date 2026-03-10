local Object = require("vault.core.object")
local function scanner()
    return require("vault.scanner")
end

local Field = Object("VaultNoteFrontmatterField")

local function parse_field_value(value)
    if value:match('^".*"$') or value:match("^'.*'$") then
        return value:sub(2, -2)
    elseif value:match(".-\n.+") then
        local array = {}
        local elements = vim.split(value, "\n")
        for _, element in ipairs(elements) do
            if element:match("^%s*-%s+.+") then
                element = element:match("^%s*-%s+(.+)")
            end
            table.insert(array, parse_field_value(element))
        end
        return array
    elseif value:match("^%d+$") then
        return tonumber(value)
    elseif value:match("^%d+%.%d+$") then
        return tonumber(value)
    elseif value:lower() == "true" or value:lower() == "false" then
        return value:lower() == "true"
    elseif value:match("^%[%[[^%[%]]+%]%]$") then
        return value
    elseif value:match("^%[.*%]$") then
        local array = {}
        local inner = value:sub(2, -2)
        local elements = vim.split(inner, ",%s*")
        for _, element in ipairs(elements) do
            table.insert(array, parse_field_value(element))
        end
        return array
    elseif value:match("^%{.*%}$") then
        local inner = value:sub(2, -2)
        local elements = vim.split(inner, ",%s*")
        local tbl = {}
        local all_parsed = true
        for _, element in ipairs(elements) do
            local k, v = element:match("^%s*([%w_%-]+):%s*(.*)$")
            if k == nil then
                all_parsed = false
                break
            end
            tbl[k] = parse_field_value(v)
        end
        if all_parsed then
            return tbl
        end
        return value
    elseif value:match("^%[%[.*%]%]$") then
        return value:sub(3, -3)
    else
        return value
    end
end

function Field:init(this)
    if type(this) == "string" then
        this = { line = this }
    end
    if type(this.line) ~= "string" then
        error("Invalid argument: " .. vim.inspect(this))
    end
    local key, value = this.line:match([[^([%w_%-]-):%s*(.*)$]])
    if key == nil then
        return nil
    end
    self.key = key
    self.value = parse_field_value(value)
    self.source = this.source
end

function Field:__tostring()
    return self.key .. ":: " .. self.value
end

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
    self.map = scanner().fields()
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

-- function Fields:sources()
--     local sources = {}
--     for key, values in pairs(self.map) do
--         for value, data in pairs(values) do
--             for slug, source in pairs(data.sources) do
--                 if not sources[slug] then
--                     sources[slug] = source
--                 else
--                     for line_number, source_line in pairs(source) do
--                         if not sources[slug][line_number] then
--                             sources[slug][line_number] = source_line
--                         else
--                             for column, source_column in pairs(source_line) do
--                                 if not sources[slug][line_number][column] then
--                                     sources[slug][line_number][column] = source_column
--                                 end
--                             end
--                         end
--                     end
--                 end
--             end
--         end
--     end
--     return sources
-- end

function Fields:datas()
    local datas = {}
    for _, field in pairs(self.map) do
        for _, data in pairs(field) do
            table.insert(datas, data)
        end
    end
    return datas
end

function Fields:flatten()
    local flattened = {}
    for _, field in pairs(self.map) do
        for _, data in pairs(field) do
            for _, source in pairs(data.sources) do
                for _, source_line in pairs(source) do
                    for _, source_column in pairs(source_line) do
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
    for _, field in pairs(self.map) do
        for value, _ in pairs(field) do
            text = text .. value .. "\n"
        end
    end
    return text
end

-- print(vim.inspect(Fields():sources()))
function Fields:sources_with_few_fields()
    local _ = self
    local same_line = {}
    return same_line
end

Fields.Field = Field
return Fields
-- print(vim.inspect(Fields():sources()))
-- local fields = Fields()
-- print(vim.inspect(fields:flatten()))
-- print(vim.inspect(fields:datas()))
