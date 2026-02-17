---@type table<string,vault.commands.complete>
local M = {}

---@alias vault.commands.complete fun(arg_lead?: string, line?: string, pos?: number): string[]

---ArgLead		the leading portion of the argument currently being
---		completed on
---CmdLine		the entire command line
---CursorPos	the cursor position in it (byte index)

---Returns the list of notes slugs
function M.api(_, _, _)
    return vim.tbl_keys(require("vault.api"))
end

--- Returns the list of notes slugs
--- @return vault.slug[]
function M.note_slugs(_, _, _)
    --- @type vault.slug[]
    local notes_slugs = require("vault.core.state").get_global_key("cache.notes.slugs")
        or require("vault.scanner").slugs()
    return vim.tbl_keys(notes_slugs)
end

--- Returns the list of note available data keys
--- @return string[]
function M.note_data_keys(_, _, _)
    return vim.tbl_keys(require("vault.notes.note.data"))
end

function M.dirs(_, line, _)
    line = line or ""
    -- line = line:gsub("^%S+%s*", "")
    local fargs = vim.split(line, " ")
    --- @type vault.slug[]
    local dirs = require("vault.dirs")():list()
    local completions = {}
    local utils = require("vault.utils")
    for _, dir in ipairs(dirs) do
        if utils.match(dir, line, "fuzzy", false) then
            table.insert(completions, dir)
        end
    end
    return completions
end

function M.tags(_, line, _)
    line = line or ""
    local fargs = vim.split(line, " ") or {}
    local config = require("vault.config")
    -- -- TODO: Add configuration to set completion strategy for tags, use fuzzy for now
    -- -- the name of the option could like opts.completion.tags.strategy
    local tags = vim.tbl_keys(require("vault.tags")():filter({
        name = "name",
        search_term = "tags",
        include = { fargs[#fargs] },
        exclude = {},
        match_opt = config.options.tags.completion.strategy,
        mode = "all",
    }).map)
    return tags
end

--- Returns the list of values for the given key
--- @return table<string,any>
function M.values_map_by_key(arg, _, _)
    return require("vault.notes")():values_map_by_key(arg)
end

--- Returns the list of match options
--- @return vault.enum.MatchOpts.key[]
function M.match_opts(_, _, _)
    return vim.tbl_keys(require("vault.enums").match_opts)
end

--- Returns the list of match types
--- @return vault.enum.MatchOpts.mode[]
function M.match_types(_, _, _)
    return vim.tbl_keys(require("vault.enums").filter_mode)
end

--- Returns the list of notes filters
function M.notes_filter(_, line, _)
    local args = vim.split(line, " ")
    table.remove(args, 1)
    if #args == 1 then
        return M.vault_notes_presets()
    elseif #args == 2 then
        return M.note_data_keys()
    elseif #args == 3 then
        return M.values_map_by_key(args[2])
    elseif #args == 4 then
        return M.values_map_by_key(args[2])
    elseif #args == 5 then
        return M.match_opts()
    elseif #args == 6 then
        return M.match_types()
    end
    return {}
end

--- Returns the list of tags for the current note
function M.note_tags(_, line, _)
    local fargs = vim.split(line, " ")
    local config = require("vault.config")
    if next(fargs) == nil then
        return {}
    end
    local current_path = vim.fn.expand("%:p")
    if type(current_path) ~= "string" then
        return {}
    end

    local tags = {}

    if not current_path:match(config.options.ext .. "$") then
        return M.tags()
    end

    local note = require("vault.notes.note")(vim.fn.expand("%:p"))
    tags = vim.tbl_keys(note.data.tags)
    return tags
end

--- Returns the list of vault notes presets
function M.vault_notes_presets(_, _, _)
    return { "linked", "orphans", "leaves", "by" }
end

--- Returns the list of dates
function M.dates(_, _, _)
    local from = tostring(os.date("%Y-%m-%d"))
    local to = tostring(os.time() - 60 * 60 * 24 * 365)
    local dates = require("dates").from_to(from, to)
    local date_values = {}
    for _, date in ipairs(dates) do
        table.insert(date_values, date.value)
    end
    return date_values
end

--- Returns the list of available statuses
function M.statuses(_, _, _)
    --TODO: Moved statuse to the frontmatter. Need to update this
    vim.notify("Implement")
    -- local tags = require("vault.tags")()
    -- local statuses = {}
    -- for _, tag in pairs(tags.map) do
    --     if tag.data.name:match("^status") and #tag.data.children > 0 then
    --         local status = tag.data.children[1]
    --         table.insert(statuses, status.d
    --     end
    -- end
    -- return statuses
end

function M.note(_, line, _)
    local fargs = vim.split(line, " ")
    --- @type vault.slug[]
    if #fargs == 1 then
        return {}
    elseif #fargs == 2 then
        return require("vault.notes.note"):get_methods()
    elseif #fargs == 3 then
        -- TODO: Decide what to return
        -- return args for the method?
        return M.note_slugs()
    elseif #fargs > 3 then
        -- TODO: Decide what to return
    end
end

return M
