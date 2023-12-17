local state = require("vault.core.state")

--- VaultNote <method> <target(key)> <arg1> <arg2> ...
---```vim
---:VaultNote open <autocomplete basename>
local function get_methods(object)
    local methods = {}
    for k, v in pairs(getmetatable(object)) do
        if type(v) == "function" then
            local ignore_patterns = {
                "^__",
                "init",
            }
            local ignore = false
            -- table.insert(VaultNotesMethods, k)
            for _, pattern in ipairs(ignore_patterns) do
                if k:match(pattern) then
                    ignore = true
                end
            end
            if not ignore then
                table.insert(methods, k)
            end
        end
    end
    return methods
end

local function get_arguments(method)
    local arguments = {}
    local info = debug.getinfo(method)
    local source = info.source:sub(2) -- Remove the @ from the beginning
    local source_lines = vim.fn.readfile(source)
    local method_line = source_lines[info.linedefined]
    local method_arguments = method_line:match("%((.*)%)")
    method_arguments = vim.split(method_arguments, ",")
    for _, argument in ipairs(method_arguments) do
        argument = vim.trim(argument)
        if not argument:match("self") and argument ~= "" then
            table.insert(arguments, argument)
        end
    end
    return arguments
end

local function get_keys(object)
    local keys = {}
    for k, _ in pairs(object) do
        table.insert(keys, k)
    end
    return keys
end

--- VaultNote
vim.api.nvim_create_user_command("VaultNote", function(args)
    local input = args.fargs
    if vim.tbl_contains(note_available_methods, input[1]) then
        local method = input[1]
        local target = input[2]
        local selected_note = require("vault.notes")():by("basename", target, "exact")[1]
        selected_note[method](selected_note)
        return
    end
end, {
    nargs = "*",
    complete = function(_, cmd_line, _)
        local arguments = vim.split(cmd_line, " ")
        if #arguments == 2 then
            return note_available_methods
        elseif #arguments == 3 then
            return require("vault.notes")():get_values_by_key("basename")
        elseif #arguments == 4 then
            return
        end
    end,
})

--- VaultNoteRandom
--- Same as VaultNote but with a random note
vim.api.nvim_create_user_command("VaultNoteRandom", function(args)
    local input = args.fargs
    if vim.tbl_contains(note_available_methods, input[1]) then
        local method = input[1]
        local selected_note = require("vault.notes")():get_random_note()
        selected_note[method](selected_note)
        return
    end
end, {
    nargs = "*",
    complete = function(_, cmd_line, _)
        local arguments = vim.split(cmd_line, " ")
        table.remove(arguments, 1)
        if #arguments == 1 then
            return note_available_methods
        end
    end,
})

---```vim
---:vaultNotes <preset> <filter> ...
---:VaultNotes linked tags <include_tags> <exclude_tags> <match_opt> <match_type>
---:VaultNotes orphans tags <include_tags> <exclude_tags> <match_opt> <match_type>
---:VaultNotes tags <include_tags> <exclude_tags> <match_opt> <match_type>

local vault_notes_keys_by = {
    "tags",
    "title",
    "basename",
    "path",
    "type",
    "status",
    "date",
    "children",
}

local vault_notes_presets = {
    "linked",
    "orphans",
    "leaves",
    "by",
}

local function construct_notes_picker_args(input)
    local args = {}

    -- Check if the first argument is a valid preset
    -- if no preset is provided, use filter directly
    if vim.tbl_contains(vault_notes_presets, input[1]) then
        args[1] = input[1]
    end
    vim.notify(vim.inspect(args))

    -- Check if the second argument is a valid key
    if vim.tbl_contains(vault_notes_keys_by, input[2]) then
        input[2] = input[2] or error("Invalid key: " .. input[2])
        args[2] = input[2] -- key - key to filter by (tags, title, basename, path, type, status, date, children)
        args[3] = input[3] -- include - table of values to include
        args[4] = input[4] -- exclude - table of values to exclude
        args[5] = input[5] -- match_opt - exact, contains, startswith
        args[6] = input[6] -- match_type - any, all

        args = { input[2], input[3], input[4], input[5], input[6] }
    end
    if #args == 0 then
        args = input
        require("vault.pickers").notes()
    elseif #args == 1 then
        if args[1] ~= "by" then
            require("vault.pickers").notes(nil, nil, require("vault.notes")()[args[1]])
        elseif args[1] == "by" then
            vim.notify("Need further arguments")
        end
    elseif #args == 2 then
        return
    elseif #args == 3 then
        if type(args[3]) ~= "table" then
            args[3] = { args[3] }
        end
        require("vault.pickers").notes(
            nil,
            nil,
            require("vault.notes")({ args[2], args[3], {}, "startswith", "all" })
        )
    elseif #args == 4 then
        if type(args[3]) ~= "table" then
            args[3] = { args[3] }
        end
        if type(args[4]) ~= "table" then
            args[4] = { args[4] }
        end
        require("vault.pickers").notes(
            nil,
            nil,
            require("vault.notes")({ args[2], args[3], args[4], "startswith", "all" })
        )
    elseif #args == 5 then
        if type(args[3]) ~= "table" then
            args[3] = { args[3] }
        end
        if type(args[4]) ~= "table" then
            args[4] = { args[4] }
        end
        require("vault.pickers").notes(
            nil,
            nil,
            require("vault.notes")({ args[2], args[3], args[4], args[5], "all" })
        )
    elseif #args == 6 then
        if type(args[3]) ~= "table" then
            args[3] = { args[3] }
        end
        if type(args[4]) ~= "table" then
            args[4] = { args[4] }
        end
        require("vault.pickers").notes(
            nil,
            nil,
            require("vault.notes")({ args[2], args[3], args[4], args[5], args[6] })
        )
    end
end

--- VaultNotes
--- Generates a picker with certain collection of notes
vim.api.nvim_create_user_command("VaultNotes", function(args)
    local input = args.fargs
    if #input == 0 then
        require("vault.pickers").notes()
        return
    elseif #input == 1 then
        if input[1] == "linked" then
            require("vault.pickers").notes(nil, nil, require("vault.notes")():linked())
        elseif input[1] == "orphans" then
            require("vault.pickers").notes(nil, nil, require("vault.notes")():orphans())
        elseif input[1] == "leaves" then
            require("vault.pickers").notes(nil, nil, require("vault.notes")():leaves())
        end
    elseif #input > 1 then
        construct_notes_picker_args(input)
    end
end, {
    nargs = "*",
    complete = function(_, cmd_line, _)
        local arguments = vim.split(cmd_line, " ")
        table.remove(arguments, 1)
        if #arguments == 1 then
            return vault_notes_presets
        elseif #arguments == 2 then
            return vault_notes_keys_by
        elseif #arguments == 3 then
            return require("vault.notes")():get_values_by_key(arguments[2])
        elseif #arguments == 4 then
            return require("vault.notes")():get_values_by_key(arguments[2])
        elseif #arguments == 5 then
            return { "exact", "contains", "startswith", "endswith", "regex", "fuzzy" }
        elseif #arguments == 6 then
            return { "any", "all" }
        end
    end,
})

--TODO: Implement
vim.api.nvim_create_user_command("VaultTags", function(args)
    local fargs = args.fargs
    if next(fargs) == nil then
        require("vault.pickers").tags()
        return
    end
    local tags = require("vault.tags")()
    local tags_names = {}
    for _, tag in pairs(tags.map) do
        for _, farg in ipairs(fargs) do
            if tag.data.name:match(farg) then
                table.insert(tags_names, tag.data.name)
            end
        end
    end

    --FIXME: Now it is not working. It is not filtering the tags
    require("vault.pickers").notes({}, { "tags", {}, tags_names, "exact", "any" })
end, {
    nargs = "*",
    complete = function()
        local tags = require("vault.tags")()
        local tag_names = {}
        for _, tag in pairs(tags.map) do
            table.insert(tag_names, tag.data.name)
        end
        return tag_names
    end,
})

--- Vault Dates
vim.api.nvim_create_user_command("VaultDates", function(args)
    local fargs = args.fargs
    if #fargs == 0 then
        require("vault.pickers").dates()
        return
    end
    local today = os.date("%Y-%m-%d")
    local year_ago = os.date("%Y-%m-%d", os.time() - 60 * 60 * 24 * 365)
    require("vault.pickers").dates(tostring(today), tostring(year_ago))
end, {
    nargs = "*",
    complete = function()
        local dates = require("dates").from_to(
            os.date("%Y-%m-%d"),
            os.date("%Y-%m-%d", os.time() - 60 * 60 * 24 * 365)
        )
        local date_values = {}
        for _, date in ipairs(dates) do
            table.insert(date_values, date.value)
        end
        return date_values
    end,
})

--- Vault Today
vim.api.nvim_create_user_command("VaultToday", function()
    local config = require("vault.config")
    local today = os.date("%Y-%m-%d %A")
    local path = config.dirs.journal.daily .. today .. ".md"
    vim.cmd("e " .. path)
end, {
    nargs = 0,
})

vim.api.nvim_create_user_command("VaultNotesStatus", function(args)
    local fargs = args.fargs
    if #fargs == 0 then
        require("vault.pickers").root_tags()
        return
    end
    local tags = require("vault.tags")()
    local statuses = {}
    for _, tag in pairs(tags.map) do
        for _, farg in ipairs(fargs) do
            if tag.data.name == farg then
                table.insert(statuses, tag.data.name)
            end
        end
    end
    require("vault.pickers").notes({}, { "tags", { statuses }, {}, "startswith", "all" })
end, {
    nargs = "*",
    complete = function()
        local tags = require("vault.tags")()
        local statuses = {}
        for _, tag in pairs(tags.map) do
            if tag.data.name:match("^status") and #tag.data.children > 0 then
                local status = tag.data.children[1]
                table.insert(statuses, status.value)
            end
        end
        return statuses
    end,
})

vim.api.nvim_create_user_command("VaultFleetingNote", function(args)
    local VaultPopupFleetingNote = require("vault.popups.fleeting_note")
    VaultPopupFleetingNote(args.fargs, {})
end, {
    nargs = "*",
})

-- require("vault.pickers").notes({},nil, require("vault.notes")({'tags', 'type', {}, "contains"}).orphans)
vim.api.nvim_create_user_command("VaultOrphans", function()
    require("vault.pickers").notes({}, nil, require("vault.notes")():orphans())
end, {
    nargs = 0,
})

vim.api.nvim_create_user_command("VaultLinked", function()
    require("vault.pickers").notes({}, nil, require("vault.notes")():linked())
end, {
    nargs = 0,
})

vim.api.nvim_create_user_command("VaultInternals", function()
    require("vault.pickers").notes({}, nil, require("vault.notes")():internals())
end, {
    nargs = 0,
})

vim.api.nvim_create_user_command("VaultLeaves", function()
    require("vault.pickers").notes({}, nil, require("vault.notes")():leaves())
end, {
    nargs = 0,
})

vim.api.nvim_create_user_command("VaultDanglingLinks", function()
    require("vault.pickers").notes({}, nil, require("vault.notes")():with_outlinks_unresolved())
end, {
    nargs = 0,
})

vim.api.nvim_create_user_command("VaultOutlinksUnresolved", function()
    require("vault.pickers").notes({}, nil, require("vault.notes")():with_outlinks_unresolved())
end, {
    nargs = 0,
})

vim.api.nvim_create_user_command("VaultOutlinksResolvedOnly", function()
    require("vault.pickers").notes({}, nil, require("vault.notes")():with_outlinks_resolved_only())
end, {
    nargs = 0,
})

vim.api.nvim_create_user_command("VaultWikilinks", function()
    require("vault.pickers").wikilinks()
end, {
    nargs = "*",
    complete = function(_, cmd_line, _)
        local arguments = vim.split(cmd_line, " ")
        table.remove(arguments, 1)

        local groups = {
            "outlinks",
            "resolved",
            "unresolved",
        }

        if #arguments == 1 then
            return groups
        end
    end,
})

vim.api.nvim_create_user_command("VaultTasks", function()
    require("vault.pickers").tasks()
end, {
    nargs = 0,
})

vim.api.nvim_create_user_command("VaultNotesCluster", function(args)
    local input = args.args
    if input == "" or input == nil then
        local path = vim.fn.expand("%")
        if type(path) == "table" then
            path = path[1]
        end
        local utils = require("vault.utils")
        local relpath = utils.path_to_slug(path)
        input = relpath
        vim.notify(input)
    end

    local note_stem = input
    local Notes = require("vault.notes")
    local notes = Notes()
    local note = vim.deepcopy(notes):with_slug(note_stem, "exact"):list()[1]
    if not note then
        vim.notify("Note not found " .. note_stem)
        return
    end
    -- print(vim.inspect(notes))
    local cluster = notes:to_cluster(note, 0)
    require("vault.pickers").notes({}, nil, cluster)
end, {
    nargs = "*",
    complete = function(_, cmd_line, _)
        -- vim.notify(cmd_line)
        -- local arguments = vim.split(cmd_line, " ")
        ---@type VaultNotes
        local notes = state.get_global_key("notes") or require("vault.notes")()
        notes = notes:reset()
        notes = notes:linked()
        ---@type VaultMap.slugs
        local notes_slugs = state.get_global_key("notes_slugs")
            or vim.tbl_keys(notes:value_map_with_key("slug"))
        return notes_slugs
    end,
})
