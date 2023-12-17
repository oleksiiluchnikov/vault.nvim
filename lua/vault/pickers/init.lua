local vault_pickers = {}
local fetcher = require("vault.fetcher")

local Log = require("plenary.log")
local Gradient = require("gradient")

local pickers = require("telescope.pickers")
local finders = require("telescope.finders")
local sorters = require("telescope.sorters")
local previewers = require("telescope.previewers")
local actions = require("telescope.actions")
local actions_state = require("telescope.actions.state")
local entry_display = require("telescope.pickers.entry_display")
---@type VaultConfig|VaultConfig.options
local config = require("vault.config")
local utils = require("vault.utils")
local error_formatter = require("vault.utils.error_formatter")

-- local Notes = require("vault.notes")
local Tags = require("vault.tags")
local Note = require("vault.notes.note")

local Layouts = require("vault.pickers.layouts")

--- Attach hl groups to vim
---@param name string @Name of hl group
---@param colors VaultArray.colors -- Array of colors
---@return table @ns_id and hl_groups
local function attach_hl_groups(name, colors)
    local hl_group_prefix = "Vault" .. name .. "Level"
    local hl_groups = {}
    for i, color in ipairs(colors) do
        local i_str = tostring(i)
        vim.api.nvim_set_hl(0, hl_group_prefix .. i_str, {
            fg = color,
        })
        table.insert(hl_groups, hl_group_prefix .. i_str)
    end
    return hl_groups
end

local function detach_hl_groups(hl_groups)
    for _, hl_group in ipairs(hl_groups) do
        vim.api.nvim_set_hl(0, hl_group, {})
    end
end

--- Open notes picker
---@param opts table?
---@param filter_opts VaultFilter.option|VaultFilter? -- Optional `VaultFilter` instance to use
---@param notes VaultNotes? -- Optional `VaultNotes` instance to use
function vault_pickers.notes(opts, filter_opts, notes)
    local Notes = require("vault.notes")
    opts = opts or {}
    -- notes = notes or Notes(filter_opts)
    if not notes then
        if filter_opts then
            notes = Notes():filter(filter_opts)
        else
            notes = Notes()
        end
    end
    local notes_list = notes:list()
    if next(notes_list) == nil then
        Log.info("No notes found in vault")
        return
    end

    -- prompt title

    ---@type number
    local average_content_length = notes:average_chars()
    average_content_length = math.floor(average_content_length)

    local prompt_title = ""

    if filter_opts then
        if filter_opts.by and #filter_opts.by == 1 then
            prompt_title = prompt_title
                .. " with "
                .. filter_opts.mode
                .. " "
                .. filter_opts.by[1]
                .. " "
                .. filter_opts.match_opt
        elseif filter_opts.by then
            prompt_title = prompt_title .. table.concat(filter_opts.by, " ")
        end

        --- Append include and exclude filters to prompt title
        ---@param tbl string[]
        ---@param s string
        local function append_list_info(tbl, s)
            if tbl and #tbl > 0 then
                prompt_title = prompt_title .. " " .. s .. ":"
                for _, v in ipairs(tbl) do
                    prompt_title = prompt_title .. " [" .. v .. "]"
                end
            end
        end

        append_list_info(filter_opts.include, "including")
        append_list_info(filter_opts.exclude, "excluding")

        if average_content_length then
            prompt_title = prompt_title .. " " .. tostring(average_content_length)
        end
    end

    -- entry maker
    local steps = 64
    local gradient_colors = Gradient.from_stops(steps, "Boolean", "#444444", "#a9a9a9", "String")

    local hl_groups = attach_hl_groups("NoteContent", gradient_colors)

    ---found the longest location_path and set it as width
    ---so we can have nice alignment
    local location_path_width = 0
    for _, note in ipairs(notes_list) do
        local location_path = ""
        local relpath = note.data.relpath
        if relpath:find("/") ~= nil then
            location_path =
                relpath:sub(1, relpath:len() - vim.fn.fnamemodify(note.data.path, ":t"):len() - 1)
        end
        local location_path_length = location_path:len()
        if location_path_length > location_path_width then
            location_path_width = location_path_length
        end
    end

    local function make_display(entry)
        local basename = vim.fn.fnamemodify(entry.value.data.path, ":t:r")
        local basename_hl_group = "TelescopeResultsNormal"

        local content = entry.value.data.content

        if content then
            local content_chars_count = #content
            local index = math.min(math.floor(content_chars_count / 16), steps)
            if index == 0 then
                index = 1
            end
            basename_hl_group = hl_groups[index]
        end

        local location_path = ""
        if entry.value.data.relpath:find("/") ~= nil then
            location_path = entry.value.data.relpath:sub(
                1,
                entry.value.data.relpath:len()
                    - vim.fn.fnamemodify(entry.value.data.path, ":t"):len()
                    - 1
            )
        end

        local location_path_hl_group = "TelescopeResultsComment"

        local displayer = entry_display.create({
            separator = " ",
            items = {
                { width = 2 },
                { width = location_path_width },
                { remaining = true },
                { remaining = true },
            },
        })

        local display_value = {
            { "██", basename_hl_group },
            { location_path, location_path_hl_group },
            { basename, basename_hl_group },
        }

        return displayer(display_value)
    end

    local function entry_maker(note)
        return {
            value = note,
            ordinal = note.data.relpath,
            display = make_display,
            filename = note.data.path,
        }
    end

    local finder = finders.new_table({
        results = notes_list,
        entry_maker = entry_maker,
    })

    -- previewer
    local previewer = previewers.vim_buffer_cat.new({
        get_buffer_by_name = function(_, entry)
            local bufnr = vim.api.nvim_create_buf(false, true)
            if type(bufnr) ~= "number" then
                error("bufnr is not a number")
            end
            local lines = vim.fn.readfile(entry.filename)
            vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
            vim.api.nvim_buf_set_option(bufnr, "filetype", "markdown")
            return bufnr
        end,
    })

    -- attach mappings
    local function close(bufnr)
        actions.close(bufnr)
        -- clean up hl groups
        detach_hl_groups(hl_groups)
    end

    local function enter(bufnr)
        local selection = actions_state.get_selected_entry()
        local path = selection.filename
        close(bufnr)
        vim.cmd("edit " .. path)
    end

    local function attach_mappings(_, map)
        actions.select_default:replace(enter)
        map("i", "<C-c>", close)
        map("n", "<C-c>", close)
        return true
    end

    pickers
        .new(Layouts.notes(), {
            prompt_title = prompt_title,
            finder = finder,
            sorter = sorters.get_generic_fuzzy_sorter(),
            previewer = previewer,
            attach_mappings = attach_mappings,
        })
        :find()
end

--- Search for tags
---@param opts table?
---@param filter_opts table?
function vault_pickers.tags(opts, filter_opts)
    opts = opts or {}

    local tags = Tags(filter_opts)

    if next(tags) == nil then
        Log.info("No tags found in vault")
        return
    end

    ---@type VaultTag[]
    local tags_list = tags:list()

    -- sort tags by notes count
    table.sort(tags_list, function(a, b)
        local a_count = a.data.count
        local b_count = b.data.count
        return a_count > b_count
    end)

    -- prompt title
    local prompt_title = "Tags"

    -- entry maker
    local steps = 64
    local colors = Gradient.from_stops(steps, "#444444", "#a9a9a9", "String")
    local hl_groups = attach_hl_groups("Tag", colors)

    local make_display = function(entry)
        local entry_width = 29
        local tag = entry.value
        local notes_length = tag.data.count
        local count_length = tostring(notes_length):len() + 1
        local displayer = entry_display.create({
            separator = " ",
            items = {
                { width = entry_width },
                { remaining = true },
                { width = count_length },
                { remaining = true },
            },
        })
        local tag_name = tag.data.name
        local index = math.min(math.floor(notes_length / 2), steps)
        if index == 0 then
            index = 1
        end
        local hl_group = hl_groups[index]

        return displayer({
            { tag_name, hl_group },
            { tostring(notes_length), "TelescopeResultsNumber" },
        })
    end

    local function entry_maker(tag)
        local tag_name = tag.data.name

        local notes_paths_count = tag.data.count

        if notes_paths_count == 0 then
            error("No notes found for tag: " .. vim.inspect(tag))
        end

        return {
            value = tag,
            ordinal = tag_name .. " " .. tostring(notes_paths_count),
            display = make_display,
        }
    end

    local finder = finders.new_table({
        results = tags_list,
        entry_maker = entry_maker,
    })

    local previewer = previewers.new_buffer_previewer({
        ---@param self table
        ---@param entry { value: VaultTag }
        define_preview = function(self, entry)
            local tag = entry.value
            ---@type VaultMap.sources
            local sources = tag.data.sources

            ---@type string[]
            local lines = {}
            local documentation = tag.data.documentation:content(tag.data.name)
            if documentation then
                local doc_lines = vim.split(documentation, "\n")
                for _, doc_line in ipairs(doc_lines) do
                    table.insert(lines, doc_line)
                end
                local separator = string.rep("-", 80)
                table.insert(lines, separator)
            end

            local seen_notes_paths = {}
            for slug, _ in pairs(sources) do
                local note = Note({
                    path = config.root .. "/" .. slug .. config.ext,
                })
                if not seen_notes_paths[note.data.relpath] then
                    seen_notes_paths[note.data.relpath] = true
                    table.insert(lines, note.data.relpath)
                end
            end
            local bufnr = self.state.bufnr
            if type(bufnr) ~= "number" then
                error(error_formatter.invalid_type(bufnr, "number"))
            end
            vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
            vim.api.nvim_buf_set_option(bufnr, "filetype", "markdown")
            return vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
        end,
    })

    local function close(bufnr)
        actions.close(bufnr)
        detach_hl_groups(hl_groups)
    end

    local function enter(bufnr)
        local selection = actions_state.get_selected_entry()
        -- local notes_paths = selection.value.data.notes_paths
        -- local notes = {}
        -- for _, note_path in ipairs(notes_paths) do
        -- 	local note = Note({
        -- 		path = note_path,
        -- 	})
        -- 	table.insert(notes, note)
        -- end
        close(bufnr)
        vault_pickers.notes({}, { "tags", { selection.value.data.name }, {}, "exact", "all" })
    end

    local function edit_documentation(bufnr)
        local selection = actions_state.get_selected_entry()
        close(bufnr)
        local tag = selection.value
        if tag.data.documentation then
            tag.data.documentation:open()
        end
    end

    local function attach_mappings(_, map)
        actions.select_default:replace(enter)
        map("i", "<C-e>", edit_documentation)
        return true
    end

    pickers
        .new(Layouts.tags(), {
            prompt_title = prompt_title,
            finder = finder,
            sorter = sorters.get_generic_fuzzy_sorter(),
            previewer = previewer,
            attach_mappings = attach_mappings,
        })
        :find()
end

--- I want to browse tag until it has no more nesting,
---and then return to full tag name like: status/TODO/later
---and then pick with tags { status/TODO/later} for example
--- For example we have tag: software/Blender/extensions
function vault_pickers.notes_by(tag_prefix) -- software or software/Blender(if we selected software)
    if tag_prefix == nil then
        return
    end
    local root_dir = config.root
    local tags = require("vault"):tags(tag_prefix) -- get all tags with prefix
    if #tags == 0 then
        -- if we selected software/Blender and there is no tags with prefix software/Blender
        -- then we have no more nesting and we need to return to full tag name
        -- our pick._cache.parent_tag will be software/Blender/software/Blender/extensions
        local parent_tag = vault_pickers._cache.parent_tag
        if parent_tag == "" then
            return
        end
        local tag_name = parent_tag:gsub(tag_prefix .. "/", "") -- now we have software/Blender/extensions
        vim.notify(tag_name)
        vault_pickers._cache.parent_tag = "" -- reset parent_tag
        vault_pickers.notes_filter_by_tags({ tag_name }) -- now we have { software/Blender/extensions }
        return
    end

    local entries = {}
    for _, tag in ipairs(tags) do
        local entry = tag.name -- now we have software/Blender/extensions if we selected software
        -- if we selected software/Blender we need to remove software/Blender from entry
        if tag_prefix ~= "" then
            entry = entry:gsub(tag_prefix .. "/", "") -- now we have extensions
        end
        if entry ~= "" then
            table.insert(entries, entry)
        end
    end

    if #entries == 0 then
        Log.error("No notes found in vault: " .. root_dir)
        return
    end

    local function enter(bufnr)
        local selection = actions_state.get_selected_entry()
        local tag = selection[1]
        actions.close(bufnr)

        ---if we selected software/Blender we need to save it to cache and remove software/Blender from tag value to left only extensions
        ---our pick._cache.parent_tag should be updated and conain software/Blender/extensions
        ---and then we can pick with tags { software/Blender/extensions }
        if vault_pickers._cache.parent_tag ~= tag_prefix .. "/" .. tag then
            vault_pickers._cache.parent_tag = tag_prefix .. "/" .. tag
            vault_pickers.notes_by(tag_prefix .. "/" .. tag)
            return
        end
    end

    pickers
        .new(Layouts.mini(), {
            prompt_title = "Status",
            finder = finders.new_table(entries),
            sorter = sorters.get_generic_fuzzy_sorter(),
            attach_mappings = function(_, _)
                actions.select_default:replace(enter)
                return true
            end,
        })
        :find()
end

--- Picker for browsing tags from root tag.
--- For example we have tag: status/TODO/later
--- We want to browse it like this:
---status
---status/TODO
---status/TODO/later
--- And then pick we open notes picker filtered by tag: status/TODO/later
---@param root_tag_name string? - Root tag to start browsing from
function vault_pickers.root_tags(root_tag_name)
    local root_dir = config.root
    local tags = {}
    if root_tag_name ~= nil then
        tags = Tags():by(root_tag_name)
    else
        tags = Tags()
    end

    if next(tags) == nil then
        Log.info("No root tags found in vault: " .. root_dir)
        return
    end

    local root_tags = {}
    local seen_root_tags = {}
    for _, tag in ipairs(tags) do
        local _root_tag_name = tag.name:match("([^/]+)")
        if not seen_root_tags[_root_tag_name] then
            seen_root_tags[_root_tag_name] = true
            table.insert(root_tags, _root_tag_name)
        end
    end

    local function make_display(entry)
        local entry_width = 29
        local displayer = entry_display.create({
            separator = " ",
            items = {
                { width = entry_width },
                { remaining = true },
            },
        })
        local tag_name = entry.name
        return displayer({
            { tag_name, "TelescopeResultsNormal" },
        })
    end

    local function entry_maker(tag)
        return {
            value = tag,
            ordinal = tag,
            display = make_display,
        }
    end

    local function enter(bufnr)
        local selection = actions_state.get_selected_entry()
        local root_tag = selection.value
        vault_pickers.root_tags(root_tag)
        actions.close(bufnr)
    end

    pickers
        .new(Layouts.mini(), {
            prompt_title = "Status",
            finder = finders.new_table({
                results = root_tags,
                entry_maker = entry_maker,
            }),
            sorter = sorters.get_generic_fuzzy_sorter(),
            attach_mappings = function(_, _)
                actions.select_default:replace(enter)
                return true
            end,
        })
        :find()
end

--- Search for date and corresponding note
---@param date_start string? @Date in format YYYY-MM-DD
---@param date_end string? @Date in format YYYY-MM-DD
function vault_pickers.dates(date_start, date_end)
    date_end = date_end or tostring(os.date("%Y-%m-%d"))
    -- date_start or os.date("%Y-%m-%d") - 7 days
    date_start = date_start or tostring(os.date("%Y-%m-%d", os.time() - 7 * 24 * 60 * 60))

    local Dates = require("dates")

    local root_dir = config.root
    local daily_dir = root_dir .. "/" .. config.dirs.journal.root .. "/Daily"

    local date_values = Dates.from_to(date_start, date_end)

    local dates = {}
    for _, date in ipairs(date_values) do
        local date_with_weekday = date .. " " .. Dates.get_weekday(date)
        date = {}
        date.value = date_with_weekday
        date.path = daily_dir .. "/" .. date_with_weekday .. ".md"
        date.relpath = utils.path_to_relpath(date.path)
        date.basename = vim.fn.fnamemodify(date.path, ":t")
        date.exists = vim.fn.filereadable(date.path) == 1
        table.insert(dates, date)
    end

    -- reverse dates
    local reversed_dates = {}
    for i = #dates, 1, -1 do
        table.insert(reversed_dates, dates[i])
    end
    dates = reversed_dates

    local function enter(bufnr)
        local selection = actions_state.get_selected_entry()
        local path = selection.value.path
        local content = "# " .. selection.value.name .. "\n"
        actions.close(bufnr)
        vim.cmd("edit " .. path)
        if selection.value.exists == false then
            vim.api.nvim_buf_set_lines(0, 0, -1, false, vim.split(content, "\n"))
            vim.cmd("normal! Go")
        end
    end

    local results_height = #dates + 5
    local results_width = 0

    for _, date in ipairs(dates) do
        -- Find the longest date
        local date_width = date.value:len()
        if date_width > results_width then
            results_width = date_width
        end
    end

    results_width = results_width + 2
    local bufwidth = vim.api.nvim_get_option("columns") - 20

    local preview_width = bufwidth - results_width - 3

    local entry_width = 29

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

    pickers
        .new({}, {
            prompt_title = "Dates",
            finder = finders.new_table({
                results = dates,
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
                    vim.api.nvim_buf_set_option(bufnr, "filetype", "markdown")
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
end

function vault_pickers.wikilinks()
    local Wikilinks = require("vault.wikilinks")
    local wikilinks = Wikilinks()
    local results = wikilinks:list()
    -- print(vim.inspect(results))

    ---@param entry table
    local function make_display(entry)
        ---@type VaultWikilink
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

    local function entry_maker(entry)
        return {
            value = entry,
            ordinal = entry.data.slug,
            display = make_display,
        }
    end

    pickers
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
end

--- TODO: Make action that will search for notes with similar tags that selected note has
--- If we have note with tags: status/TODO, class/Action, class/Action/Project
--- We could search for notes containing tags: status/TODO, class/Action, class/Action/Project
--- With mode "all" or "any"

--- Search for notes in Inbox directory
function vault_pickers.inbox()
    local inbox_dir = config.dirs.inbox

    local notes = {}
    for _, note_path in ipairs(vim.fn.globpath(inbox_dir, "**/*" .. config.ext, true, true)) do
        local note = Note({
            path = note_path,
        })
        table.insert(notes, note)
    end

    vault_pickers.notes({}, notes)
end

function vault_pickers.tasks()
    local tasks = fetcher.tasks()
    -- print(vim.inspect(tasks))
    local results = {}
    for slug, map in pairs(tasks) do
        for line_number, task in pairs(map) do
            if task.status == "[x]" then
                goto continue
            end
            local task = {
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

        local full_width = vim.api.nvim_get_option("columns")
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

    local function entry_maker(entry)
        return {
            value = entry,
            ordinal = entry.line:match("%s*(.*)"),
            display = make_display,
            filename = config.root .. "/" .. entry.slug .. config.ext,
        }
    end

    pickers
        .new({}, {
            prompt_title = "Tasks",
            finder = finders.new_table({
                results = results,
                entry_maker = entry_maker,
            }),
            sorter = sorters.get_generic_fuzzy_sorter(),
            sorting_strategy = "ascending",
            layout_config = {
                height = vim.api.nvim_get_option("lines") - 4,
                width = vim.api.nvim_get_option("columns"),
            },
            attach_mappings = function(_, _)
                actions.select_default:replace(enter)
                return true
            end,
        })
        :find()
end

return vault_pickers
