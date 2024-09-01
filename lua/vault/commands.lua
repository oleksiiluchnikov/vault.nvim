--- @class vault.commands

--- @class vault.completions.args
--- @field args string[]
--- @field bang boolean
--- @field count? integer
--- @field fargs string[]
--- @field line1 number
--- @field line2 number
--- @field mods vim.api.keyset.parse_cmd.mods
--- @field name string
--- @field range? integer[]|integer
--- @field reg? string
--- @field smods vim.api.keyset.parse_cmd.mods

--- @class vault.commands.complete
local complete = {}

--- Returns the list of notes slugs
--- @return vault.slug[]
function complete.note_slugs()
    --- @type vault.slug[]
    local notes_slugs = require("vault.core.state").get_global_key("cache.notes.slugs")
        or require("vault.fetcher").slugs()
    return vim.tbl_keys(notes_slugs)
end

--- Returns the list of note available data keys
--- @return string[]
function complete.note_data_keys()
    return vim.tbl_keys(require("vault.notes.note.data"))
end

--- @param cmd_line string
function complete.dirs(_, cmd_line, _)
    cmd_line = cmd_line or ""
    cmd_line = cmd_line:gsub("^%S+%s*", "")
    --- @type vault.slug[]
    local dirs = require("vault.fetcher").dirs()
    dirs = vim.tbl_keys(dirs)
    local completions = {}
    local utils = require("vault.utils")
    for _, dir in ipairs(dirs) do
        if utils.match(dir, cmd_line, "fuzzy", false) then
            table.insert(completions, dir)
        end
    end
    return completions
end

function complete.tags()
    -- tags = vim.tbl_keys(require("vault.fetcher").tags())
    -- return tags
    local tags = require("vault.tags")()
    local tag_names = {}
    for _, tag in pairs(tags.map) do
        table.insert(tag_names, tag.data.name)
    end
    return tag_names
end

--- Returns the list of values for the given key
--- @param arg string
--- @return table<string,any>
function complete.values_map_by_key(arg)
    return require("vault.notes")():values_map_by_key(arg)
end

--- Returns the list of match options
--- @return vault.enum.MatchOpts.key[]
function complete.match_opts()
    return vim.tbl_keys(require("vault.utils.enums").match_opts)
end

--- Returns the list of match types
--- @return vault.enum.MatchOpts.mode[]
function complete.match_types()
    return vim.tbl_keys(require("vault.utils.enums").filter_mode)
end

--- Returns the list of notes filters
--- @param cmd_line string
--- @return string[]
function complete.notes_filter(_, cmd_line, _)
    local args = vim.split(cmd_line, " ")
    table.remove(args, 1)
    if #args == 1 then
        return complete.vault_notes_presets()
    elseif #args == 2 then
        return complete.note_data_keys()
    elseif #args == 3 then
        return complete.values_map_by_key(args[2])
    elseif #args == 4 then
        return complete.values_map_by_key(args[2])
    elseif #args == 5 then
        return complete.match_opts()
    elseif #args == 6 then
        return complete.match_types()
    end
    return {}
end

--- Returns the list of tags for the current note
--- @param cmd_line string
--- @return string[]|nil
function complete.note_tags(_, cmd_line, _)
    local config = require("vault.config")
    local fargs = vim.split(cmd_line, " ")
    if next(fargs) == nil then
        return
    end
    local current_path = vim.fn.expand("%:p")
    if type(current_path) ~= "string" then
        return
    end

    local tags = {}

    if not current_path:match(config.options.ext .. "$") then
        return complete.tags()
    end

    local note = require("vault.notes.note")(vim.fn.expand("%:p"))
    tags = vim.tbl_keys(note.data.tags)
    return tags
end

--- Returns the list of vault notes presets
--- @return string[]
function complete.vault_notes_presets()
    return { "linked", "orphans", "leaves", "by" }
end

--- Returns the list of dates
--- @return string[]
function complete.dates()
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
--- @return string[]|nil
function complete.statuses()
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

--- @param cmd_line string
function complete.note(_, cmd_line, _)
    local fargs = vim.split(cmd_line, " ")
    --- @type vault.slug[]
    if #fargs == 1 then
        return
    elseif #fargs == 2 then
        return require("vault.notes.note"):methods()
    elseif #fargs == 3 then
        -- TODO: Decide what to return
        -- return args for the method?
        return complete.note_slugs()
    elseif #fargs > 3 then
        -- TODO: Decide what to return
    end
end

--- @class vault.commands.callback
local callbacks = {}

--- ```vim
--- :vaultNotes <preset> <filter> ...
--- :VaultNotes linked tags <include_tags> <exclude_tags> <match_opt> <match_type>
--- :VaultNotes orphans tags <include_tags> <exclude_tags> <match_opt> <match_type>
--- :VaultNotes tags <include_tags> <exclude_tags> <match_opt> <match_type>
--- ```

--- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- --
--- Create a new note with the given slug.
---
--- If no slug is provided, a fleeting note popup is shown.
--- If a note with the given slug already exists, it is opened for editing.
--- Otherwise, a new note is created with the given slug and opened for editing.
---
--- @param args vault.completions.args
--- @usage
--- ```lua
--- ```
function callbacks.create_new_note(args)
    local fargs = args.fargs
    if next(fargs) == nil then
        require("vault.popups.fleeting_note")()
    end

    local new_slug = fargs[1]
    local notes = require("vault.notes")():with_slug(new_slug, "exact", false)
    if notes:count() ~= 0 then
        notes.map[new_slug]:edit()
        return
    end
    local path = require("vault.utils").slug_to_path(new_slug)
    local note = require("vault.notes.note")(path)
    note:write(path)
    note:edit()
end

--- @param args vault.completions.args
function callbacks.pick_dirs(args)
    require("vault.pickers").dirs()
    if next(args.fargs) ~= nil then
        vim.api.nvim_buf_set_lines(0, 0, -1, false, args.fargs)
        vim.defer_fn(function()
            vim.fn.feedkeys("\r", "i")
        end, 1)
    end
end

---Edits a random note from the vault.
---@param args vault.completions.args
---@return nil
function callbacks.edit_random_note(args)
    ---@type vault.Notes
    local notes
    if #args.fargs == 0 then
        notes = require("vault.notes")()
    else
        notes = require("vault.notes")():with_slug(table.concat(args.fargs, " "), "fuzzy")
    end
    local random_note = notes:get_random_note()
    if random_note == nil then
        return
    end
    random_note:edit()
end

--- vault.Tags
--- @param args vault.completions.args
function callbacks.open_tags_picker(args)
    local fargs = args.fargs
    if next(fargs) == nil then
        require("vault.pickers").tags()
        return
    end

    local tags_names = fargs
    --- @type vault.Filter.option.tags
    local filter_opts = {
        search_term = "tags",
        include = tags_names,
        exclude = {},
        match_opt = "contains",
        mode = "all",
    }

    require("vault.pickers").notes({ notes = require("vault.notes")():filter(filter_opts) })
end

--- Vault Dates
--- Opens a picker with the dates
--- @param args vault.completions.args
--- @return nil
function callbacks.open_dates_picker(args)
    local fargs = args.fargs
    if next(fargs) == nil then
        require("vault.pickers").dates()
        return
    end
    --TODO: Add configuration to set the date format
    local today = os.date("%Y-%m-%d")
    local year_ago = os.date("%Y-%m-%d", os.time() - 60 * 60 * 24 * 365)
    -- require("vault.pickers").dates(tostring(today), tostring(year_ago))
    require("vault.pickers").dates({ start_date = tostring(today), end_date = tostring(year_ago) })
end

--- vault.Today
--- Opens the today's journal note
--- @return nil
function callbacks.today()
    --- @type vault.Config|vault.Config.options
    local config = require("vault.config")
    local today = os.date("%Y-%m-%d %A")
    if type(today) ~= "string" then
        return
    end
    -- local path = config.options.dirs.journal.daily .. today .. ".md"
    local daily_dir = config.options.dirs.journal.daily
    local path = string.format("%s/%s%s", daily_dir, today, config.options.ext)
    if vim.fn.filereadable(path) == 0 then
        vim.notify("Initializing today's journal note")
    end
    vim.cmd("e " .. path)
end

function callbacks.open_properties_picker(args)
    local fargs = args.fargs
    if next(fargs) == nil then
        require("vault.pickers").properties()
        return
    end
    local values = {}
    for _, value in ipairs(fargs) do
        table.insert(values, value)
    end
    require("vault.pickers").properties({ values = values })
end

--- @command :VaultYesterday {dates} [[
--- Opens a picker with the statuses
--- @command ]]
--- @param args vault.completions.args
--- @return nil
function callbacks.open_notes_status_picker(args)
    local fargs = args.fargs
    if next(fargs) == nil then
        -- require("vault.pickers").root_tags()
        callbacks.open_properties_picker(args)
        local bufnr = vim.api.nvim_get_current_buf()
        vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "status" })
        require("telescope.actions").select_default.enter(bufnr)
        return
    end
    --TODO: Moved statuse to the frontmatter. Need to update this
    local tags = require("vault.tags")()
    local statuses = {}
    for _, tag in pairs(tags.map) do
        for _, farg in ipairs(fargs) do
            if tag.data.name == farg then
                table.insert(statuses, tag.data.name)
            end
        end
    end
    local notes = require("vault.notes")():filter({ "tags", { statuses }, {}, "startswith", "all" })

    require("vault.pickers").notes({ notes = notes })
end

--- vault.FleetingNote
--- Opens a fleeting note
--- @param args vault.completions.args
--- @return nil
function callbacks.open_fleeting_note_popup(args)
    local FleetingNote = require("vault.popups.fleeting_note")
    if next(args.fargs) == nil then
        FleetingNote()
        return
    elseif #args.fargs == 1 then
    end
    -- FleetingNote(args.fargs, {})
end

--- vault.Orphans
--- Opens a picker with orphans
--- @return nil
function callbacks.open_orphans_picker()
    require("vault.pickers").notes({ notes = require("vault.notes")():orphans() })
end

--- vault.Linked
--- Opens a picker with linked notes
--- @return nil
function callbacks.open_linked_picker()
    require("vault.pickers").notes({ notes = require("vault.notes")():linked() })
end

--- Opens a live grep picker with fuzzy search
--- @param args vault.completions.args
--- @return nil
function callbacks.open_live_grep_picker(args)
    --TODO: Implement
    error("Not implemented")
    if args.range == 0 then
        require("vault.pickers").live_grep({ query = "" })
        return
    end
    local query = table.concat(args.fargs, " ")
    require("vault.pickers").live_grep({ query = query })
end

--- vault.Yesterday
--- Opens the yesterday's journal note
--- @return nil
function callbacks.yesterday()
    local config = require("vault.config")
    local yesterday = os.date("%Y-%m-%d", os.time() - 60 * 60 * 24)
    local daily_dir = config.options.dirs.journal.daily
    local path = string.format("%s/%s%s", daily_dir, yesterday, config.options.ext)
    if vim.fn.filereadable(path) == 0 then
        vim.notify("Initializing yesterday's journal note")
    end
    vim.cmd("e " .. path)
end

--- vault.NoteRename
--- Rename a note title and update all the links to that note
--- ```vim
--- :VaultNoteRename <new_title>
--- ```
---
--- ```lua
--- require("vault.notes.note")(vim.fn.expand("%:p")):rename(new_path)
--- ```
--- @param args vault.completions.args
--- @return nil
function callbacks.rename(args)
    local note = require("vault.notes.note")(vim.fn.expand("%:p"))
    if next(args.fargs) == nil then
        vim.notify("Not renamed")
        return
    end
    local new_slug = table.concat(args.fargs, " ")
    if new_slug == "" then
        return
    end
    local new_path = require("vault.utils").slug_to_path(new_slug)
    note:move(new_path)
    vim.cmd("bdelete!")
    note:edit()
end

--- vault.NoteInlinks
--- Opens a picker with the notes where current note is mentioned
--- ```vim
--- :VaultNoteInlinks
--- ```
---
--- ```lua
--- pickers.notes({}, nil, inlinks)
--- ```
--- @return nil
function callbacks.note_inlinks_picker()
    local note = require("vault.notes.note")(vim.fn.expand("%:p"))
    local inlinks = note.data.inlinks or {}
    if next(inlinks) == nil then
        return
    end
    local notes = require("vault.notes")():with_slugs(vim.tbl_keys(inlinks))
    require("vault.pickers").notes({ notes = notes })
end

--- vault.NoteOutlinks
--- Opens a picker with the notes that current note links to
--- ```vim
--- :VaultNoteOutlinks
--- ```
---
--- ```lua
--- pickers.notes({ notes = require('vault.notes')():with_slugs(vim.tbl_keys(outlinks)) })
--- ```
--- @return nil
function callbacks.note_outlinks_picker()
    local note = require("vault.notes.note")(vim.fn.expand("%:p"))
    local outlinks = note.data.outlinks or {}
    if next(outlinks) == nil then
        vim.notify("No outlinks")
        return
    end
    -- pickers.notes({}, nil, outlinks)
    local slugs = {}
    for _, outlink in pairs(outlinks) do
        table.insert(slugs, outlink.data.slug)
    end

    require("vault.pickers").notes({ notes = require("vault.notes")():with_slugs(slugs) })
end

--- vault.NoteTags
--- Opens a picker with the notes that have the tags
--- ```vim
--- :VaultNoteTags <range>
--- ```
---
--- ```lua
--- ```
--- @param args vault.completions.args
function callbacks.note_tags_picker(args)
    local note = require("vault.notes.note")(vim.fn.expand("%:p"))
    if next(note.data.tags) == nil then
        vim.notify("No tags")
        return
    end

    --- @type vault.slug[]
    local slugs = {}

    if next(args.fargs) == nil then
        for _, tag in pairs(note.data.tags) do
            -- table.insert(slugs, vim.tbl_keys(tag.data.sources))
            for slug, _ in pairs(tag.data.sources) do
                table.insert(slugs, slug)
            end
        end
    elseif args.fargs[1] then
        for _, tag in pairs(note.data.tags) do
            if tag.data.name == args.fargs[1] then
                for slug, _ in pairs(tag.data.sources) do
                    table.insert(slugs, slug)
                end
            end
        end
    end
    -- -- if range is provided, then get the tags from the range
    -- if args.range == 0 then
    -- end
    -- if args.range == 2 then
    --     error("Not implemented")
    -- end
    require("vault.pickers").notes({ notes = require("vault.notes")():with_slugs(slugs) })
end

--- Create a new note from the selected text, and replace the selected text with a link to the new note
--- @param args vault.completions.args
function callbacks.note_from_selected_text(args)
    -- --- @type vault.Note
    -- local current_note = require("vault.notes.note")(vim.fn.expand("%:p"))
    --- @type string[]
    local lines = vim.api.nvim_buf_get_lines(0, args.line1 - 1, args.line2, false)
    if next(lines) == nil then
        vim.notify("Invalid text")
        return
    end

    --- @type string
    local new_note_slug = vim.fn.input("New note slug: ")
    if not new_note_slug or new_note_slug == "" then
        vim.notify("Invalid slug")
        return
    end

    --- @type number
    local uuid = require("vault.utils").generate_uuid()
    new_note_slug = uuid .. " " .. new_note_slug

    --- @type vault.path
    local new_note_path = require("vault.utils").slug_to_path(new_note_slug)
    if vim.fn.filereadable(new_note_path) == 1 then
        vim.notify("File already exists: " .. new_note_path)
        return
    end

    --- @type vault.Wikilink.Data.raw
    local link = "[[" .. new_note_slug .. "]]"
    --TODO: Implement possibilit to add the link inside the line
    vim.api.nvim_buf_set_lines(0, args.line1 - 1, args.line2, false, { link })

    local new_note_content = table.concat(lines, "\n")
    local new_note = require("vault.notes.note")(new_note_path)
    new_note.data.content = new_note_content
    new_note:write()
    -- renew the note to update marksman cache
    if vim.fn.executable("marksman") == 1 then
        vim.cmd("LspRestart marksman")
    end
end

--- vault.NoteProperties
--- Opens a picker with the properties of the note
--- ```vim
--- :VaultNoteProperties
--- :VaultNoteProperties <property_name>
--- :VaultNoteProperties <property_name> <property_name>
--- ```
--- @param args vault.completions.args
--- @return nil
function callbacks.open_note_properties_picker(args)
    local fargs = args.fargs
    if next(fargs) == nil then
        require("vault.pickers").properties()
        return
    end
    local values = {}
    for _, value in ipairs(fargs) do
        table.insert(values, value)
    end
    require("vault.pickers").properties({ values = values })
end

--- VaultNoteByDir
--- Opens a picker with notes by directory
--- @param args vault.completions.args
function callbacks.open_note_by_dir_picker(args)
    local fargs = args.fargs
    if next(fargs) == nil then
        -- return notes in the root directory
        require("vault.pickers").notes({
            notes = require("vault.notes")():with_relpath("", "exact", false),
        })
        return
    end
    local notes = require("vault.notes")():with_relpath(fargs[1], "startswith", false)
    require("vault.pickers").notes({ notes = notes })
end

--- @param args vault.completions.args
function callbacks.note(args)
    local fargs = args.fargs
    -- if no arguments, then open a picker
    if next(fargs) == nil then
        require("vault.api").open_notes_picker()
        return
    elseif #fargs == 1 then
        --TODO: Implement choose a note from a picker
        -- apply the method to the note that is "%"
        local note = require("vault.notes.note")(vim.fn.expand("%:p"))
        if note == nil then
            vim.notify("No note found")
            return
        end
        table.insert(fargs, 1, note)
        return
    end
    local method = fargs[1]
    local slug = fargs[2]
    local arguments = {}
    for i = 3, #fargs do
        table.insert(arguments, fargs[i])
    end
    local note = require("vault.notes")().map[slug]
    table.insert(arguments, 1, note)
    -- Apply the method to the note
    local output = note[method](unpack(arguments))
    if output then
        --- @class notify.Options
        local notify_opts = {
            timeout = 1000,
            title = note.data.stem,
        }
        vim.notify(output, vim.log.levels.INFO, notify_opts)
    end
end

local function construct_notes_picker_args(input)
    local args = {}

    -- Check if the first argument is a valid preset
    -- if no preset is provided, use filter directly
    if vim.tbl_contains(complete.vault_notes_presets(), input[1]) then
        args[1] = input[1]
    end
    vim.notify(vim.inspect(args))

    -- Check if the second argument is a valid key
    if vim.tbl_contains(complete.note_data_keys(), input[2]) then
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
            require("vault.pickers").notes({ notes = require("vault.notes")()[args[1]] })
        elseif args[1] == "by" then
            vim.notify("Need further arguments")
        end
    elseif #args == 2 then
        return
    elseif #args == 3 then
        if type(args[3]) ~= "table" then
            args[3] = { args[3] }
        end
        require("vault.pickers").notes({
            notes = require("vault.notes")({ args[2], args[3], {}, "startswith", "all" }),
        })
    elseif #args == 4 then
        if type(args[3]) ~= "table" then
            args[3] = { args[3] }
        end
        if type(args[4]) ~= "table" then
            args[4] = { args[4] }
        end
        require("vault.pickers").notes({
            notes = require("vault.notes")({ args[2], args[3], args[4], "startswith", "all" }),
        })
    elseif #args == 5 then
        if type(args[3]) ~= "table" then
            args[3] = { args[3] }
        end
        if type(args[4]) ~= "table" then
            args[4] = { args[4] }
        end
        require("vault.pickers").notes({
            notes = require("vault.notes")({ args[2], args[3], args[4], args[5], "all" }),
        })
    elseif #args == 6 then
        if type(args[3]) ~= "table" then
            args[3] = { args[3] }
        end
        if type(args[4]) ~= "table" then
            args[4] = { args[4] }
        end
        require("vault.pickers").notes({
            notes = require("vault.notes")({ args[2], args[3], args[4], args[5], args[6] }),
        })
    end
end

function callbacks.notes(args)
    if next(args.fargs) == nil then
        require("vault.pickers").notes()
        return
    elseif #args.fargs == 1 then
        construct_notes_picker_args(args.fargs)
    end
end

function callbacks.tasks()
    -- TODO: Implement to complete by status
    require("vault.pickers").tasks()
end

-- Commands for the plugin
local M = {
    ["VaultNote"] = {
        --- @command :VaultNote {method} {slug} {arguments} [[
        --- Open a note in the vault
        --- ```vim
        --- :VaultNote <method> <slug> <arguments>
        --- :VaultNote linked tags <include_tags> <exclude_tags> <match_opt> <match_type>
        --- ```
        --- @command ]]
        callback = callbacks.note,
        opts = {
            desc = "Open a note in the vault",
            complete = complete.note,
            nargs = "*",
        },
    },
    ["VaultRandomNote"] = {
        --- @command :VaultRandomNote {slug} [[
        --- Open a random note
        --- @command ]]
        callback = callbacks.edit_random_note,
        opts = {
            desc = "Open a random note",
            complete = complete.note_slugs,
            nargs = "*",
        },
    },
    ["VaultNotes"] = {
        --- Generates a picker with certain collection of notes
        callback = callbacks.notes,
        opts = {
            desc = "Open a picker with a collection of notes",
            complete = complete.notes_filter,
            nargs = "*",
        },
    },
    ["VaultTags"] = {
        --- @command :VaultTags {tags} [[
        --- Open a picker with the notes that have the tags
        --- @command ]]
        callback = callbacks.open_tags_picker,
        opts = {
            desc = "Open a picker with the notes that have the tags",
            complete = complete.tags,
            nargs = "*",
        },
    },
    ["VaultDates"] = {
        --- @command :VaultDates {dates} [[
        --- Open a picker with the dates
        --- @command ]]
        callback = callbacks.open_dates_picker,
        opts = {
            desc = "Open a picker with the dates",
            complete = complete.dates,
            nargs = "*",
        },
    },
    ["VaultToday"] = {
        --- @command :VaultToday [[
        --- Opens the today's journal note
        --- @command ]]
        callback = callbacks.today,
        opts = {
            desc = "Opens the today's journal note",
            nargs = 0,
        },
    },
    ["VaultNotesStatus"] = {
        --- @command :VaultNotesStatus {statuses} [[
        --- Opens a picker with the statuses
        --- @command ]]
        callback = callbacks.open_notes_status_picker,
        opts = {
            desc = "Open a picker with the statuses",
            complete = complete.statuses,
            nargs = "*",
        },
    },
    ["VaultFleetingNote"] = {
        --- @command :VaultFleetingNote [[
        --- Opens a popup to create fleeting note
        --- @command ]]
        callback = callbacks.open_fleeting_note_popup,
        opts = {
            desc = "Open a popup to create a fleeting note",
            nargs = "*",
        },
    },
    ["VaultOrphans"] = {
        --- @command :VaultOrphans [[
        --- Opens a popup to pick
        --- @command ]]
        callback = callbacks.open_orphans_picker,
        opts = {
            desc = "Open a picker with the orphans",
            nargs = 0,
        },
    },
    ["VaultLinked"] = {
        --- @command :VaultLinked [[
        --- Opens a popup to pick
        --- @command ]]
        callback = callbacks.open_linked_picker,
        opts = {
            desc = "Open a picker with the linked notes",
            nargs = 0,
        },
    },
    ["VaultInternals"] = {
        --- @command :VaultInternals [[
        callback = function()
            require("vault.pickers").notes({ notes = require("vault.notes")():internals() })
        end,
        opts = {
            desc = "Open a picker with the internals",
            complete = complete.notes_filter,
            nargs = "*",
        },
    },
    ["VaultLeaves"] = {
        callback = function()
            require("vault.pickers").notes({ notes = require("vault.notes")():leaves() })
        end,
        opts = {
            desc = "Open a picker with the leaves",
            complete = complete.notes_filter,
            nargs = "*",
        },
    },
    ["VaultDanglingLinks"] = {
        callback = function()
            require("vault.pickers").notes({
                notes = require("vault.notes")():with_outlinks_unresolved(),
            })
        end,
        opts = {
            desc = "Open a picker with the dangling links",
            complete = complete.notes_filter,
            nargs = "*",
        },
    },
    ["VaultOutlinksUnresolved"] = {
        callback = function()
            require("vault.pickers").notes({
                notes = require("vault.notes")():with_outlinks_unresolved(),
            })
        end,
        opts = {
            desc = "Open a picker with the outlinks unresolved",
            complete = complete.notes_filter,
            nargs = "*",
        },
    },
    ["VaultOutlinksResolvedOnly"] = {
        callback = function()
            require("vault.pickers").notes({
                notes = require("vault.notes")():with_outlinks_resolved_only(),
            })
        end,
        opts = {
            desc = "Open a picker with the outlinks resolved only",
            complete = complete.notes_filter,
            nargs = "*",
        },
    },
    ["VaultWikilinks"] = {
        callback = function()
            require("vault.pickers").wikilinks()
        end,
        opts = {
            desc = "Open a picker with the wikilinks",
            complete = complete.note_slugs,
            nargs = "*",
        },
    },
    ["VaultTasks"] = {
        callback = callbacks.tasks,
        opts = {
            desc = "Open a picker with the tasks accross the vault",
            complete = complete.statuses,
            nargs = "*",
        },
    },
    ["VaultNotesCluster"] = {
        callback = function(args)
            local input = args.args

            if input == "" or input == nil then
                local path = vim.fn.expand("%")
                if type(path) == "table" then
                    path = path[1]
                end
                local relpath = require("vault.utils").path_to_slug(path)
                input = relpath
                vim.notify(input)
            end

            local note_slug = input
            local notes = require("vault.notes")()
            local note = vim.deepcopy(notes):with_slug(note_slug, "exact"):list()[1]
            if not note then
                vim.notify("Note not found " .. note_slug)
                return
            end
            local cluster = notes:to_cluster(note, 0)
            require("vault.pickers").notes({ notes = cluster })
        end,
        opts = {
            desc = "Open a picker with the notes that are in the same cluster",
            complete = complete.note_slugs,
            nargs = "*",
        },
    },
    ["VaultMove"] = {
        --- Command to move a note to a new location.
        --- If oargs then open picker
        --- if arg, and it is a valid relpath, then move to that location
        callback = function()
            print("use vault.Rename instead")

            -- local input = args.fargs[1]
            -- local current_path = vim.fn.expand("%:p")
            -- if type(current_path) ~= "string" then
            --     return
            -- end
            -- if not current_path:match(config.options.root) then
            --     vim.notify("Not a vault note")
            --     return
            -- elseif not current_path:match(config.options.ext .. "$") then
            --     vim.notify("Not a vault note")
            --     return
            -- elseif not vim.fn.filereadable(current_path) then
            --     vim.notify("Not a vault note")
            --     return
            -- elseif not vim.fn.isdirectory(current_path) then
            --     vim.notify("Not a vault note")
            --     return
            -- end
            --
            -- local note = require("vault.notes.note")(current_path)
            --
            -- if input == nil or input == "" then
            --     pickers.move_note_to(note)
            --     return
            -- end
            -- if input:match("^.$") then
            --     input = config.options.root
            -- else
            --     input = config.options.root .. "/" .. input
            -- end
            --
            -- local new_path = string.format("%s/%s", input, note.data.basename)
            -- if vim.fn.filereadable(new_path) == 1 then
            --     vim.notify("File already exists")
            --     return
            -- elseif note.data.path == new_path then
            --     vim.notify("Already in that location")
            --     return
            -- end
            --
            -- local clients = vim.lsp.get_clients({ bufnr = vim.fn.bufnr() })
            -- note:rename(new_path)
            -- for _, client in ipairs(clients) do
            --     -- restart the lsp client
            --     vim.lsp.stop_client(client.id)
            --     vim.lsp.start_client(client.config)
            -- end

            -- vim.cmd("LspRestart") Simulate that command
        end,
        opts = {
            nargs = "*",
            complete = complete.dirs,
        },
    },
    ["VaultGrep"] = {
        callback = callbacks.open_live_grep_picker,
        opts = {
            nargs = "*",
            range = true,
        },
    },
    ["VaultYesterday"] = {
        callback = callbacks.yesterday,
        opts = {
            nargs = 0,
        },
    },
    ["VaultRename"] = {
        callback = callbacks.rename,
        opts = {
            nargs = "*",
        },
    },
    ["VaultNoteInlinks"] = {
        callback = callbacks.note_inlinks_picker,
        opts = {
            nargs = 0,
        },
    },
    ["VaultNoteOutlinks"] = {
        callback = callbacks.note_outlinks_picker,
        opts = {
            nargs = 0,
        },
    },
    ["VaultNoteTags"] = {
        callback = callbacks.note_tags_picker,
        opts = {
            nargs = "*",
            range = true,
            complete = complete.note_tags,
            desc = "Open a picker with the notes that have the tags and the note",
        },
    },
    ["VaultNoteExtract"] = {
        callback = callbacks.note_from_selected_text,
        opts = {
            nargs = "*",
            range = true,
            complete = complete.note_slugs,
        },
    },
    ["VaultProperties"] = {
        --- vault.Properties
        --- Opens a picker with the properties
        --- ```vim
        --- :VaultProperties
        --- :VaultProperties <property_name>
        --- :VaultProperties <property_name> <property_name>
        --- ```
        --- @param args vault.completions.args
        --- @return nil
        callback = function(args)
            local fargs = args.fargs
            if next(fargs) == nil then
                require("vault.pickers").properties()
                return
            end
            local values = {}
            for _, value in ipairs(fargs) do
                table.insert(values, value)
            end
            require("vault.pickers").properties({ values = values })
        end,
        opts = {
            nargs = "*",
            complete = function(_, cmd_line, _)
                local arguments = vim.split(cmd_line, " ")
                if next(arguments) == nil then
                    return
                end
                --- @type vault.Property.Data.name[]
                local properties = vim.tbl_keys(require("vault.fetcher").properties())
                return properties
            end,
            desc = "Open a picker of properties to browse",
        },
    },
    ["VaultNoteProperties"] = {
        callback = callbacks.open_note_properties_picker,
        opts = {
            nargs = "*",
            complete = function(_, cmd_line, _)
                local arguments = vim.split(cmd_line, " ")
                if next(arguments) == nil then
                    return
                end
                --- @type vault.Property.Data.name[]
                local properties = {}
                local config = require("vault.config")
                if not vim.fn.expand("%:p"):match(config.options.ext .. "$") then
                    properties = vim.tbl_keys(require("vault.fetcher").properties())
                    return properties
                end
                properties = vim.tbl_keys(
                    require("vault.notes.note")(vim.fn.expand("%:p")).data.frontmatter.data
                )
                return properties
            end,
            desc = "Open a picker of properties to browse",
        },
    },
    ["VaultNotesByDir"] = {
        callback = callbacks.open_note_by_dir_picker,
        opts = {
            nargs = "*",
            complete = function(_, cmd_line, _)
                local arguments = vim.split(cmd_line, " ")
                if next(arguments) == nil then
                    return
                end
                local paths = vim.tbl_keys(require("vault.fetcher").dirs())
                return paths
            end,
            desc = "Open a picker with notes by directory",
        },
    },
    ["VaultNoteNew"] = {
        callback = callbacks.create_new_note,
        opts = {
            nargs = "*",
            complete = function(_, cmd_line, _)
                local arguments = vim.split(cmd_line, " ")
                if arguments[2] == nil then
                    return
                end
                local paths = vim.tbl_keys(require("vault.fetcher").dirs())
                local suggest = false
                for _, path in pairs(paths) do
                    if
                        require("vault.utils").match(path, arguments[2], "startswith", false)
                        == false
                    then
                        suggest = false
                    else
                        suggest = true
                    end
                end
                if suggest == true then
                    return paths
                end
            end,
            desc = "Open a picker with notes by directory",
        },
    },
    ["VaultDirs"] = {
        callback = callbacks.pick_dirs,
        opts = {
            desc = "Open a picker with the directories in the vault",
            complete = complete.dirs,
            nargs = "*",
        },
    },
}

for command, opts in pairs(M) do
    local assign, err = pcall(vim.api.nvim_create_user_command, command, opts.callback, opts.opts)
    if not assign then
        error(string.format("`:%s` failed to create, error: %s", command, err))
    end
end

return callbacks
