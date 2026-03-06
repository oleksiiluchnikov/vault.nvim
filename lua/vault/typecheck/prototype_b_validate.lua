--- Prototype B — Module 2: Validator
--- Validates a note's frontmatter against a schema.
--- THROWAWAY — reference only, will not ship as-is.

---@class vault.typecheck.Error
---@field field string
---@field message string
---@field lnum integer|nil
---@field path string|nil

local M = {}

---@alias vault.typecheck.WikilinkChecker fun(wikilink: string): string|nil

---@class vault.typecheck.ValidateOpts
---@field schema vault.typecheck.Schema
---@field raw_fields table<string, any>
---@field line_map table<string, integer>
---@field check_wikilink vault.typecheck.WikilinkChecker

---@param opts vault.typecheck.ValidateOpts
---@return vault.typecheck.Error[]
function M.validate(opts)
    local schema = opts.schema
    local raw = opts.raw_fields
    local line_map = opts.line_map
    local check_wl = opts.check_wikilink

    ---@type vault.typecheck.Error[]
    local errors = {}

    for field_name, field_type in pairs(schema.fields) do
        if field_name == "categories" then goto continue end

        local value = raw[field_name]
        local lnum = line_map[field_name]

        if value == nil then
            if field_type.required then
                table.insert(errors, {
                    field = field_name,
                    message = "missing required field '" .. field_name .. "'",
                    lnum = lnum,
                })
            end
            goto continue
        end

        local err = M.check_field(field_name, value, field_type, check_wl)
        if err then
            err.lnum = lnum
            table.insert(errors, err)
        end

        ::continue::
    end

    return errors
end

---@param name string
---@param value any
---@param ft vault.typecheck.FieldType
---@param check_wl vault.typecheck.WikilinkChecker
---@return vault.typecheck.Error|nil
function M.check_field(name, value, ft, check_wl)
    local kind = ft.kind

    if kind == "title_template" or kind == "date_template" or kind == "optional" then
        return nil
    end

    if kind == "number" then
        if type(value) ~= "number" and tonumber(value) == nil then
            return { field = name, message = "expected number, got '" .. tostring(value) .. "'" }
        end
        return nil
    end

    if kind == "wikilink" then
        return M.check_wikilink(name, value, ft, check_wl)
    end

    if kind == "enum" then
        return M.check_enum(name, value, ft)
    end

    if kind == "string" then
        if type(value) ~= "string" or vim.trim(value) == "" then
            return { field = name, message = "expected non-empty string" }
        end
        return nil
    end

    if kind == "array_wikilink" then
        return M.check_array_wikilink(name, value, check_wl)
    end

    if kind == "array_string" then
        if type(value) ~= "table" then
            return { field = name, message = "expected array, got " .. type(value) }
        end
        return nil
    end

    return nil
end

---@param name string
---@param value any
---@param ft vault.typecheck.FieldType
---@param check_wl vault.typecheck.WikilinkChecker
---@return vault.typecheck.Error|nil
function M.check_wikilink(name, value, ft, check_wl)
    local s = type(value) == "string" and value or tostring(value)
    if not s:match("^%[%[.-%]%]$") then
        return { field = name, message = "expected wikilink, got '" .. s .. "'" }
    end
    if ft.prefix then
        local inner = s:match("^%[%[(.-)%]%]$") or ""
        if not inner:match("^" .. vim.pesc(ft.prefix)) then
            return {
                field = name,
                message = "wikilink prefix mismatch: expected '" .. ft.prefix .. "', got '" .. inner .. "'",
            }
        end
    end
    local err = check_wl(s)
    if err then
        return { field = name, message = err }
    end
    return nil
end

---@param name string
---@param value any
---@param ft vault.typecheck.FieldType
---@return vault.typecheck.Error|nil
function M.check_enum(name, value, ft)
    local s = type(value) == "string" and value or tostring(value)
    if ft.values then
        for _, v in ipairs(ft.values) do
            if s == v then return nil end
        end
        return {
            field = name,
            message = "expected one of [" .. table.concat(ft.values, ", ") .. "], got '" .. s .. "'",
        }
    end
    return nil
end

---@param name string
---@param value any
---@param check_wl vault.typecheck.WikilinkChecker
---@return vault.typecheck.Error|nil
function M.check_array_wikilink(name, value, check_wl)
    if type(value) ~= "table" then
        return { field = name, message = "expected array, got " .. type(value) }
    end
    for i, item in ipairs(value) do
        if type(item) ~= "string" or not item:match("^%[%[.-%]%]$") then
            return {
                field = name,
                message = "item " .. i .. ": expected wikilink, got '" .. tostring(item) .. "'",
            }
        end
        local err = check_wl(item)
        if err then
            return { field = name, message = "item " .. i .. ": " .. err }
        end
    end
    return nil
end

return M
