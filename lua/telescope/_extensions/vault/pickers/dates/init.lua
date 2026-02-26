--- @class telescope_popup_options.vault.Dates: telescope_popup_options
--- @field start_date? string Specifies the start date of the date range. Defaults: 7 days ago
--- @field end_date? string Specifies the end date of the date range. Defaults: today
--- Search for date and corresponding note
--- TODO: Add option to create note if it doesn't exist
--- TODO: Add option to configure date format
--- @return Picker
return function(opts)
    local config = require("vault.config")
    local utils = require("vault.utils")
    local actions = require("telescope.actions")
    local actions_state = require("telescope.actions.state")
    local entry_display = require("telescope.pickers.entry_display")
    local finders = require("telescope.finders")
    local pickers = require("telescope.pickers")
    local sorters = require("telescope.sorters")
    local previewers = require("telescope.previewers")
    local vault_state = require("vault.core.state")
    local Dates = require("dates")

    opts = opts or {}
    --- @type string
    opts.start_date = opts.start_date
        or tostring(os.date("%Y-%m-%d", os.time() - 365 * 24 * 60 * 60))
    --- @type string
    opts.end_date = opts.end_date or tostring(os.date("%Y-%m-%d"))

    local date_values = Dates.from_to(opts.start_date, opts.end_date)
    local daily_dir = config.dir("journal.daily")
    if not daily_dir then
        vim.notify("[vault] Journal daily directory not configured", vim.log.levels.WARN)
        return
    end

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
        vim.cmd("edit " .. vim.fn.fnameescape(path))
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

    local picker = pickers.new({}, {
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
    vault_state.set_global_key("picker", picker)
    return picker
end
