--- @class vault.Pickers
--- TODO: Picker
--- assign_tags fun(opts: table?, tags: string[]): nil - Picker to choose the tag to assign, or do this as action
--- for tags picker?
--- put_links fun(opts: table?, links: string[]): nil - Picker to choose the link to put, or do this as action
--- for notes picker?
--- put_wikilinks fun(opts: table?, wikilinks: string[]): nil - Picker to choose the wikilink to put, or do this as action
local vault_pickers = {}

local Log = require("plenary.log")
local Gradient = require("gradient")

-- Telecope modules
local pickers = require("telescope.pickers")
local finders = require("telescope.finders")
local sorters = require("telescope.sorters")
local previewers = require("telescope.previewers")
local actions = require("telescope.actions")
local actions_state = require("telescope.actions.state")
local entry_display = require("telescope.pickers.entry_display")

local vault_state = require("vault.core.state")
--- @type vault.Config|vault.Config.options
local config = require("vault.config")
local fetcher = require("vault.fetcher")
-- local vault_highlights = require("vault.highlights")

local utils = require("vault.utils")
local error_msg = require("vault.utils.fmt.error")

local vault_previewers = require("vault.pickers.previewers")
local vault_mappings = require("vault.pickers.mappings")
local vault_layouts = require("vault.pickers.layouts")

local Note = require("vault.notes.note")

--- @alias Gradient string[]

--- @alias vault.TelescopeFindResults fun(self: vault.TelescopeFindResults): vault.TelescopeFindResults
--- @alias vault.TelescopeDisplayerConfig {separator: string, items: {width: number, remaining: boolean}[]}

--- @alias vault.Picker.map fun(mode: string, keymap: string, callback: fun(bufnr: integer))
--- @alias vault.TelescopeLayoutStrategy string|fun(self: Picker, window: TelescopeWindow): TelescopeLayout
--- @alias vault.TelescopeWindowOptions table
--- @alias vault.TelescopeFinder table
--- @alias vault.TelescopeSorter table
--- @alias vault.TelescopePreviewer table
--- @alias vault.TelescopeEntryManager table
--- @alias vault.TelescopeEntry {value: any, valid?: boolean, ordinal: string, display: string | vault.TelescopeEntryMaker, filename: string?, bufnr: integer?, lnum: number?, col: number}
--- @alias vault.TelescopeMultiSelect table
--- @alias vault.TelescopeScrollStrategy string|fun(self: Picker, window: TelescopeWindow, direction: string, reset: boolean)
--- @alias vault.TelescopeTiebreakStrategy string|fun(self: Picker, entries: vault.TelescopeEntry[])
--- @alias vault.TelescopeSelectionStrategy string|fun(self: Picker, entries: vault.TelescopeEntry[], prompt: string)
--- @alias vault.TelescopeBorder string|table
--- @alias vault.TelescopeBorderChars table
--- @alias vault.TelescopeCachePickerOptions table
--- @alias vault.TelescopeEntryMaker fun(entry: vault.TelescopeEntry): vault.TelescopeEntry

--- @class TelescopePickerOptions
--- @field layout_strategy? vault.TelescopeLayoutStrategy
--- @field get_window_options? fun(): vault.TelescopeWindowOptions
--- @field prompt_title? string
--- @field results_title? string
--- @field preview_title? string
--- @field prompt_prefix? string
--- @field wrap_results? boolean
--- @field selection_caret? string
--- @field entry_prefix? string
--- @field multi_icon? string
--- @field initial_mode? string
--- @field debounce? number
--- @field default_text? string
--- @field get_status_text? fun(): string
--- @field on_input_filter_cb? fun()
--- @field finder vault.TelescopeFinder
--- @field sorter? Sorter
--- @field previewer? vault.TelescopePreviewer|vault.TelescopePreviewer[]
--- @field current_previewer_index? number
--- @field default_selection_index? number
--- @field get_selection_window? fun(): TelescopeWindow
--- @field cwd? string
--- @field _completion_callbacks? table
--- @field manager? vault.TelescopeEntryManager
--- @field _multi? vault.TelescopeMultiSelect
--- @field track? boolean
--- @field attach_mappings? boolean
--- @field file_ignore_patterns? string[]
--- @field scroll_strategy? vault.TelescopeScrollStrategy
--- @field sorting_strategy? table
--- @field tiebreak? vault.TelescopeTiebreakStrategy
--- @field selection_strategy? vault.TelescopeSelectionStrategy
--- @field push_cursor_on_edit? boolean
--- @field push_tagstack_on_edit? boolean
--- @field layout_config? table
--- @field cycle_layout_list? boolean
--- @field border? vault.TelescopeBorder
--- @field borderchars? vault.TelescopeBorderChars
--- @field cache_picker? vault.TelescopeCachePickerOptions
--- @field temp__scrolling_limit? number
--- @field __locations_input? boolean
--- @field create_layout? fun(self: Picker, window: TelescopeWindow): TelescopeLayout
--- @field on_complete? fun()[]
--- @field __hide_previewer? boolean
--- @field resumed_picker? boolean
--- @field fix_preview_title? boolean

--- @class telescope_popup_options.vault.Notes: telescope_popup_options
--- @field notes? vault.Notes

--- Search for notes in vault
--- @param opts? telescope_popup_options.vault.Notes
--- @return nil
function vault_pickers.notes(opts)
    opts = opts or {}
    opts.notes = opts.notes or require("vault.notes")()

    --- @type vault.Note[]
    local results = opts.notes:list()
    if next(results) == nil then
        Log.info("No notes found in vault")
        return
    end

    local average_content_count = opts.notes:average_chars()
    local prompt_title = string.format("average chars: %d", average_content_count)

    local steps = 64
    --- @type Gradient|nil
    local colors = Gradient.from_stops(steps, "Boolean", "#444444", "#a9a9a9", "String")
    if type(colors) ~= "table" then
        error(error_msg.COMMAND_EXECUTION_ERROR("Gradient.from_stops", vim.inspect(colors)))
    end

    local hl_name = "VaultNoteContent"
    for i, color in ipairs(colors) do
        vim.api.nvim_set_hl(0, hl_name .. tostring(i), { fg = color })
    end

    --- @type string
    local col_2 = ""
    local col_2_maxwidth = 0
    for _, note in ipairs(results) do
        local relpath = note.data.relpath
        if relpath:find("/") ~= nil then
            col_2 = string.match(relpath, "(.*/)") or ""
        end
        local col2_width = col_2:len()
        if col2_width > col_2_maxwidth then
            col_2_maxwidth = col2_width
        end
    end

    local make_display = function(entry)
        local col_1_hl_name = "TelescopeResultsNormal"
        --- @type vault.Note
        local note = entry.value

        --- --
        local content = note.data.content or ""
        local content_chars_count = content:len()
        local index = math.min(math.floor(content_chars_count / 16), steps)
        if index == 0 then
            index = 1
        end
        col_1_hl_name = hl_name .. tostring(index)

        --- --
        -- Display dir before note name
        col_2 = vim.fn.fnamemodify(note.data.slug, ":h")
        local col_2_hl_name = "TelescopeResultsComment"

        -- Alternative for display_group
        -- if note.data.frontmatter.data.type then
        --     display_group = note.data.frontmatter.data.type
        -- end

        --- --
        --- @type vault.stem
        local col_3 = vim.fn.fnamemodify(note.data.path, ":t:r")
        local col_3_hl_name = col_1_hl_name

        --- -
        --- @type vault.TelescopeDisplayerConfig
        --- @see entry_display.create
        local displayer_config = {
            separator = " ",
            items = {
                { width = 2 },
                { width = col_2_maxwidth },
                { remaining = true },
                { remaining = true },
            },
        }

        --- @type fun(self: table, picker: any): string, table
        local displayer = entry_display.create(displayer_config)

        local display_value = {
            { "██", col_1_hl_name },
            { col_2, col_2_hl_name },
            { col_3, col_3_hl_name },
        }

        return displayer(display_value)
    end

    --- @param note vault.Note
    --- @return vault.TelescopeEntry
    local entry_maker = function(note)
        return {
            value = note,
            ordinal = note.data.path .. " " .. note.data.content,
            display = make_display,
            filename = note.data.path,
        }
    end

    --- Sort by name desc
    --- @param a vault.Note
    --- @param b vault.Note
    table.sort(results, function(a, b)
        return vim.fn.strcharpart(a.data.path, -1, #a.data.path)
            < vim.fn.strcharpart(b.data.path, -1, #b.data.path)
    end)

    local finder = finders.new_table({
        results = results,
        entry_maker = entry_maker,
    })

    local picker_opts = {
        prompt_title = prompt_title,
        finder = finder,
        sorter = sorters.get_fzy_sorter(),
        previewer = vault_previewers.notes,
        attach_mappings = vault_mappings.notes,
    }
    local picker = pickers.new(vault_layouts.notes(), picker_opts)

    vault_state.set_global_key("picker", picker)
    picker:find()
    return picker
end

--- @class telescope_popup_options.vault.Tags: telescope_popup_options

--- Search for tags
--- @param opts? table - Telescope options
function vault_pickers.tags(opts)
    opts = opts or {}
    opts.tags = opts.tags or require("vault.tags")()

    --- @type vault.Tags.list
    local tags_list = opts.tags:list()
    if next(opts.tags) == nil then
        Log.info("No tags found in vault")
        return
    end

    -- sort tags by notes count
    table.sort(tags_list, function(a, b)
        return a.data.count > b.data.count
    end)

    local steps = 64
    --- @type Gradient|nil
    local colors = Gradient.from_stops(steps, "#444444", "#a9a9a9", "String")
    if type(colors) ~= "table" then
        -- error(
        --     error_msg.COMMAND_EXECUTION_ERROR("Gradient.from_stops", "table", vim.inspect(colors))
        -- )
        -- error("Gradient.from_stops", "table", vim.inspect(colors))
        error("Gradient.from_stops")
    end
    local hl_name = "VaultTag"
    for i, color in ipairs(colors) do
        vim.api.nvim_set_hl(0, hl_name .. tostring(i), { fg = color })
    end

    --- @param entry vault.TelescopeEntry
    local make_display = function(entry)
        --- @type vault.Tag
        local tag = entry.value
        local sources_count = tag.data.count

        --- --
        local col_1 = tag.data.name
        local col_1_width = 29
        local i = math.min(math.floor(sources_count / 2), steps)
        if i == 0 then
            i = 1
        end
        local col_1_hl_name = hl_name .. tostring(i)
        --- --

        local col_2 = tostring(sources_count)
        local col_2_width = col_2:len()
        local col_2_hl_name = "TelescopeResultsNumber"
        --- --

        local displayer = entry_display.create({
            separator = " ",
            items = {
                { width = col_1_width },
                { remaining = true },
                { width = col_2_width },
                { remaining = true },
            },
        })

        return displayer({
            { col_1, col_1_hl_name },
            { col_2, col_2_hl_name },
        })
    end

    --- @param tag vault.Tag
    --- @return vault.TelescopeEntry
    local entry_maker = function(tag)
        return {
            value = tag,
            ordinal = tag.data.name .. " " .. tostring(tag.data.count),
            display = make_display,
        }
    end

    local finder = finders.new_table({
        results = tags_list,
        entry_maker = entry_maker,
    })

    local picker_opts = {
        prompt_title = "tags",
        finder = finder,
        sorter = sorters.get_fzy_sorter(),
        previewer = vault_previewers.tags,
        attach_mappings = vault_mappings.tags,
    }
    local picker = pickers.new(vault_layouts.tags(), picker_opts)
    picker:find()
    vault_state.set_global_key("picker", picker)
    return picker
end

--
-- --- Picker for browsing tags from root tag.
-- --- For example we have tag: status/TODO/later
-- --- We want to browse it like this:
-- --- status
-- --- status/TODO
-- --- status/TODO/later
-- --- And then pick we open notes picker filtered by tag: status/TODO/later
-- --- @param root_tag_name? string - Root tag to start browsing from
-- function vault_pickers.root_tags(root_tag_name)
--     local root_dir = config.options.root
--     local tags = {}
--     if root_tag_name ~= nil then
--         tags = Tags():by(root_tag_name)
--     else
--         tags = Tags()
--     end
--
--     if next(tags) == nil then
--         Log.info("No root tags found in vault: " .. root_dir)
--         return
--     end
--
--     local root_tags = {}
--     local seen_root_tags = {}
--     for _, tag in ipairs(tags) do
--         local _root_tag_name = tag.name:match("([^/]+)")
--         if not seen_root_tags[_root_tag_name] then
--             seen_root_tags[_root_tag_name] = true
--             table.insert(root_tags, _root_tag_name)
--         end
--     end
--
--     local make_display = function(entry)
--         local entry_width = 29
--         local displayer = entry_display.create({
--             separator = " ",
--             items = {
--                 { width = entry_width },
--                 { remaining = true },
--             },
--         })
--         local tag_name = entry.name
--         return displayer({
--             { tag_name, "TelescopeResultsNormal" },
--         })
--     end
--
--     local entry_maker = function(tag)
--         return {
--             value = tag,
--             ordinal = tag,
--             display = make_display,
--         }
--     end
--
--     local function enter(bufnr)
--         local selection = actions_state.get_selected_entry()
--         local root_tag = selection.value
--         vault_pickers.root_tags(root_tag)
--         vault_actions.close(bufnr)
--     end
--
--     local picker = pickers
--         .new(vault_layouts.mini(), {
--             prompt_title = "Status",
--             finder = finders.new_table({
--                 results = root_tags,
--                 entry_maker = entry_maker,
--             }),
--             sorter = sorters.get_generic_fuzzy_sorter(),
--             attach_mappings = function(_, _)
--                 actions.select_default:replace(enter)
--                 return true
--             end,
--         })
--         :find()
--     vault_state.set_global_key("picker", picker)
--     return picker
-- end

--- @class telescope_popup_options.vault.Dates: telescope_popup_options
--- @field start_date? string Specifies the start date of the date range. Defaults: 7 days ago
--- @field end_date? string Specifies the end date of the date range. Defaults: today
--- Search for date and corresponding note
--- TODO: Add option to create note if it doesn't exist
--- TODO: Add option to configure date format
function vault_pickers.dates(opts)
    --- @type string
    opts.end_date = opts.end_date or tostring(os.date("%Y-%m-%d"))
    --- @type string
    opts.start_date = opts.start_date or tostring(os.date("%Y-%m-%d", os.time() - 7 * 24 * 60 * 60))

    local Dates = require("dates")
    local date_values = Dates.from_to(opts.start_date, opts.end_date)
    local daily_dir = config.options.dirs.journal.daily

    local daily_notes = {}
    for _, date in ipairs(date_values) do
        -- local date_with_weekday = date .. " " .. Dates.get_weekday(date)
        local date_with_weekday = string.format("%s %s", date, Dates.get_weekday(date))
        local daily_note = {}
        daily_note.value = date_with_weekday
        daily_note.path = string.format("%s/%s%s", daily_dir, date_with_weekday, config.options.ext)
        daily_note.relpath = utils.path_to_relpath(daily_note.path)
        daily_note.basename = vim.fn.fnamemodify(daily_note.path, ":t")
        daily_note.exists = vim.fn.filereadable(daily_note.path) == 1
        table.insert(daily_notes, daily_note)
    end

    -- reverse dates
    local reversed_dates = {}
    for i = #daily_notes, 1, -1 do
        table.insert(reversed_dates, daily_notes[i])
    end
    daily_notes = reversed_dates

    local function enter(bufnr)
        local selection = actions_state.get_selected_entry()
        local path = selection.value.path
        local content = "# " .. selection.value.name .. "\n"
        actions.close(bufnr)
        vim.cmd("edit " .. path)
        -- If daily note doesn't exist, create it and open it
        if selection.value.exists == false then
            vim.api.nvim_buf_set_lines(0, 0, -1, false, vim.split(content, "\n"))
            vim.cmd("normal! Go")
        end
    end

    local results_height = #daily_notes + 5
    local results_width = 0

    for _, date in ipairs(daily_notes) do
        -- Find the longest date
        local date_width = date.value:len()
        if date_width > results_width then
            results_width = date_width
        end
    end

    results_width = results_width + 2
    local bufwidth = math.floor(vim.api.nvim_list_uis()[1].width * 0.8) -- TODO: Make this configurable
    local preview_width = bufwidth - results_width - 3
    local entry_width = 29

    --- @param entry vault.TelescopeEntry
    local make_display = function(entry)
        local display_value = {}

        local displayer = entry_display.create({
            separator = " ",
            items = {
                { width = entry_width },
                { remaining = true },
            },
        })
        if entry.value.exists == true then
            display_value = {
                entry.value.value,
                "TelescopeResultsNormal",
            }
        else
            display_value = {
                entry.value.value,
                "TelescopeResultsComment",
            }
        end

        return displayer({
            display_value,
        })
    end

    local entry_maker = function(entry)
        return {
            value = entry,
            ordinal = entry.value,
            display = make_display,
            filename = entry.path,
        }
    end

    local picker = pickers
        .new({}, {
            prompt_title = "Dates",
            finder = finders.new_table({
                results = daily_notes,
                entry_maker = entry_maker,
            }),
            sorter = sorters.get_generic_fuzzy_sorter(),
            previewer = previewers.vim_buffer_cat.new({
                get_buffer_by_name = function(_, entry)
                    local bufnr = vim.api.nvim_create_buf(false, true)
                    local lines = {}
                    if entry.exists then
                        lines = vim.fn.readfile(entry.path)
                    else
                        lines = { "No notes for this date" }
                    end
                    if type(bufnr) ~= "number" then
                        error("bufnr is not a number")
                    end
                    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
                    -- vim.api.nvim_buf_set_option(bufnr, "filetype", "markdown")
                    vim.api.nvim_set_option_value("filetype", "markdown", { buf = bufnr })
                    return bufnr
                end,
            }),
            sorting_strategy = "ascending",
            layout_config = {
                height = results_height,
                width = bufwidth,
                preview_width = preview_width,
            },
            attach_mappings = function()
                actions.select_default:replace(enter)
                return true
            end,
        })
        :find()
    vault_state.set_global_key("picker", picker)
    return picker
end

function vault_pickers.wikilinks()
    local Wikilinks = require("vault.wikilinks")
    local wikilinks = Wikilinks()
    local results = wikilinks:list()

    --- @param entry table
    local make_display = function(entry)
        --- @type vault.Wikilink
        local wikilink = entry.value

        local entry_width = string.len(wikilink.data.slug) + 2
        local displayer = entry_display.create({
            separator = " ",
            items = {
                { width = entry_width },
                { remaining = true },
            },
        })
        local display_value = {
            entry.value.data.slug,
            "TelescopeResultsNormal",
        }
        return displayer({
            display_value,
        })
    end

    local entry_maker = function(entry)
        return {
            value = entry,
            ordinal = entry.data.slug,
            display = make_display,
        }
    end

    local picker = pickers
        .new({}, {
            prompt_title = "Wikilinks",
            finder = finders.new_table({
                results = results,
                entry_maker = entry_maker,
            }),
            sorter = sorters.get_generic_fuzzy_sorter(),
            -- previewer = previewers.vim_buffer_cat.new({
            --     get_buffer_by_name = function(_, entry)
            --         local bufnr = vim.api.nvim_create_buf(false, true)
            --         local lines = vim.fn.readfile(entry.path)
            --         if type(bufnr) ~= "number" then
            --             error("bufnr is not a number")
            --         end
            --         vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
            --         vim.api.nvim_buf_set_option(bufnr, "filetype", "markdown")
            --         return bufnr
            --     end,
            -- }),
            sorting_strategy = "ascending",
        })
        :find()
    vault_state.set_global_key("picker", picker)
    return picker
end

--- TODO: Make action that will search for notes with similar tags that selected note has
--- If we have note with tags: status/TODO, class/Action, class/Action/Project
--- We could search for notes containing tags: status/TODO, class/Action, class/Action/Project
--- With mode "all" or "any"

--- Search for notes in Inbox directory
--- @param opts? telescope_popup_options.vault.Notes
function vault_pickers.inbox(opts)
    local inbox_dir = config.options.dirs.inbox

    opts = opts or {}
    opts.notes = opts.notes or require("vault.notes")()
    for _, note_path in ipairs(vim.fn.globpath(inbox_dir, "**/*" .. config.options.ext, true, true)) do
        local note = Note(note_path)
        table.insert(opts.notes, note)
    end

    vault_pickers.notes(opts)
end

--- @class telescope_popup_options.vault.Tasks: telescope_popup_options
--- @field tasks? table<string, table>
function vault_pickers.tasks(opts)
    opts = opts or {}
    opts.tasks = opts.tasks or require("vault.fetcher").tasks()
    local tasks = fetcher.tasks()
    local results = {}
    for slug, map in pairs(tasks) do
        for line_number, task in pairs(map) do
            if task.status == "[x]" then
                goto continue
            end
            task = {
                line_number = line_number,
                slug = slug,
                line = task.line,
                text = task.text,
                status = task.status,
            }
            table.insert(results, task)
            ::continue::
        end
    end
    -- Chunk example
    --     {
    --   line = "- [-] [[Routine/workout]]\n",
    --   line_number = 30,
    --   slug = "Journal/Daily/2022-01-03 Monday",
    --   status = "[-]",
    --   text = "[[Routine/workout]]"
    -- }

    local function enter(bufnr)
        local selection = actions_state.get_selected_entry()
        local path = selection.filename
        local line_number = selection.value.line_number
        actions.close(bufnr)
        -- vim.cmd("edit " .. path)
        -- vim.cmd(tostring(line_number) .. "G")
        vim.cmd("edit +" .. tostring(line_number) .. " " .. path)
    end

    local make_display = function(entry)
        local verbose_status = entry.value.status
        if verbose_status == "[-]" then
            verbose_status = "PENDING"
        elseif verbose_status == "[x]" then
            verbose_status = "DONE"
        elseif verbose_status == "[ ]" then
            verbose_status = "TODO"
        elseif verbose_status == "[>]" then
            verbose_status = "IN PROGRESS"
        end
        -- local stem = entry.value.slug:match("([^/]+)$")
        -- -- local slug_width = string.len(entry.value.slug) + 1
        -- local full_width = vim.api.nvim_get_option("columns") - 6
        -- -- align stem to the right
        -- local stem_width = string.len(stem)
        -- local entry_width = full_width - stem_width - 2
        -- local status_width = string.len(entry.value.status)
        -- verbose_status = verbose_status
        --     .. string.rep(" ", status_width - string.len(verbose_status))

        local full_width = vim.o.columns
        local stem = entry.value.slug:match("([^/]+)$")
        local stem_width = string.len(stem)
        local status_width = string.len(entry.value.status)
        -- local verbose_status_width = string.len(verbose_status) - should be fixed to max of verbose_statuses
        local verbose_status_width = 8
        -- align verbose_status to the right of column
        verbose_status = string.rep(" ", verbose_status_width - string.len(verbose_status))
            .. verbose_status
        local entry_width = full_width - stem_width - status_width - verbose_status_width - 2

        local displayer = entry_display.create({
            separator = " ",
            items = {
                { width = verbose_status_width },
                { width = status_width },
                { width = entry_width },
                { remaining = true },
                { width = stem_width },
            },
        })
        local verbose_status_value = {
            verbose_status,
            "TelescopeResultsNumber",
        }
        local status_value = {
            entry.value.status,
            "TelescopeResultsNormal",
        }
        local text_value = {
            entry.value.text,
            "TelescopeResultsNormal",
        }
        local stem_value = {
            stem,
            "TelescopeResultsComment",
        }
        return displayer({
            verbose_status_value,
            status_value,
            text_value,
            stem_value,
        })
    end

    local entry_maker = function(entry)
        return {
            value = entry,
            ordinal = entry.line:match("%s*(.*)"),
            display = make_display,
            filename = config.options.root .. "/" .. entry.slug .. config.options.ext,
        }
    end

    local picker = pickers
        .new({}, {
            prompt_title = "Tasks",
            finder = finders.new_table({
                results = results,
                entry_maker = entry_maker,
            }),
            sorter = sorters.get_generic_fuzzy_sorter(),
            sorting_strategy = "ascending",
            layout_config = {
                height = vim.o.lines - 4,
                width = vim.o.columns,
            },
            attach_mappings = function(_, _)
                actions.select_default:replace(enter)
                return true
            end,
        })
        :find()
    vault_state.set_global_key("picker", picker)
    return picker
end

--- @class telescope_popup_options.vault.move_note_to: telescope_popup_options
--- @field note? vault.Note

--- @param opts table
function vault_pickers.move_note_to(opts)
    opts = opts or {}
    opts.note = opts.note

    if opts.note == nil then
        -- get current buffer path
        local bufnr = vim.api.nvim_get_current_buf()
        local path = vim.api.nvim_buf_get_name(bufnr)
        if path:find(config.options.root) == nil then
            Log.error("Current buffer is not in vault")
            return
        end
        opts.note = Note(path)
    end

    local root_dir = config.options.root
    -- Simple picker to show all relative dirs where we can move note
    -- on enter we move note to selected dir
    local function enter(bufnr)
        local selection = actions_state.get_selected_entry()
        --- @type vault.path
        local path = selection.value
        local basename = vim.fn.fnamemodify(opts.note.data.path, ":t")
        local new_path = string.format("%s%s", path, basename)
        actions.close(bufnr)
        -- vim.fn.rename(note.data.path, new_path)
        opts.note:rename(new_path)
        -- Update current buffer.
        -- How does vim manage this?
        -- If we rename current buffer, it will be closed and new buffer will be opened
        local bufnr_of_note = vim.fn.bufnr(opts.note.data.path)
        -- vim.cmd("write") -- write changes to disk
        -- we couldnd write becaust the picker is still open
        vim.api.nvim_buf_delete(bufnr_of_note, { force = true })
        vim.cmd("edit " .. new_path)
    end

    --- @param entry vault.TelescopeEntry
    local make_display = function(entry)
        local entry_width = entry.value:len()
        local displayer = entry_display.create({
            separator = " ",
            items = {
                { width = entry_width },
                { remaining = true },
            },
        })
        local display_value = {
            -- entry.value,
            utils.path_to_relpath(entry.value),
            "TelescopeResultsNormal",
        }
        return displayer({
            display_value,
        })
    end

    local entry_maker = function(entry)
        return {
            value = entry,
            ordinal = entry,
            display = make_display,
        }
    end

    local attach_mappings = function()
        actions.select_default:replace(enter)
        return true
    end

    local results = {}
    for _, dir in ipairs(vim.fn.globpath(root_dir, "**/", true, true)) do
        table.insert(results, dir)
    end

    local picker = pickers
        .new({}, {
            prompt_title = "Move note to",
            finder = finders.new_table({
                results = results,
                entry_maker = entry_maker,
            }),
            sorter = sorters.get_generic_fuzzy_sorter(),
            attach_mappings = attach_mappings,
        })
        :find()
    vault_state.set_global_key("picker", picker)
    return picker
end

--- @class telescope_popup_options.vault.cluster: telescope_popup_options
--- @field path? string Path to note to open build cluster from
--- @field notes? vault.Notes Notes instance to use
--- @field depth? number Depth of cluster to build

--- Open picker for |vault.Notes.Cluster| from provided `vault.Note`. Default is current buffer.
--- @param opts table
function vault_pickers.open_cluster(opts)
    opts = opts or {}
    opts.notes = opts.notes or require("vault.notes")()
    opts.path = opts.path or vim.api.nvim_buf_get_name(vim.api.nvim_get_current_buf())
    opts.depth = opts.depth or 0
    -- local note = Note({
    --     path = path,
    -- })
    local note = Note(opts.path)
    local notes_cluster = require("vault.notes.cluster")(opts.notes, note, opts.depth)
    if next(notes_cluster.map) == nil then
        error("No notes found in cluster")
        return
    end
    vault_pickers.notes(opts)
end

-- Live Grep across all notes
--- @param opts table
function vault_pickers.live_grep(opts)
    local root_dir = config.options.root
    local screen_width = vim.api.nvim_list_uis()[1].width
    local screen_height = vim.api.nvim_list_uis()[1].height
    local default_opts = {
        prompt_title = "Search in notes",
        -- layout_strategy = "vertical",
        layout_config = {
            width = screen_width - 4,
            height = screen_height - 4,
            prompt_position = "top",
            preview_cutoff = 120,
        },
        cwd = root_dir,
        glob_pattern = "**/*.md",
        search = opts.query,
    }

    -- merge opts with default opts
    opts = vim.tbl_deep_extend("force", default_opts, opts or {})
    -- require("telescope.builtin").live_grep(opts)
    local picker = require("telescope.builtin").live_grep(opts)
    picker:find()
    return picker
end

-- --- Picker for browsing properties
-- --- It opens the picker with all properties of the current note
-- --- ```lua
-- --- local properties = vim.tbl_keys(require("vault.fetcher").properties())
-- --- ```
-- --- And then we can pick the property and see picker with values
-- --- ```lua
-- --- local property = vim.tbl_keys(require("vault.fetcher").properties()[selected_property]
-- --- ```
-- --- @param opts table
-- --- @param query? string[] - List of property names to show. If not provided, all properties will be shown.
-- function vault_pickers.properties(opts)
--     --- @type vault.Notes
--     local notes = require("vault.notes")()
--     --- @type table<string, table>
--     local properties = require("vault.fetcher").properties()
--
--     -- filter properties by query
--     if next(query) ~= nil then
--         local new_properties = {}
--         for _, property in ipairs(query) do
--             if properties[property] ~= nil then
--                 new_properties[property] = properties[property]
--             end
--         end
--         if next(new_properties) == nil then
--             vim.notify("No properties found")
--             return
--         end
--
--         properties = new_properties
--     end
--
--     --- @type string
--     local property_name -- "title"
--     --- @type string[]
--     local results = vim.tbl_keys(properties)
--
--     --- Enter callback
--     --- @param bufnr integer
--     local function enter(bufnr)
--         --- @type TelescopeEntry
--         local selection = actions_state.get_selected_entry()
--         --- @type table<string, table>
--         local values = properties[selection[1]]
--         property_name = selection[1]
--         results = vim.tbl_keys(values)
--
--         local function enter(bufnr)
--             --- @type TelescopeEntry
--             local selection = actions_state.get_selected_entry()
--             --- @type vault.Note.data.path[]
--             local sources = properties[property_name][selection[1]].sources
--             --- @type vault.Note.data.path[]
--             local paths = vim.tbl_keys(sources)
--
--             --- @type vault.Notes.map
--             notes.map = {}
--             for _, path in ipairs(paths) do
--                 local note = Note(path)
--                 notes:add_note(note)
--             end
--             vault_pickers.notes(opts)
--         end
--
--         local attach_mappings = function(_, map)
--             actions.select_default:replace(enter)
--             return true
--         end
--
--         pickers
--             .new({}, {
--                 prompt_title = selection[1],
--                 finder = finders.new_table({
--                     results = results,
--                     entry_maker = entry_maker,
--                 }),
--                 sorter = sorters.get_generic_fuzzy_sorter(),
--                 attach_mappings = attach_mappings,
--             })
--             :find()
--     end
--
--     local attach_mappings = function(_, map)
--         actions.select_default:replace(enter)
--         return true
--     end
--
--     pickers
--         .new({}, {
--             prompt_title = "Properties",
--             finder = finders.new_table({
--                 results = results,
--                 entry_maker = entry_maker,
--             }),
--             sorter = sorters.get_generic_fuzzy_sorter(),
--             attach_mappings = attach_mappings,
--         })
--         :find()
-- end -- [[@as fun(opts: table?): nil]]

--- Pick a property from the list.
--- @param opts table
--- @param properties vault.Properties - The properties to display in the picker.
--- @param callback function - A function to call with the selected property.
local function pick_property(opts, properties, callback)
    local results = vim.tbl_keys(properties.map)

    local function enter()
        local selection = actions_state.get_selected_entry()
        local property_name = selection[1]
        callback(property_name)
    end

    local attach_mappings = function()
        actions.select_default:replace(enter)
        return true
    end

    -- local entry_maker = function(entry)
    --     return {
    --         value = entry,
    --         ordinal = entry,
    --         display = make_display,
    --     }
    -- end

    local picker = pickers
        .new(opts, {
            prompt_title = "Properties",
            finder = finders.new_table({
                results = results,
                -- entry_maker = entry_maker,
            }),
            sorter = sorters.get_generic_fuzzy_sorter(),
            attach_mappings = attach_mappings,
        })
        :find()
    vault_state.set_global_key("picker", picker)
    return picker
end

--- Pick a value from the selected property.
--- @param opts table
--- @param property_name vault.Property.Data.name - The name of the selected property.
--- @param values vault.Property.Data.values - The values associated with the selected property.
--- @param callback function - A function to call with the selected value.
local function pick_value(opts, property_name, values, callback)
    local results = vim.tbl_keys(values)

    local function enter()
        local selection = actions_state.get_selected_entry()
        local value_name = selection[1]
        callback(value_name)
    end

    local attach_mappings = function()
        actions.select_default:replace(enter)
        return true
    end

    local make_display = function(entry)
        local entry_width = entry.value:len()
        local displayer = entry_display.create({
            separator = " ",
            items = {
                { width = entry_width },
                { remaining = true },
            },
        })
        local display_value = {
            -- entry.value,
            utils.path_to_relpath(entry.value),
            "TelescopeResultsNormal",
        }
        return displayer({
            display_value,
        })
    end

    local entry_maker = function(entry)
        return {
            value = entry,
            ordinal = entry,
            display = make_display,
        }
    end

    local picker = pickers
        .new(opts, {
            prompt_title = property_name,
            finder = finders.new_table({
                results = results,
                entry_maker = entry_maker,
            }),
            sorter = sorters.get_generic_fuzzy_sorter(),
            attach_mappings = attach_mappings,
        })
        :find()
    vault_state.set_global_key("picker", picker)
    return picker
end

--- @class telescope_popup_options.vault.properties: telescope_popup_options
--- @field query? string[] List of property names to show. If not provided, all properties will be shown.

--- @param opts? table
function vault_pickers.properties(opts)
    opts = opts or {}
    opts.query = opts.query or {}
    local notes = require("vault.notes")()
    -- local properties = require("vault.fetcher").properties()
    --- @type vault.Properties
    local properties = require("vault.properties")()

    -- Filter properties by query
    if next(opts.query) ~= nil then
        local filtered_properties = {}
        for _, property in ipairs(opts.query) do
            if properties.map[property] ~= nil then
                filtered_properties[property] = properties.map[property]
            end
        end
        if next(filtered_properties) == nil then
            vim.notify("No properties found")
            return
        end
        properties.map = filtered_properties
    end

    -- Handle property selection
    local function on_property_selected(property_name)
        local values = properties.map[property_name].data.values

        local function on_value_selected(value_name)
            local sources = properties.map[property_name].data.values[value_name].data.sources
            local paths = vim.tbl_keys(sources)

            notes.map = {}
            for _, path in ipairs(paths) do
                local note = Note(path)
                notes:add_note(note)
            end
            vault_pickers.notes(opts)
        end

        pick_value(opts, property_name, values, on_value_selected)
    end

    if vim.tbl_count(properties.map) == 1 then
        local property_name = vim.tbl_keys(properties.map)[1]
        on_property_selected(property_name)
    else
        pick_property(opts, properties, on_property_selected)
    end
end

--- @class telescope_popup_options.vault.dirs: telescope_popup_options
--- @field query? string[] List of property names to show. If not provided, all properties will be shown.

--- @param opts? table
function vault_pickers.dirs(opts)
    opts = opts or vault_layouts.mini()
    opts.query = opts.query or require("vault.fetcher").dirs()
    local action_state = require("telescope.actions.state")
    local picker = require("telescope.pickers").new({
        prompt_title = "Directories",
        finder = require("telescope.finders").new_table({
            results = vim.tbl_keys(opts.query),
        }),
        sorter = require("telescope.sorters").get_fzy_sorter(),
        attach_mappings = function(prompt_bufnr, _)
            actions.select_default:replace(function()
                local current_picker = action_state.get_current_picker(prompt_bufnr)
                local selection = current_picker:get_selection()
                actions.close(prompt_bufnr)
                require("vault.pickers").notes(
                    nil,
                    require("vault.notes")():with_relpath(selection.value, "startswith", false)
                )
            end)
            return true
        end,
    }, {})
    picker:find()
    return picker
end

return vault_pickers
