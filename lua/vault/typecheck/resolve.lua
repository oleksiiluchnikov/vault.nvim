--- Template resolver for vault frontmatter type checking.
--- Resolves: note categories → category note → template field → template path.

local M = {}

local frontmatter = require("vault.typecheck.frontmatter")

--- Resolve the template path from a note's categories field.
---
--- Chain:
---   categories: ["[[Tasks]]"]
---     → find Tasks.md (category note)
---       → read template: "[[task-template]]"
---         → strip wikilink brackets → Templates/task-template.md
---
---@param categories string[]|nil -- raw category values from note frontmatter
---@param vault_root string -- absolute path to vault root
---@return string|nil template_path -- absolute path to template file, or nil
---@return string|nil error -- error message if resolution failed
function M.resolve(categories, vault_root)
    -- No categories
    if not categories or (type(categories) == "table" and #categories == 0) then
        return nil, "no categories field"
    end

    -- Ensure table
    if type(categories) == "string" then
        categories = { categories }
    end

    -- Multiple categories
    if #categories > 1 then
        return nil, "multiple categories not supported (got " .. #categories .. ")"
    end

    local raw = categories[1]
    -- Strip wikilink brackets from category name
    local cat_name = raw:match("^%[%[(.-)%]%]$") or raw

    -- Search for the category note in known locations
    ---@type string|nil
    local cat_path
    local search_paths = {
        vault_root .. "/" .. cat_name .. ".md",
        vault_root .. "/Categories/" .. cat_name .. ".md",
        vault_root .. "/References/" .. cat_name .. ".md",
    }

    for _, p in ipairs(search_paths) do
        if vim.fn.filereadable(p) == 1 then
            cat_path = p
            break
        end
    end

    if not cat_path then
        return nil, "category note not found: " .. cat_name
    end

    -- Read template field from category note
    local fields = frontmatter.read_raw_frontmatter(cat_path)
    local template_raw = fields.template
    if not template_raw or (type(template_raw) == "string" and vim.trim(template_raw) == "") then
        return nil, "category '" .. cat_name .. "' has no template field"
    end

    -- Strip wikilink brackets from template value: "[[task-template]]" → "task-template"
    local template_name = template_raw
    if type(template_name) == "string" then
        template_name = template_name:match("^%[%[(.-)%]%]$") or template_name
    end

    local template_path = vault_root .. "/Templates/" .. template_name .. ".md"
    if vim.fn.filereadable(template_path) == 0 then
        return nil, "template not found: " .. template_path
    end

    return template_path, nil
end

return M
