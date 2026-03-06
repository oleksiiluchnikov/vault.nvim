--- Raw frontmatter reader for the type checker.
--- Preserves original types: wikilinks stay as "[[...]]", numbers as numbers.
--- Unlike shared.read_frontmatter_fields(), does NOT strip wikilink brackets.

local M = {}

--- Read raw frontmatter from a Markdown file, preserving original value types.
--- Wikilinks stay as `"[[Status - Backlog]]"` (not stripped).
--- Numbers stay as numbers. Quoted strings have quotes stripped.
---@param path string -- absolute path to the .md file
---@return table<string, any> -- field_name → raw value
function M.read_raw_frontmatter(path)
    ---@type table<string, any>
    local fields = {}
    local ok, lines = pcall(vim.fn.readfile, path, "", 60)
    if not ok then return fields end
    if not lines[1] or not lines[1]:match("^%-%-%-") then return fields end

    local current_key = nil ---@type string|nil
    local current_list = nil ---@type string[]|nil

    for i = 2, #lines do
        if lines[i]:match("^%-%-%-") then break end

        local list_item = lines[i]:match("^%s+%-%s+(.+)")
        if list_item and current_key and current_list then
            list_item = list_item:gsub('^"(.*)"$', "%1"):gsub("^'(.*)'$", "%1")
            table.insert(current_list, list_item)
        else
            local key, value = lines[i]:match("^([%w_%-]+):%s*(.*)")
            if key then
                -- Flush previous list key
                if current_key and current_list then
                    fields[current_key] = current_list
                end
                current_key = key
                current_list = nil
                value = vim.trim(value or "")

                if value == "" then
                    -- Start of a multi-line list (or empty value)
                    current_list = {}
                elseif value:match("^%[") and value:match("%]$") then
                    -- Inline array: [item1, item2]
                    ---@type string[]
                    local items = {}
                    local inner = value:match("^%[(.*)%]$") or ""
                    for item in inner:gmatch("[^,]+") do
                        item = vim.trim(item)
                        item = item:gsub('^"(.*)"$', "%1"):gsub("^'(.*)'$", "%1")
                        if item ~= "" then
                            table.insert(items, item)
                        end
                    end
                    fields[key] = items
                    current_key = nil
                else
                    -- Scalar value: try number first, then string
                    local num = tonumber(value)
                    if num and not value:match("[\"']") then
                        fields[key] = num
                        current_key = nil
                    else
                        value = value:gsub('^"(.*)"$', "%1"):gsub("^'(.*)'$", "%1")
                        fields[key] = value
                        current_key = nil
                    end
                end
            end
        end
    end

    -- Flush trailing list
    if current_key and current_list then
        fields[current_key] = current_list
    end

    return fields
end

--- Build a map of field names to their 0-indexed line numbers in the file.
--- Used to attach diagnostics to the correct line.
---@param path string
---@return table<string, integer> -- field_name → 0-indexed line number
function M.build_line_map(path)
    ---@type table<string, integer>
    local map = {}
    local ok, lines = pcall(vim.fn.readfile, path, "", 60)
    if not ok then return map end
    if not lines[1] or not lines[1]:match("^%-%-%-") then return map end

    for i = 2, #lines do
        if lines[i]:match("^%-%-%-") then break end
        local key = lines[i]:match("^([%w_%-]+):")
        if key then
            map[key] = i - 1 -- 0-indexed for vim.diagnostic
        end
    end

    return map
end

return M
