-- - Completion module for vault.nvim
-- - Implements completion for:
--   - Dates with weekday detection
--   - Tags with # prefix
--   - YAML frontmatter properties
--   - Property values with context awareness
-- - Smart context detection (frontmatter boundaries, property lines)
local state = require("vault.core.state")
local config = require("vault.config")
local journal = require("vault.journal")

local M = {}

--- Date pattern string used for date matching.
-- local DATE_PATTERN = "%d%d%d%d%-%d%d%-%d%d"
local default_date_pattern = "%d%d%d%d%-%d%d%-%d%d"
local DATE_PATTERN = config.options.search_pattern.date.lua or default_date_pattern
-- local DATE_PATTERN = config.options.search_pattern.date.lua

local has_cmp, cmp = pcall(require, "cmp")
if not has_cmp then
    -- error("`nvim-cmp` is not installed")
    error("`hrsh7th/nvim-cmp` is not installed")
    return
end

local has_dates, Dates = pcall(require, "dates")
if not has_dates then
    error("`olekesiiluchnikov/dates.nvim` is not installed")
    return
end

local function is_available()
    if vim.bo.filetype == "markdown" then
        return true
    end
end

-- Disable duplicate set field warning
-- Registering the source requires re-declaring the field
-- But LSP features like completions and help tags still work
--- @diagnostic disable: duplicate-set-field

--- Register the cmp.Source for the `vault_date` source.
--- @see cmp.Source
local function register_date_source()
    --- @type cmp.Source
    --- @diagnostic disable-next-line: missing-fields
    local source = {
        is_available = is_available,
    }

    --- @return cmp.Source
    source.new = function()
        return setmetatable({}, { __index = source })
    end

    --- Return trigger characters for triggering completion (optional).
    --- We use \d, -, and space to trigger completion.
    --- @return string[]
    source.get_trigger_characters = function()
        return { "0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "-", " " }
    end

    --- Notice that it uses vim regex pattern, not lua regex pattern.
    source.get_keyword_pattern = function()
        return [=[\[\d\-*\s*\]+$]=]
    end

    ---@param params cmp.SourceCompletionApiParams
    ---@param callback fun(response: lsp.CompletionResponse|nil)
    function source.complete(_, params, callback)
        --- @type cmp.Context
        --- @type string
        local cursor_before_line = params.context.cursor_before_line

        local offset = params.offset
        local date_length = 11

        local input = cursor_before_line:sub(offset - 1)
        local typed_date = cursor_before_line:sub(offset - date_length, offset - 1)
        local typed_string = cursor_before_line:match("[%d%-]+$")

        if not typed_date or not typed_string then
            return
        end

        if typed_date:match(DATE_PATTERN) or typed_date:match(DATE_PATTERN .. " ") then
            --- @type lsp.CompletionItem[]
            local items = {}
            local year = typed_date:sub(1, 4)
            local month = typed_date:sub(6, 7)
            local day = typed_date:sub(9, 10)
            local time = os.time({
                year = year,
                month = month,
                day = day,
            })
            local weekday = tostring(os.date("%A", time))
            local new_text = weekday
            if #typed_date == 10 then
                new_text = " " .. weekday
            end

            --- @type lsp.CompletionItem
            local item = {
                label = weekday,
                kind = 12,
                textEdit = {
                    newText = new_text,
                    range = {
                        start = {
                            line = params.context.cursor.row - 1,
                            character = params.context.cursor.col - #input,
                        },
                        ["end"] = {
                            line = params.context.cursor.row - 1,
                            character = params.context.cursor.col,
                        },
                    },
                },
            }
            table.insert(items, item)
            callback({
                items = items,
                isIncomplete = true,
            })
        elseif typed_string:match("%d+") and #typed_string > 2 then
            --- @type string[]
            local dates = Dates.get(typed_string)
            --- @type lsp.CompletionItem[]
            local items = {}
            local daily_settings = journal.settings()
            if not daily_settings then
                callback({})
                return
            end
            for _, date in ipairs(dates) do
                local path = journal.path(date, daily_settings)
                local content = ""
                local file = io.open(path, "r")
                if file then
                    content = file:read("*a")
                    file:close()
                end
                local kind = 12
                if content == "" then
                    kind = 13
                end
                table.insert(items, {
                    label = date,
                    kind = kind,
                    textEdit = {
                        newText = date,
                        range = {
                            start = {
                                line = params.context.cursor.row - 1,
                                character = params.context.cursor.col - #typed_string - 1,
                            },
                            ["end"] = {
                                line = params.context.cursor.row - 1,
                                character = params.context.cursor.col,
                            },
                        },
                    },
                    documentation = {
                        kind = "markdown",
                        value = content,
                    },
                })
            end

            callback({
                items = items,
                isIncomplete = true,
            })
        else
            callback({ isIncomplete = true })
        end
    end
    cmp.register_source("vault_date", source.new())
end

local function register_tags_source()
    --- @class cmp.Source
    local source = {
        is_available = is_available,
    }

    --- @return cmp.Source
    source.new = function()
        return setmetatable({}, { __index = source })
    end

    source.get_trigger_characters = function()
        return { "#" }
    end

    source.get_keyword_pattern = function()
        return [=[\%(#\%(\w\|\-\|_\|\/\)\+\)]=]
    end

    ---@param params cmp.SourceCompletionApiParams
    ---@param callback fun(response: lsp.CompletionResponse|nil)
    function source.complete(_, params, callback)
        local offset = params.offset

        local cursor_before_line = params.context.cursor_before_line
        local input = cursor_before_line:sub(offset - 1)
        --- @type string
        --- | "#"
        local prefix = cursor_before_line:sub(1, offset - 1)

        if not prefix then
            return
        elseif not prefix:match("#") then
            return
        end

        --- @type vault.Tags
        local tags = state.get_global_key("tags") or require("vault.tags")()
        --- @type lsp.CompletionItem[]
        local items = {}
        for tag_name, _ in pairs(tags.map) do
            --- @type lsp.CompletionItem
            local item = {
                label = tag_name,
                kind = 14, -- Keyword
                textEdit = {
                    newText = tag_name,
                    range = {
                        start = {
                            line = params.context.cursor.row - 1,
                            character = params.context.cursor.col - #input,
                        },
                        ["end"] = {
                            line = params.context.cursor.row - 1,
                            character = params.context.cursor.col,
                        },
                    },
                },
                -- documentation = {
                --     kind = "markdown",
                --     value = tag.data.documentation:content(tag.data.name),
                -- },
            }
            table.insert(items, item)
        end
        callback({
            items = items,
            isIncomplete = true,
        })
    end

    cmp.register_source("vault_tag", source.new())
end

--- Check if the current line number is within a YAML frontmatter block
--- Frontmatter blocks are delimited by '---' markers at start and end
---@param lnum number The line number to check (1-indexed)
---@return boolean|false True if line is in frontmatter, false otherwise
---@return string|nil Error message if operation failed
local function is_in_frontmatter(lnum)
    local success, lines =
        pcall(vim.api.nvim_buf_get_lines, vim.api.nvim_get_current_buf(), 0, -1, false)
    if not success then
        return false
    end

    if #lines == 0 or not lines[1]:match("^---") then
        return false
    end

    local second_frotmatter_line_index = 0
    for i = 2, #lines do
        if lines[i]:match("^---") then
            second_frotmatter_line_index = i
            break
        end
    end

    if second_frotmatter_line_index < lnum then
        return false
    end
    return true
end

--- Register the cmp.Source for the `vault_properties` source.
--- It will provide completion for properties when we start typing inside
--- the frontmatter of a note from the beginning of the line.
--- @see cmp.Source
local function register_properties_sources()
    --- @class cmp.Source
    local source = {
        is_available = is_available,
    }

    --- @return cmp.Source
    source.new = function()
        return setmetatable({}, { __index = source })
    end

    source.get_keyword_pattern = function()
        -- return [=[^\S*]=] -- TODO: Make configurable
        return [=[^[A-Za-z0-9_-]\+$]=]
    end

    --- Validate if cursor is in a valid property position
    --- @param line string The line to check
    --- @return boolean is_valid If the position is valid for property completion
    --- @return string? error_message Optional error message if validation fails
    local function is_in_property(line)
        if not line then
            return false
        end

        -- Check if line already has a value part (after colon)
        if vim.split(line, ":")[2] then
            return false
        end

        -- Validate property name format
        local property_pattern = [=[^[A-Za-z0-9_-]+$]=]
        if not line:match(property_pattern) then
            return false
        end

        return true
    end

    ---@param params cmp.SourceCompletionApiParams
    ---@param callback fun(response: lsp.CompletionResponse|nil)
    function source.complete(_, params, callback)
        if is_in_frontmatter(params.context.cursor.row) == false then
            return
        end

        if is_in_property(params.context.cursor_before_line) == false then
            return
        end

        --- @type vault.Properties
        local properties = state.get_global_key("properties") or require("vault.properties")()

        --- @type lsp.CompletionItem[]
        local items = {}
        for property_name, _ in pairs(properties.map) do
            property_name = property_name .. ":"
            --- @type lsp.CompletionItem
            local item = {
                label = property_name,
                kind = 5,
                textEdit = {
                    newText = property_name,
                    range = {
                        start = {
                            line = params.context.cursor.row - 1,
                            character = 0,
                        },
                        ["end"] = {
                            line = params.context.cursor.row - 1,
                            character = params.context.cursor.col,
                        },
                    },
                    replaceText = property_name,
                },
                -- TODO: Add documentation
                -- documentation = {
                --     kind = "markdown",
                --     value = property.data.documentation:content(property.data.name),
                -- },
            }
            table.insert(items, item)
        end
        callback({
            items = items,
            isIncomplete = true,
        })
    end

    cmp.register_source("vault_properties", source.new()) -- TODO: Use a better name
end

--- Register the cmp.Source for the `vault_properties` source.
--- It will provide completion for properties when we start typing inside
--- the frontmatter of a note from the beginning of the line.
--- @see cmp.Source
local function register_property_values_source()
    --- @class cmp.Source
    local source = {
        is_available = is_available,
    }

    --- @return cmp.Source
    source.new = function()
        return setmetatable({}, { __index = source })
    end

    source.get_trigger_characters = function()
        return { " ", ":" }
    end

    source.get_keyword_pattern = function()
        return [=[%(\s*|\S*%)]=] -- TODO: Make configurable
    end

    ---@param params cmp.SourceCompletionApiParams
    ---@param callback fun(response: lsp.CompletionResponse|nil)
    function source.complete(_, params, callback)
        --- @type vault.Properties
        local properties = state.get_global_key("properties") or require("vault.properties")()
        if is_in_frontmatter(params.context.cursor.row) == false then
            return
        end

        local cursor_before_line = params.context.cursor_before_line
        -- local key = vim.fn.matchstr(cursor_before_line, [=[\v(^[A-Za-z0-9_-]+):.*$]=])
        if not cursor_before_line:find(":") then
            return
        end
        local key = vim.split(cursor_before_line, ":")[1]
        -- TODO: Add validation for frontmatter keys

        if not properties.map[key] then
            return
        end

        --- @type lsp.CompletionItem[]
        local items = {}

        --- @type table<string, vault.Property.Value>
        local values = properties.map[key].data.values
        local seen_values = {}

        for value_name, value in pairs(values) do
            local unquoted_value = string.match(value_name, [=[^['"](.+)['"]$]=], 1) or value_name
            if seen_values[unquoted_value] then
                goto continue
            end
            seen_values[unquoted_value] = true
            local new_text = value_name
            -- if last character is a colon in the cursor_before_line then add a space
            if cursor_before_line:sub(cursor_before_line:len()) == ":" then
                new_text = " " .. value_name
            end
            local value_type = value.data.type
            if value_type == "list" then
                new_text = "\n  - " .. new_text
            end
            --- @type lsp.CompletionItem
            local item = {
                label = unquoted_value,
                kind = 13,
                textEdit = {
                    newText = new_text,
                    range = {
                        start = {
                            line = params.context.cursor.row - 1,
                            character = params.context.cursor.col,
                        },
                        ["end"] = {
                            line = params.context.cursor.row - 1,
                            character = params.context.cursor.col,
                        },
                    },
                    replaceText = new_text,
                },
                documentation = {
                    kind = "markdown",
                    value = tostring(value.data.type),
                },
            }
            table.insert(items, item)
            ::continue::
        end
        callback({
            items = items,
            isIncomplete = true,
        })
    end

    cmp.register_source("vault_property_values", source.new()) -- TODO: Use a better name
end

function M.setup()
    register_tags_source()
    register_date_source()
    register_properties_sources()
    register_property_values_source()
end

return M
