local completions = require("vault.commands.completions")
--- @class vault.commands.callback
local callbacks = {}

function callbacks.toggle_link()
    local winid = vim.api.nvim_get_current_win()
    local cursor_pos = vim.api.nvim_win_get_cursor(winid)
    local line = vim.api.nvim_get_current_line()
    local col = cursor_pos[2] + 1 -- Convert 0-based index to 1-based

    -- Lua patterns (NOT Vim regex — string.find() only supports Lua patterns)
    local url_pattern = "(https?://[%w%-%.]+[%w%-]+[%w]/?[%w%-%._~:/?#%[%]@!%$&'%(%)%*%+,;=]*)"
    local md_link_pattern = "%[([^%]]*)%]%(([^%)]+)%)"

    local function update_line(new_content)
        vim.api.nvim_buf_set_lines(0, cursor_pos[1] - 1, cursor_pos[1], false, { new_content })
        -- Restore cursor position
        vim.api.nvim_win_set_cursor(winid, cursor_pos)
    end

    local function url_to_markdown(url, title)
        title = title or url or "Link"
        return string.format("[%s](%s)", title, url)
    end

    -- Try to find markdown link under cursor FIRST (more specific match)
    local search_start = math.max(1, col - 100)
    local md_start = search_start
    while md_start do
        local s, e, title, mdurl = line:find(md_link_pattern, md_start)
        if not s then
            break
        end
        if col >= s and col <= e then
            local new_line = line:sub(1, s - 1) .. mdurl .. line:sub(e + 1)
            update_line(new_line)
            return
        end
        md_start = s + 1
    end

    -- Try to find bare URL under cursor
    local url_start = search_start
    while url_start do
        local s, e, url = line:find(url_pattern, url_start)
        if not s then
            break
        end
        if col >= s and col <= e then
            local new_line = line:sub(1, s - 1) .. url_to_markdown(url) .. line:sub(e + 1)
            update_line(new_line)
            return
        end
        url_start = s + 1
    end

    vim.notify("No URL or Markdown link found under cursor", vim.log.levels.WARN)
end

--- @param args vim.api.keyset.create_user_command.command_args
function callbacks.api(args)
    local fargs = args.fargs
    -- if next(fargs) == nil then
    --     require("telescope._extensions.vault.pickers").api():find()
    --     return
    -- end
    local api = fargs[1]
    if api == nil then
        return
    end
    local api_function = require("vault.api")[api]
    if api_function == nil then
        return
    end
    local arguments = {}
    for i = 2, #fargs do
        table.insert(arguments, fargs[i])
    end
    api_function(unpack(arguments))
end

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
--- @param args vim.api.keyset.create_user_command.command_args
--- @usage
--- ```lua
--- ```
function callbacks.create_new_note(args)
    local fargs = args.fargs
    if next(fargs) == nil then
        require("vault.popups.fleeting_note")()
        return
    end

    local new_slug = table.concat(fargs, " ")
    local notes = require("vault.notes")():filter("slug", new_slug, "exact", false)
    if next(notes.map) then
        notes.map[new_slug]:edit()
        return
    end
    local path = require("vault.utils").slug_to_path(new_slug)
    local note = require("vault.notes.note")(path)
    note:write(path)
    note:edit()
end

--- @param args vim.api.keyset.create_user_command.command_args
function callbacks.pick_dirs(args)
    local fargs = args.fargs
    if next(fargs) == nil then
        require("telescope._extensions.vault.pickers").dirs():find()
        return
    end
    local notes = require("vault.notes")():filter("relpath", fargs[1], "startswith", false)
    require("telescope._extensions.vault.pickers").notes({ notes = notes }):find()
end

---Edits a random note from the vault.
---@param args vim.api.keyset.create_user_command.command_args
---@return nil
function callbacks.edit_random_note(args)
    ---@type vault.Notes
    local notes
    if #args.fargs == 0 then
        notes = require("vault.notes")()
    else
        notes = require("vault.notes")():filter("slug", table.concat(args.fargs, " "), "fuzzy")
    end
    local random_note = notes:get_random()
    if random_note == nil then
        return
    end
    random_note:edit()
end

--- vault.Tags
--- @param args vim.api.keyset.create_user_command.command_args
function callbacks.open_tags_picker(args)
    local fargs = args.fargs
    if next(fargs) == nil then
        require("telescope._extensions.vault.pickers").tags():find()
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

    require("telescope._extensions.vault.pickers")
        .notes({ notes = require("vault.notes")():filter(filter_opts) })
        :find()
end

--- Vault Dates
--- Opens a picker with the dates
--- @param args vim.api.keyset.create_user_command.command_args
--- @return nil
function callbacks.open_dates_picker(args)
    local fargs = args.fargs
    if next(fargs) == nil then
        require("telescope._extensions.vault.pickers").dates():find()
        return
    end
    --TODO: Add configuration to set the date format
    local today = os.date("%Y-%m-%d")
    local year_ago = os.date("%Y-%m-%d", os.time() - 60 * 60 * 24 * 365)
    -- require("telescope._extensions.vault.pickers").dates(tostring(today), tostring(year_ago))
    require("telescope._extensions.vault.pickers")
        .dates({ start_date = tostring(today), end_date = tostring(year_ago) })
        :find()
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
    vim.cmd("e " .. vim.fn.fnameescape(path))
end

function callbacks.open_properties_picker(args)
    local fargs = args.fargs
    if next(fargs) == nil then
        require("telescope._extensions.vault.pickers").properties():find()
        return
    end
    local values = {}
    for _, value in ipairs(fargs) do
        table.insert(values, value)
    end
    require("telescope._extensions.vault.pickers").properties({ values = values }):find()
end

--- @command :VaultYesterday {dates} [[
--- Opens a picker with the statuses
--- @command ]]
--- @param args vim.api.keyset.create_user_command.command_args
--- @return nil
function callbacks.open_notes_status_picker(args)
    local fargs = args.fargs
    if next(fargs) == nil then
        -- require("telescope._extensions.vault.pickers").root_tags():find()
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

    require("telescope._extensions.vault.pickers").notes({ notes = notes }):find()
end

--- vault.FleetingNote
--- Opens a fleeting note
--- @param args vim.api.keyset.create_user_command.command_args
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
    require("telescope._extensions.vault.pickers")
        .notes({ notes = require("vault.notes")():orphans() })
        :find()
end

--- vault.Linked
--- Opens a picker with linked notes
--- @return nil
function callbacks.open_linked_picker()
    require("telescope._extensions.vault.pickers")
        .notes({ notes = require("vault.notes")():linked() })
        :find()
end

--- Opens a live grep picker with fuzzy search
--- @param args vim.api.keyset.create_user_command.command_args
--- @return nil
function callbacks.open_live_grep_picker(args)
    -- TODO: Implement live_grep picker
    vim.notify("[vault] VaultGrep is not yet implemented", vim.log.levels.WARN)
    -- if args.range == 0 then
    --     require("telescope._extensions.vault.pickers").live_grep({ query = "" }):find()
    --     return
    -- end
    -- local query = table.concat(args.fargs, " ")
    -- require("telescope._extensions.vault.pickers").live_grep({ query = query }):find()
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
    vim.cmd("e " .. vim.fn.fnameescape(path))
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
--- @param args vim.api.keyset.create_user_command.command_args
--- @return nil
function callbacks.rename(args)
    local note = require("vault.notes.note")(vim.fn.expand("%:p"))
    if next(args.fargs) == nil then
        vim.notify("Not renamed")
        --- TODO: Implement to open input popup
        return
    end
    local new_slug = table.concat(args.fargs, " ")
    if new_slug == "" then
        return
    end
    local new_path = require("vault.utils").slug_to_path(new_slug)

    local ok, err = pcall(function()
        note:move(new_path)
    end)
    if not ok then
        vim.notify("Failed to move note: " .. tostring(err), vim.log.levels.ERROR)
        return
    end

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
    local notes = require("vault.notes")():filter(vim.tbl_keys(inlinks))
    require("telescope._extensions.vault.pickers").notes({ notes = notes }):find()
end

--- vault.NoteOutlinks
--- Opens a picker with the notes that current note links to
--- ```vim
--- :VaultNoteOutlinks
--- ```
---
--- ```lua
--- pickers.notes({ notes = require('vault.notes')():with_slugs(vim.tbl_keys(outlinks)) }):find()
--- ```
--- @return nil
function callbacks.note_outlinks_picker()
    local note = require("vault.notes.note")(vim.fn.expand("%:p"))
    local outlinks = note.data.outlinks or {}
    if next(outlinks) == nil then
        vim.notify("No outlinks")
        return
    end
    -- pickers.notes({}, nil, outlinks):find()
    local slugs = {}
    for _, outlink in pairs(outlinks) do
        table.insert(slugs, outlink.data.slug)
    end

    require("telescope._extensions.vault.pickers")
        .notes({ notes = require("vault.notes")():filter(slugs) })
        :find()
end

--- vault.NoteTags
--- Opens a picker with the notes that have the tags
--- ```vim
--- :VaultNoteTags <range>
--- ```
---
--- ```lua
--- ```
--- @param args vim.api.keyset.create_user_command.command_args
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
    require("telescope._extensions.vault.pickers")
        .notes({ notes = require("vault.notes")():filter(slugs) })
        :find()
end

--- Create a new note from the selected text, and replace the selected text with a link to the new note
--- @param args vim.api.keyset.create_user_command.command_args
function callbacks.note_from_selected_text(args)
    local start_pos = vim.api.nvim_buf_get_mark(0, "<")
    local end_pos = vim.api.nvim_buf_get_mark(0, ">")

    -- Validate marks
    if start_pos[1] == 0 or end_pos[1] == 0 then
        vim.notify("No selection found", vim.log.levels.WARN)
        return
    end

    -- Adjust for 0-based indexing for API calls
    local row1, col1 = start_pos[1] - 1, start_pos[2]
    local row2, col2 = end_pos[1] - 1, end_pos[2]

    -- Handle visual line mode or block mode if necessary, but assuming characterwise for now
    -- In visual line mode, col1 is 0 and col2 is 2147483647
    if col2 == 2147483647 then
        local line_content = vim.api.nvim_buf_get_lines(0, row2, row2 + 1, false)[1]
        col2 = #line_content
    else
        -- Include the last character
        col2 = col2 + 1
    end

    local lines = vim.api.nvim_buf_get_text(0, row1, col1, row2, col2, {})
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

    -- Optional: Make UUID optional via config? For now keeping it but maybe user wants control
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

    -- Replace text with link
    vim.api.nvim_buf_set_text(0, row1, col1, row2, col2, { link })

    local new_note_content = table.concat(lines, "\n")
    local note = require("vault.notes.note")(new_note_path)
    note.data.content = new_note_content
    note:write()
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
--- @param args vim.api.keyset.create_user_command.command_args
--- @return nil
function callbacks.open_note_properties_picker(args)
    local fargs = args.fargs
    if next(fargs) == nil then
        require("telescope._extensions.vault.pickers").properties():find()
        return
    end
    local values = {}
    for _, value in ipairs(fargs) do
        table.insert(values, value)
    end
    require("telescope._extensions.vault.pickers").properties({ values = values }):find()
end

--- VaultNoteByDir
--- Opens a picker with notes by directory
--- @param args vim.api.keyset.create_user_command.command_args
function callbacks.open_note_by_dir_picker(args)
    local fargs = args.fargs
    if next(fargs) == nil then
        -- return notes in the root directory
        require("telescope._extensions.vault.pickers")
            .notes({
                notes = require("vault.notes")():filter("relpath", "", "exact", false),
            })
            :find()
        return
    end
    local notes = require("vault.notes")():filter("relpath", fargs[1], "startswith", false)
    require("telescope._extensions.vault.pickers").notes({ notes = notes }):find()
end

--- @param args vim.api.keyset.create_user_command.command_args
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
    if vim.tbl_contains(completions.vault_notes_presets(), input[1]) then
        args[1] = input[1]
    end

    -- Check if the second argument is a valid key
    if vim.tbl_contains(completions.note_data_keys(), input[2]) then
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
        require("telescope._extensions.vault.pickers").notes():find()
    elseif #args == 1 then
        if args[1] ~= "by" then
            require("telescope._extensions.vault.pickers")
                .notes({ notes = require("vault.notes")()[args[1]] })
                :find()
        elseif args[1] == "by" then
            vim.notify("Need further arguments")
        end
    elseif #args == 2 then
        return
    elseif #args == 3 then
        if type(args[3]) ~= "table" then
            args[3] = { args[3] }
        end
        require("telescope._extensions.vault.pickers")
            .notes({
                notes = require("vault.notes")({ args[2], args[3], {}, "startswith", "all" }),
            })
            :find()
    elseif #args == 4 then
        if type(args[3]) ~= "table" then
            args[3] = { args[3] }
        end
        if type(args[4]) ~= "table" then
            args[4] = { args[4] }
        end
        require("telescope._extensions.vault.pickers")
            .notes({
                notes = require("vault.notes")({ args[2], args[3], args[4], "startswith", "all" }),
            })
            :find()
    elseif #args == 5 then
        if type(args[3]) ~= "table" then
            args[3] = { args[3] }
        end
        if type(args[4]) ~= "table" then
            args[4] = { args[4] }
        end
        require("telescope._extensions.vault.pickers")
            .notes({
                notes = require("vault.notes")({ args[2], args[3], args[4], args[5], "all" }),
            })
            :find()
    elseif #args == 6 then
        if type(args[3]) ~= "table" then
            args[3] = { args[3] }
        end
        if type(args[4]) ~= "table" then
            args[4] = { args[4] }
        end
        require("telescope._extensions.vault.pickers")
            .notes({
                notes = require("vault.notes")({ args[2], args[3], args[4], args[5], args[6] }),
            })
            :find()
    end
end

function callbacks.notes(args)
    if next(args.fargs) == nil then
        require("telescope._extensions.vault.pickers").notes():find()
        return
    elseif #args.fargs == 1 then
        construct_notes_picker_args(args.fargs)
    end
end

function callbacks.tasks()
    -- TODO: Implement to complete by status
    require("telescope._extensions.vault.pickers").tasks():find()
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
            complete = completions.note,
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
            complete = completions.notes_filter,
            nargs = "*",
        },
    },
    ["VaultNotes"] = {
        --- Generates a picker with certain collection of notes
        callback = callbacks.notes,
        opts = {
            desc = "Open a picker with a collection of notes",
            complete = completions.notes_filter,
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
            complete = completions.tags,
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
            complete = completions.dates,
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
            complete = completions.statuses,
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
            require("telescope._extensions.vault.pickers")
                .notes({ notes = require("vault.notes")():internals() })
                :find()
        end,
        opts = {
            desc = "Open a picker with the internals",
            complete = completions.notes_filter,
            nargs = "*",
        },
    },
    ["VaultLeaves"] = {
        callback = function()
            require("telescope._extensions.vault.pickers")
                .notes({ notes = require("vault.notes")():leaves() })
                :find()
        end,
        opts = {
            desc = "Open a picker with the leaves",
            complete = completions.notes_filter,
            nargs = "*",
        },
    },
    ["VaultDanglingLinks"] = {
        callback = function()
            require("telescope._extensions.vault.pickers")
                .notes({
                    notes = require("vault.notes")():with_outlinks_unresolved(),
                })
                :find()
        end,
        opts = {
            desc = "Open a picker with the dangling links",
            complete = completions.notes_filter,
            nargs = "*",
        },
    },
    ["VaultOutlinksUnresolved"] = {
        callback = function()
            require("telescope._extensions.vault.pickers")
                .notes({
                    notes = require("vault.notes")():with_outlinks_unresolved(),
                })
                :find()
        end,
        opts = {
            desc = "Open a picker with the outlinks unresolved",
            complete = completions.notes_filter,
            nargs = "*",
        },
    },
    ["VaultOutlinksResolvedOnly"] = {
        callback = function()
            require("telescope._extensions.vault.pickers")
                .notes({
                    notes = require("vault.notes")():with_outlinks_resolved_only(),
                })
                :find()
        end,
        opts = {
            desc = "Open a picker with the outlinks resolved only",
            complete = completions.notes_filter,
            nargs = "*",
        },
    },
    ["VaultWikilinks"] = {
        callback = function()
            require("telescope._extensions.vault.pickers").wikilinks():find()
        end,
        opts = {
            desc = "Open a picker with the wikilinks",
            complete = completions.note_slugs,
            nargs = "*",
        },
    },
    ["VaultTasks"] = {
        callback = callbacks.tasks,
        opts = {
            desc = "Open a picker with the tasks accross the vault",
            complete = completions.statuses,
            nargs = "*",
        },
    },
    ["VaultNotesCluster"] = {
        callback = function(args)
            local path = vim.fn.expand("%")
            -- Check if we are even in the vault note buffer
            if type(path) ~= "string" then
                return
            end
            -- if root dir is nil or empty, return early

            -- Are we even in the vault?

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
            local note = vim.deepcopy(notes):filter("slug", note_slug, "exact"):list()[1]
            if not note then
                vim.notify("Note not found " .. note_slug)
                return
            end
            local cluster = notes:to_cluster(note, 0)
            require("telescope._extensions.vault.pickers").notes({ notes = cluster }):find()
        end,
        opts = {
            desc = "Open a picker with the notes that are in the same cluster",
            complete = completions.note_slugs,
            nargs = "*",
        },
    },
    ["VaultMove"] = {
        --- Command to move a note to a new location.
        --- If oargs then open picker
        --- if arg, and it is a valid relpath, then move to that location
        callback = function()
            vim.notify("[vault] :VaultMove is deprecated, use :VaultRename instead", vim.log.levels.WARN)

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
            --     pickers.move_note_to(note):find()
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
            complete = completions.dirs,
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
            complete = completions.note_tags,
            desc = "Open a picker with the notes that have the tags and the note",
        },
    },
    ["VaultNoteExtract"] = {
        callback = callbacks.note_from_selected_text,
        opts = {
            nargs = "*",
            range = true,
            complete = completions.note_slugs,
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
        --- @param args vim.api.keyset.create_user_command.command_args
        --- @return nil
        callback = function(args)
            local fargs = args.fargs
            if next(fargs) == nil then
                require("telescope._extensions.vault.pickers").properties():find()
                return
            end
            local values = {}
            for _, value in ipairs(fargs) do
                table.insert(values, value)
            end
            require("telescope._extensions.vault.pickers").properties({ values = values }):find()
        end,
        opts = {
            nargs = "*",
            complete = function(_, cmd_line, _)
                local arguments = vim.split(cmd_line, " ")
                if next(arguments) == nil then
                    return
                end
                --- @type vault.Property.Data.name[]
                local properties = vim.tbl_keys(require("vault.scanner").properties())
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
                    properties = vim.tbl_keys(require("vault.scanner").properties())
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
                local paths = vim.tbl_keys(require("vault.scanner").dirs())
                return paths
            end,
            desc = "Open a picker with notes by directory",
        },
    },
    ["VaultNoteNew"] = {
        callback = callbacks.create_new_note,
        opts = {
            nargs = "*",
            complete = completions.dirs,
            desc = "Create a new note",
        },
    },
    ["VaultDirs"] = {
        callback = callbacks.pick_dirs,
        opts = {
            desc = "Open a picker with the directories in the vault",
            complete = completions.dirs,
            nargs = "*",
        },
    },
    ["Vault"] = {
        callback = callbacks.api,
        opts = {
            desc = "Open a picker with the directories in the vault",
            complete = completions.api,
            nargs = "*",
        },
    },
    ["VaultToggleLink"] = {
        callback = callbacks.toggle_link,
        opts = {
            desc = "Toggle a link under cursor",
            nargs = 0,
        },
    },
    ["VaultBases"] = {
        --- @command :VaultBases [base_name] [[
        --- Open a picker with all bases or drill into a specific base's matched notes
        --- @command ]]
        callback = function(args)
            local fargs = args.fargs
            if next(fargs) == nil then
                require("telescope._extensions.vault.pickers").bases():find()
                return
            end
            local base_name = table.concat(fargs, " ")
            require("vault.api").open_picker_base_notes(base_name)
        end,
        opts = {
            desc = "Open a picker with Obsidian base database views",
            nargs = "*",
            complete = function()
                local ok, bases = pcall(function()
                    return require("vault.bases")()
                end)
                if ok and bases then
                    return bases:names()
                end
                return {}
            end,
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
