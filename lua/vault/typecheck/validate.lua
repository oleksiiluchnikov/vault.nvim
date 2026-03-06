--- Field validator for vault frontmatter type checking.
--- Validates a note's frontmatter fields against a schema.
--- Pure Lua core — wikilink target checking is dependency-injected.

---@class vault.typecheck.Error
---@field field string
---@field message string
---@field lnum integer|nil -- 0-indexed line number
---@field path string|nil  -- set by caller for vault-wide reports

local M = {}

--- Trim whitespace (local, no vim dependency in validation logic).
---@param s string
---@return string
local function trim(s)
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

---@alias vault.typecheck.WikilinkChecker fun(wikilink: string): string|nil

---@class vault.typecheck.ValidateOpts
---@field schema vault.typecheck.Schema
---@field raw_fields table<string, any>
---@field line_map table<string, integer>
---@field check_wikilink vault.typecheck.WikilinkChecker

--- Validate a note's frontmatter against a schema.
--- Extra fields (in note but not in schema) are allowed.
--- Only fields defined in the schema are checked.
---@param opts vault.typecheck.ValidateOpts
---@return vault.typecheck.Error[]
function M.validate(opts)
    local schema = opts.schema
    local raw = opts.raw_fields
    local line_map = opts.line_map
    local check_wl = opts.check_wikilink

    ---@type vault.typecheck.Error[]
    local errors = {}

    -- Check multiple categories (type error)
    local cats = raw.categories
    if type(cats) == "table" and #cats > 1 then
        table.insert(errors, {
            field = "categories",
            message = "multiple categories not supported (got " .. #cats .. ")",
            lnum = line_map.categories,
        })
    end

    for field_name, field_type in pairs(schema.fields) do
        -- Skip categories — it's the discriminator, validated above
        if field_name == "categories" then goto continue end

        local value = raw[field_name]
        local lnum = line_map[field_name]

        -- Missing field
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

        -- Type-specific validation
        local err = M.check_field(field_name, value, field_type, check_wl)
        if err then
            err.lnum = lnum
            table.insert(errors, err)
        end

        ::continue::
    end

    return errors
end

--- Validate a single field value against its type.
---@param name string
---@param value any
---@param ft vault.typecheck.FieldType
---@param check_wl vault.typecheck.WikilinkChecker
---@return vault.typecheck.Error|nil
function M.check_field(name, value, ft, check_wl)
    local kind = ft.kind

    -- Template-generated and optional fields: skip
    if kind == "title_template" or kind == "date_template" or kind == "optional" or kind == "unknown" then
        return nil
    end

    if kind == "number" then
        return M.check_number(name, value)
    end

    if kind == "wikilink" then
        return M.check_wikilink(name, value, ft, check_wl)
    end

    if kind == "enum" then
        return M.check_enum(name, value, ft)
    end

    if kind == "string" then
        return M.check_string(name, value)
    end

    if kind == "array_wikilink" then
        return M.check_array_wikilink(name, value, check_wl)
    end

    if kind == "array_string" then
        return M.check_array_string(name, value)
    end

    return nil
end

---@param name string
---@param value any
---@return vault.typecheck.Error|nil
function M.check_number(name, value)
    if type(value) ~= "number" and tonumber(value) == nil then
        return { field = name, message = "expected number, got '" .. tostring(value) .. "'" }
    end
    return nil
end

---@param name string
---@param value any
---@return vault.typecheck.Error|nil
function M.check_string(name, value)
    if type(value) ~= "string" or trim(value) == "" then
        return { field = name, message = "expected non-empty string" }
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

    -- Must be wikilink syntax
    if not s:match("^%[%[.-%]%]$") then
        return { field = name, message = "expected wikilink, got '" .. s .. "'" }
    end

    -- Prefix check
    if ft.prefix then
        local inner = s:match("^%[%[(.-)%]%]$") or ""
        if not inner:match("^" .. vim.pesc(ft.prefix)) then
            return {
                field = name,
                message = "wikilink prefix mismatch: expected '"
                    .. ft.prefix .. "', got '" .. inner .. "'",
            }
        end
    end

    -- Target existence check
    local target_err = check_wl(s)
    if target_err then
        return { field = name, message = target_err }
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
            message = "expected one of ["
                .. table.concat(ft.values, ", ")
                .. "], got '" .. s .. "'",
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
        local target_err = check_wl(item)
        if target_err then
            return { field = name, message = "item " .. i .. ": " .. target_err }
        end
    end
    return nil
end

---@param name string
---@param value any
---@return vault.typecheck.Error|nil
function M.check_array_string(name, value)
    if type(value) ~= "table" then
        return { field = name, message = "expected array, got " .. type(value) }
    end
    return nil
end

return M
