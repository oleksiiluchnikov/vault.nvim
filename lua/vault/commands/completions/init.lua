---@type table<string,vault.commands.complete>
local M = {}

---@alias vault.commands.complete fun(arg_lead?: string, line?: string, pos?: number): string[]

---ArgLead		the leading portion of the argument currently being
---		completed on
---CmdLine		the entire command line
---CursorPos	the cursor position in it (byte index)

--- Context-aware completion for :Vault subcommands.
--- Walks the subcommand tree to offer completions at the correct depth.
function M.api(_, line, _)
    line = line or ""
    local parts = vim.split(line, "%s+", { trimempty = true })

    -- Remove the command name ("Vault") from parts
    if #parts > 0 and parts[1] == "Vault" then
        table.remove(parts, 1)
    end

    -- Get the subcommand tree from the commands module
    local ok, cmds = pcall(require, "vault.commands")
    if not ok or not cmds or not cmds._get_subcommands then
        return vim.tbl_keys(require("vault.api"))
    end
    local tree = cmds._get_subcommands()

    -- Walk the tree for all but the last token (which is the prefix being completed)
    local node = tree
    local prefix = ""
    local trailing_space = line:match("%s$")

    if trailing_space then
        -- Cursor is after a space — all parts are complete, prefix is empty
        for _, part in ipairs(parts) do
            local child = node[part]
            if child and type(child) == "table" then
                node = child
            else
                -- No deeper match — try node's own complete function
                if node.complete then
                    return node.complete(part)
                end
                return {}
            end
        end
        prefix = ""
    else
        -- Last token is the prefix being completed
        for i = 1, #parts - 1 do
            local child = node[parts[i]]
            if child and type(child) == "table" then
                node = child
            else
                if node.complete then
                    return node.complete(parts[i] or "")
                end
                return {}
            end
        end
        prefix = parts[#parts] or ""
    end

    -- If node has a `complete` function, defer to it
    if node.complete then
        return node.complete(prefix)
    end

    -- Otherwise, list child subcommand names matching prefix
    local results = {}
    for k, v in pairs(node) do
        if type(v) == "table" and k ~= "run" and k ~= "complete" then
            if k:find(prefix, 1, true) == 1 then
                table.insert(results, k)
            end
        end
    end
    table.sort(results)
    return results
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
    local fargs = vim.split(line, " ")
    local query = fargs[#fargs] or ""
    --- @type string[]
    local dir_keys = vim.tbl_keys(require("vault.dirs")().map)
    if query == "" then
        return dir_keys
    end
    local completions = {}
    local utils = require("vault.utils")
    for _, dir in ipairs(dir_keys) do
        if utils.match(dir, query, "fuzzy", false) then
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

--- Returns the list of available statuses (from frontmatter 'status' property)
function M.statuses(_, _, _)
    local ok, properties = pcall(function() return require("vault.scanner").properties() end)
    if not ok or not properties then
        return {}
    end
    local status_prop = properties.status
    if not status_prop then
        return {}
    end
    return vim.tbl_keys(status_prop.data.values or {})
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
