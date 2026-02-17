--- @class telescope_popup_options.vault.Tasks: telescope_popup_options
--- @field tasks? table<string, table>
--- @return Picker
return function(opts)
    local vault_state = require("vault.core.state")
    local Log = require("plenary.log")
    local Error = require("vault.utils.error")
    local entry_display = require("telescope.pickers.entry_display")
    local finders = require("telescope.finders")
    local pickers = require("telescope.pickers")
    local sorters = require("telescope.sorters")
    local actions = require("telescope.actions")
    local actions_state = require("telescope.actions.state")
    local utils = require("vault.utils")
    local vault_previewers = require("telescope._extensions.vault.previewers")
    local vault_mappings = require("telescope._extensions.vault.mappings")
    local vault_layouts = require("telescope._extensions.vault.layouts")
    local task_picker_actions = require("telescope._extensions.vault.pickers.tasks.actions")
    --- Constants for task display configuration
    local DISPLAY_CONFIG = {
        WIDTHS = {
            STATUS = 1, -- For the status symbol
            ID = 10,
            REPEAT = 50,
            DATE = 10, -- For created, due, start, schedule, completed
            PRIORITY = 3,
            SEPARATOR = 2, -- Space between columns
        },
        COLORS = {
            GRADIENT = {
                STEPS = vim.api.nvim_list_uis()[1].height,
                START = "Comment",
                END = "Normal",
                TYPE = "String",
            },
            STATUS = {
                ["-"] = { symbol = "⊖", hl = "DiagnosticWarn" }, -- PENDING
                ["x"] = { symbol = "⊗", hl = "DiagnosticOk" }, -- DONE
                [" "] = { symbol = "⊙", hl = "DiagnosticHint" }, -- TODO
                ["/"] = { symbol = "⊘", hl = "DiagnosticInfo" }, -- IN PROGRESS
            },
        },
        HIGHLIGHT_GROUP = "VaultTask",
    }

    --- Track whether gradient colors were successfully set up
    local gradient_available = false

    --- Setup gradient colors for tasks display
    --- @return boolean success
    local function setup_task_colors()
        if vim.b.vault_task_colors_initialized then
            gradient_available = true
            return true
        end

        local display_config = DISPLAY_CONFIG.COLORS.GRADIENT
        local ok, colors = pcall(function()
            local Gradient = require("gradient")
            return Gradient.from_stops(
                display_config.STEPS,
                display_config.START,
                display_config.END,
                display_config.TYPE
            )
        end)

        if not ok or type(colors) ~= "table" then
            gradient_available = false
            return false
        end

        for i, color in ipairs(colors) do
            pcall(vim.api.nvim_set_hl, 0, DISPLAY_CONFIG.HIGHLIGHT_GROUP .. i, { fg = color })
        end

        gradient_available = true
        vim.b.vault_task_colors_initialized = true
        return true
    end

    --- Right align text in a fixed width
    --- @param text string|nil Text to align
    --- @param width integer Width to align within
    --- @return string
    local function right_align(text, width)
        text = text or ""
        return string.rep(" ", width - #text) .. text
    end

    --- Calculate description width based on window and other columns
    --- @param window_width integer Full window width
    --- @return integer desc_width
    local function calculate_desc_width(window_width)
        local widths = DISPLAY_CONFIG.WIDTHS

        local desc_width = window_width
            - widths.STATUS
            - widths.ID
            - widths.REPEAT
            - (widths.DATE * 5)
            - widths.PRIORITY
            - (widths.SEPARATOR * 8)

        local max_desc_width = 160
        if desc_width > max_desc_width then
            desc_width = max_desc_width
        end
        return desc_width
    end
    opts = opts or {}
    opts.tasks = opts.tasks or require("vault.tasks")()
    local tasks_list = opts.tasks:list()

    if next(tasks_list) == nil then
        Log.info("No tasks found in vault")
    end

    local function enter(bufnr)
        local selection = actions_state.get_selected_entry()
        actions.close(bufnr)
        vim.cmd(string.format("edit +%d %s", selection.value.line_number, selection.filename))
    end

    local make_display = function(entry)
        setup_task_colors()

        local task = entry.value
        local window_width = vim.api.nvim_list_uis()[1].width
        -- local status_info = DISPLAY_CONFIG.COLORS.`STATUS[task.status]` or { symbol = "?", hl = "Normal" }
        local status_info = DISPLAY_CONFIG.COLORS.STATUS[task.data.status]
            or { symbol = "?", hl = "Normal" }

        -- Calculate gradient for description
        local desc_hl = "TelescopeResultsNormal"
        if gradient_available then
            local desc_length = #task.data.description
            local gradient_idx = math.max(
                1,
                math.min(math.floor(desc_length / 16), DISPLAY_CONFIG.COLORS.GRADIENT.STEPS)
            )
            desc_hl = DISPLAY_CONFIG.HIGHLIGHT_GROUP .. gradient_idx
        end

        local displayer = entry_display.create({
            separator = string.rep(" ", DISPLAY_CONFIG.WIDTHS.SEPARATOR),
            items = {
                { width = DISPLAY_CONFIG.WIDTHS.STATUS }, -- Status symbol
                { width = calculate_desc_width(window_width) }, -- Description
                { width = DISPLAY_CONFIG.WIDTHS.ID }, -- ID
                { width = DISPLAY_CONFIG.WIDTHS.REPEAT }, -- Repeat
                { width = DISPLAY_CONFIG.WIDTHS.DATE }, -- Created
                { width = DISPLAY_CONFIG.WIDTHS.DATE }, -- Due
                { width = DISPLAY_CONFIG.WIDTHS.DATE }, -- Start
                { width = DISPLAY_CONFIG.WIDTHS.DATE }, -- Schedule
                { width = DISPLAY_CONFIG.WIDTHS.DATE }, -- Completed
                { width = DISPLAY_CONFIG.WIDTHS.PRIORITY }, -- Priority
            },
        })

        return displayer({
            { status_info.symbol, status_info.hl },
            { task.data.description, desc_hl },
            { right_align(task.data.id, DISPLAY_CONFIG.WIDTHS.ID), "Comment" },
            { right_align(task.data.due, DISPLAY_CONFIG.WIDTHS.DATE), "Repeat" },
            { right_align(task.data.created, DISPLAY_CONFIG.WIDTHS.DATE), "Special" },
            { right_align(task.data.due, DISPLAY_CONFIG.WIDTHS.DATE), "WarningMsg" },
            { right_align(task.data.start, DISPLAY_CONFIG.WIDTHS.DATE), "Type" },
            { right_align(task.data.schedule, DISPLAY_CONFIG.WIDTHS.DATE), "String" },
            { right_align(task.data.completed, DISPLAY_CONFIG.WIDTHS.DATE), "DiagnosticOk" },
            { right_align(task.data.priority, DISPLAY_CONFIG.WIDTHS.PRIORITY), "Error" },
        })
    end

    local entry_maker = function(task)
        return {
            value = task,
            ordinal = task.data.line,
            display = make_display,
            -- display = task.data.line:gsub("^%s*(.-)%s*$", "%1"):gsub("^-%s*%[.]%s*", ""),
            -- filename = config.options.root
            --     .. "/"
            --     .. task.data.sources[1].slug
            --     .. config.options.ext,
        }
    end

    local picker = pickers.new({}, {
        prompt_title = "Tasks",
        finder = finders.new_table({
            results = tasks_list,
            entry_maker = entry_maker,
        }),
        sorter = sorters.get_generic_fuzzy_sorter(),
        sorting_strategy = "ascending",
        layout_config = {
            height = vim.api.nvim_list_uis()[1].height - 4,
            width = vim.api.nvim_list_uis()[1].width,
        },
        attach_mappings = function(_, _)
            actions.select_default:replace(task_picker_actions.enter)
            return true
        end,
    })
    vault_state.set_global_key("picker", picker)
    return picker
end
