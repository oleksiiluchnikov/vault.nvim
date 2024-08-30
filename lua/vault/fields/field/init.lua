--- `VaultField` class definition.
local Object = require("vault.core.object")

--- @classsvault.Field: vault.Object
--- @field key string - The key of the field.
--- @field value any - The value of the field.
--- @field source string - The source of the field.
local Field = Object("VaultNoteFrontmatterField")

--- @alias vault.Field.value table<string, any>

local function parse_field_value(value)
    -- Attempt to parse common data types
    if value:match('^".*"$') or value:match("^'.*'$") then
        -- String
        return value:sub(2, -2)
    elseif value:match(".-\n.+") then
        -- It is nested field
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
        -- Integer
        return tonumber(value)
    elseif value:match("^%d+%.%d+$") then
        -- Float
        return tonumber(value)
    elseif value:lower() == "true" or value:lower() == "false" then
        -- Boolean
        return value:lower() == "true"
    elseif value:match("^%[%[[^%[%]]+%]%]$") then
        -- Wikilink
        return value
    elseif value:match("^%[.*%]$") then
        -- Array
        local array = {}
        local inner = value:sub(2, -2)
        local elements = vim.split(inner, ",%s*")
        for _, element in ipairs(elements) do
            table.insert(array, parse_field_value(element))
        end
        return array
    elseif value:match("^%{.*%}$") then
        -- Table
        local tbl = {}
        local elements = vim.split(value:sub(2, -2), ",%s*")
        for _, element in ipairs(elements) do
            local k, v = element:match("^%s*([%w_]+):%s*(.*)$")
            if k == nil then
                error("Invalid table element: " .. vim.inspect(element))
            end
            tbl[k] = parse_field_value(v)
        end
        return tbl
    elseif value:match("^%[%[.*%]%]$") then
        -- Multiline string
        return value:sub(3, -3)
    else
        -- Fallback to treating as a string
        return value
    end
end

--- Create a new FrontmatterField object.
--- @param this table|string - The string to parse.
function Field:init(this)
    if type(this) == "string" then
        this = {
            line = this,
        }
    end
    if not type(this.line) == "string" then
        error("Invalid argument: " .. vim.inspect(this))
    end
    local key, value = this.line:match([[^([%w_]-):%s*(.*)$]])
    if key == nil then
        return nil
    end
    self.key = key
    self.value = parse_field_value(value)
    self.source = this.source
end

--- Convert the FrontmatterField to a string.
--- @return string
function Field:__tostring()
    return self.key .. ":: " .. self.value
end

return Field
