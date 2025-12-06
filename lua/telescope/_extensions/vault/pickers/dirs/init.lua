--- @class telescope_popup_options.vault.dirs: telescope_popup_options
--- @field query? string[] List of property names to show. If not provided, all properties will be shown.

--- @param opts? table
--- @return Picker
return function(opts)
    local dirs = require("vault.dirs")()
    local utils = require("vault.utils")
    local entry_display = require("telescope.pickers.entry_display")
    local finders = require("telescope.finders")
    local sorters = require("telescope.sorters")
    local vault_state = require("vault.core.state")
    local Gradient = require("gradient")
    local Scanner = require("vault.scanner")
    local pickers = require("telescope.pickers")
    local vault_layouts = require("telescope._extensions.vault.layouts")

    opts = opts or {}

    local dirs_list = dirs:list()
    if next(dirs_list) == nil then
        require("plenary.log").info("No properties found in vault")
    end

    local steps = math.min(vim.api.nvim_list_uis()[1].height, vim.tbl_count(dirs_list))
    --- @type Gradient|nil
    local colors = Gradient.from_stops(steps, "Comment", "Normal", "String")
    if type(colors) ~= "table" then
        -- error(
        --     error_msg.COMMAND_EXECUTION_ERROR("Gradient.from_stops", "table", vim.inspect(colors))
        -- )
        -- error("Gradient.from_stops", "table", vim.inspect(colors))
        error("Gradient.from_stops")
    end
    local hl_name = dirs.class.name
    for i, color in ipairs(colors) do
        vim.api.nvim_set_hl(0, hl_name .. tostring(i), { fg = color })
    end

    local slugs = Scanner.slugs()

    --- @param entry vault.TelescopeEntry
    local make_display = function(entry)
        --- @type vault.Dir
        local directory = entry.value
        -- local sources_count =
        --     -- require("vault.notes")():filter("relpath",directory, "startswith", false):count()
        --     notes:filter('slug',directory, "startswith", false):count()
        local sources_count = 0
        for slug, _ in pairs(slugs) do
            if utils.match(slug, directory.data.relpath, "startswith", false) then
                sources_count = sources_count + 1
            end
        end

        --- --
        local col_1 = directory.data.relpath
        local col_1_width = 29
        local i = math.min(math.floor(sources_count / 2), steps)
        if i == 0 then
            i = 1
        end
        local col_1_hl_name = hl_name .. tostring(i)
        --- --

        local col_2 = tostring(sources_count)
        local col_2_width = #col_2
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

    --- @param directory vault.Dir
    --- @return vault.TelescopeEntry
    local entry_maker = function(directory)
        return {
            value = directory,
            -- ordinal = property.data.name .. " " .. tostring(property.data.count),
            ordinal = directory.data.relpath,
            display = make_display,
        }
    end

    local finder = finders.new_table({
        results = dirs_list,
        entry_maker = entry_maker,
    })

    opts.sort_by = opts.sort_by or "count"

    if opts.sort_by == "count" then
        -- sort by count of notes in directory
        table.sort(dirs_list, function(a, b)
            a = a.data.relpath
            b = b.data.relpath
            local a_count = 0
            for slug, _ in pairs(slugs) do
                if utils.match(slug, a, "startswith", false) then
                    a_count = a_count + 1
                end
            end
            a_count = a_count * 100
            local b_count = 0
            for slug, _ in pairs(slugs) do
                if utils.match(slug, b, "startswith", false) then
                    b_count = b_count + 1
                end
            end
            b_count = b_count * 100
            return a_count > b_count
        end)
    elseif opts.sort_by == "name" then
        table.sort(dirs_list, function(a, b)
            a = a.data.name or ""
            b = b.data.name or ""
            -- if underscore is first letter, put it at the top
            if b:sub(1, 1) == "_" then
                return false
            elseif a:sub(1, 1) == "_" then
                return true
            end
            return a < b
        end)
    end

    local on_input_filter_cb = function(prompt)
        local picker = vault_state.get_global_key("picker")
        if picker == nil then
            vim.notify("No picker found")
            return
        end
        local is_negative = false

        local function default_finder()
            local new_finder = finders.new_table({
                results = dirs_list,
                entry_maker = entry_maker,
            })

            picker.finder:close() -- TODO: Find a way to close picker without closing previewer
            picker.finder = new_finder

            vault_state.set_global_key("prompt", prompt)
            return {
                prompt = prompt or "",
            }
        end

        if prompt:sub(-1) ~= "/" then
            return default_finder()
        end

        if prompt:sub(1, 1) == "-" then
            is_negative = true
        end

        local pattern = prompt:sub(1, -2)
        pattern = pattern:sub(2)
        if is_negative == true then
            pattern = pattern:sub(2)
        end
        local new_results = {}
        local results_without_excluded = {}

        for _, entry in ipairs(picker.finder.results) do
            local slug = entry.value
            local is_valid_regex = pcall(vim.fn.match, slug, pattern)
            if is_valid_regex == false then
                goto continue
            end
            if vim.fn.match(slug, pattern) ~= -1 then
                table.insert(new_results, slug)
                if is_negative == true then
                    table.insert(results_without_excluded, slug)
                end
            end
            ::continue::
        end
        if next(new_results) == nil then
            return default_finder()
        elseif is_negative == true then
            new_results = {}
            for _, entry in ipairs(picker.finder.results) do -- TODO: Use results_without_excluded
                if not vim.tbl_contains(results_without_excluded, entry.value) then
                    table.insert(new_results, entry.value)
                end
            end
        end

        local new_finder = finders.new_table({
            results = new_results,
            entry_maker = entry_maker,
        })
        picker.finder:close()
        picker.finder = new_finder

        vault_state.set_global_key("prompt", prompt)

        return {
            prompt = "",
        }
    end

    local picker = pickers.new(vault_layouts.mini(), {
        prompt_title = "Directories",
        finder = finder,
        sorter = sorters.get_fzy_sorter(),
        on_input_filter_cb = on_input_filter_cb,
        attach_mappings = function(_, map)
            local dirs_picker_actions = require("telescope._extensions.vault.pickers.vault.actions")
            local actions = require("telescope.actions")

            -- select all entries in the picker
            map("i", "<CR>", dirs_picker_actions.enter)
            map("n", "<CR>", dirs_picker_actions.enter)

            -- select all entries in the picker
            map("i", "<C-a>", actions.select_all)
            map("n", "<C-a>", actions.select_all)

            map("i", "<C-d>", actions.drop_all)
            map("n", "<C-d>", actions.drop_all)

            return true
        end,
    })

    vault_state.set_global_key("picker", picker)
    return picker
end
