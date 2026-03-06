--- Prototype B — Module 1: Type inference engine
--- Infers field types from template default values.
--- THROWAWAY — reference only, will not ship as-is.

---@alias vault.typecheck.FieldKind
---| "wikilink"        # "[[Prefix - Value]]" → must be wikilink matching prefix
---| "string"          # "some value" → required non-empty string
---| "number"          # 12345 → must be numeric
---| "optional"        # "" → may be blank
---| "date_template"   # "{{date:FORMAT}}" → auto-generated, skip
---| "title_template"  # "{{title}}" → auto-generated, skip
---| "enum"            # "a | b | c" → must be one of values
---| "array_wikilink"  # [] or ["[[...]]"] → array of wikilinks
---| "array_string"    # ["tag1", "tag2"] → array of strings
---| "unknown"         # can't infer

---@class vault.typecheck.FieldType
---@field kind vault.typecheck.FieldKind
---@field prefix string|nil
---@field values string[]|nil
---@field required boolean

---@class vault.typecheck.Schema
---@field template_path string
---@field fields table<string, vault.typecheck.FieldType>

local M = {}

---@param value any
---@return vault.typecheck.FieldType
function M.infer(value)
    if value == nil then
        return { kind = "unknown", required = false }
    end

    if type(value) == "table" then
        return M.infer_array(value)
    end

    if type(value) == "number" then
        return { kind = "number", required = true }
    end

    if type(value) ~= "string" then
        return { kind = "unknown", required = false }
    end

    return M.infer_string(value)
end

---@param arr any[]
---@return vault.typecheck.FieldType
function M.infer_array(arr)
    if #arr == 0 then
        return { kind = "array_wikilink", required = false }
    end
    local first = arr[1]
    if type(first) == "string" and first:match("^%[%[.-%]%]$") then
        return { kind = "array_wikilink", required = false }
    end
    return { kind = "array_string", required = false }
end

---@param s string
---@return vault.typecheck.FieldType
function M.infer_string(s)
    s = vim.trim(s)

    if s == "" then
        return { kind = "optional", required = false }
    end

    if s:match("^{{title}}$") or s:match("^{{title:.*}}$") then
        return { kind = "title_template", required = false }
    end

    if s:match("^{{date:.*}}$") then
        return { kind = "date_template", required = false }
    end

    if s:match("^%[%[.-%]%]$") then
        local inner = s:match("^%[%[(.-)%]%]$")
        local prefix = inner:match("^(.-%s+%-%s+)")
        return { kind = "wikilink", required = true, prefix = prefix }
    end

    if s:match("|") then
        ---@type string[]
        local values = {}
        for v in s:gmatch("[^|]+") do
            table.insert(values, vim.trim(v))
        end
        return { kind = "enum", required = true, values = values }
    end

    return { kind = "string", required = true }
end

---@param template_path string
---@param read_frontmatter fun(path: string): table<string, any>
---@return vault.typecheck.Schema
function M.load_schema(template_path, read_frontmatter)
    local raw = read_frontmatter(template_path)
    ---@type table<string, vault.typecheck.FieldType>
    local fields = {}
    for key, value in pairs(raw) do
        fields[key] = M.infer(value)
    end
    return { template_path = template_path, fields = fields }
end

return M
