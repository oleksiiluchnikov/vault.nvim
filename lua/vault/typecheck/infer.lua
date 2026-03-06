--- Type inference engine for vault frontmatter.
--- Infers field types from template default values.
--- Pure Lua — no vim.* dependencies. Testable standalone.
---
--- ## Type inference rules
---
--- | Template default            | Inferred kind    | Required |
--- |----------------------------|-----------------|----------|
--- | `"[[Status - Backlog]]"`   | wikilink        | yes      |
--- | `""`                       | optional         | no       |
--- | `"task"` (plain string)    | string           | yes      |
--- | `20260306` (number)        | number           | yes      |
--- | `"draft | published"`      | enum             | yes      |
--- | `[]`                       | array_wikilink   | no       |
--- | `["[[Tasks]]"]`            | array_wikilink   | no       |
--- | `["tag1"]`                 | array_string     | no       |
--- | `"{{title}}"`              | title_template   | no       |
--- | `"{{date:FORMAT}}"`        | date_template    | no       |

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
---@field prefix string|nil   -- for wikilink: "Status - ", etc.
---@field values string[]|nil -- for enum: {"draft", "published"}
---@field required boolean

---@class vault.typecheck.Schema
---@field template_path string
---@field fields table<string, vault.typecheck.FieldType>

local M = {}

--- Trim whitespace from both ends of a string.
--- Local replacement for vim.trim to keep this module pure Lua.
---@param s string
---@return string
local function trim(s)
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

--- Infer the field type from a template default value.
---@param value any -- raw YAML value from template frontmatter
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

    if type(value) == "boolean" then
        return { kind = "string", required = true }
    end

    if type(value) ~= "string" then
        return { kind = "unknown", required = false }
    end

    return M.infer_string(value)
end

--- Infer type from an array (table) value.
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

--- Infer type from a string value.
---@param s string
---@return vault.typecheck.FieldType
function M.infer_string(s)
    s = trim(s)

    -- Empty string → optional field
    if s == "" then
        return { kind = "optional", required = false }
    end

    -- Template variables → skip validation
    if s:match("^{{title}}$") or s:match("^{{title:.*}}$") then
        return { kind = "title_template", required = false }
    end
    if s:match("^{{date:.*}}$") then
        return { kind = "date_template", required = false }
    end

    -- Wikilink: "[[Prefix - Value]]"
    if s:match("^%[%[.-%]%]$") then
        local inner = s:match("^%[%[(.-)%]%]$")
        ---@type string|nil
        local prefix = inner:match("^(.-%s+%-%s+)") -- e.g. "Status - "
        return { kind = "wikilink", required = true, prefix = prefix }
    end

    -- Enum: "draft | published"
    if s:match("|") then
        ---@type string[]
        local values = {}
        for v in s:gmatch("[^|]+") do
            table.insert(values, trim(v))
        end
        return { kind = "enum", required = true, values = values }
    end

    -- Plain string → required
    return { kind = "string", required = true }
end

--- Load a schema by reading a template file and inferring types for all fields.
---@param template_path string -- path to the template .md file
---@param read_frontmatter fun(path: string): table<string, any> -- injected reader
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
