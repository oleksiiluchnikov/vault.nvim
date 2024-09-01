local M = {}

--- Date pattern string used for date matching.
local DATE_PATTERN = "%d%d%d%d%-%d%d%-%d%d"

local has_cmp, cmp = pcall(require, "cmp")
if not has_cmp then
    error("`nvim-cmp` is not installed")
    return
end

local has_dates, Dates = pcall(require, "dates")
if not has_dates then
    error("`dates.nvim` is not installed")
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
        return [=[\[\d\-\s*\]+$]=]
    end

    --- @param request cmp.Context|table
    --- @param callback function
    source.complete = function(_, request, callback)
        local context = request.context
        if not context or type(context) ~= "table" then
            return
        end
        --- @type string
        local cursor_before_line = request.context.cursor_before_line

        local offset = request.offset
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
                            line = context.cursor.row - 1,
                            character = context.cursor.col - #input,
                        },
                        ["end"] = {
                            line = context.cursor.row - 1,
                            character = context.cursor.col,
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
            --- @type vault.Config.options|vault.Config
            local config = require("vault.config")
            local journal_dir = config.options.dirs.journal.daily
            for _, date in ipairs(dates) do
                local weekday = Dates.get_weekday(date)
                local path = journal_dir .. "/" .. date .. " " .. weekday .. ".md"
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
                                line = context.cursor.row - 1,
                                character = context.cursor.col - #typed_string - 1,
                            },
                            ["end"] = {
                                line = context.cursor.row - 1,
                                character = context.cursor.col,
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
    local tags = require("vault.tags")()
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

    --- @param request cmp.Context|table
    --- @param callback function
    source.complete = function(_, request, callback)
        local offset = request.offset
        local context = request.context

        local cursor_before_line = context.cursor_before_line
        local input = cursor_before_line:sub(offset - 1)
        --- @type string
        --- | "#"
        local prefix = cursor_before_line:sub(1, offset - 1)

        if not prefix then
            return
        elseif not prefix:match("#") then
            return
        end

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
                            line = context.cursor.row - 1,
                            character = context.cursor.col - #input,
                        },
                        ["end"] = {
                            line = context.cursor.row - 1,
                            character = context.cursor.col,
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

--- Register the cmp.Source for the `vault_properties` source.
--- It will provide completion for properties when we start typing inside
--- the frontmatter of a note from the beginning of the line.
--- @see cmp.Source
local function register_properties_source()
    --- TODO: Implement completion for properties
    --- use vim.tbl_keys(fetcher.properties()) to get all properties
end

function M.setup()
    register_tags_source()
    register_date_source()
    register_properties_source()
end

return M
