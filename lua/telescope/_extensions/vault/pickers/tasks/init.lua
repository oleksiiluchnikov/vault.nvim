--- @class telescope_popup_options.vault.Tasks: telescope_popup_options
--- @field tasks? table<string, table>
--- @return Picker
return function(opts)
    local vault_state = require("vault.core.state")
    local log = require("vault.log").scope("telescope")
    local entry_display = require("telescope.pickers.entry_display")
    local finders = require("telescope.finders")
    local pickers = require("telescope.pickers")
    local sorters = require("telescope.sorters")
    local vault_mappings = require("telescope._extensions.vault.mappings")
    local vault_hl = require("telescope._extensions.vault.highlights")
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

    local gradient_steps = DISPLAY_CONFIG.COLORS.GRADIENT.STEPS
    local hl_name = DISPLAY_CONFIG.HIGHLIGHT_GROUP
    local colors = vault_hl.setup(hl_name, gradient_steps, {
        DISPLAY_CONFIG.COLORS.GRADIENT.START,
        DISPLAY_CONFIG.COLORS.GRADIENT.END,
        DISPLAY_CONFIG.COLORS.GRADIENT.TYPE,
    })

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
        log.info("No tasks found in vault")
    end

    local make_display = function(entry)
        local task = entry.value
        local window_width = vim.api.nvim_list_uis()[1].width
        local status_info = DISPLAY_CONFIG.COLORS.STATUS[task.data.status]
            or { symbol = "?", hl = "Normal" }

        -- Calculate gradient for description
        local desc_hl = "TelescopeResultsNormal"
        if colors then
            local desc_length = task.data.description and #task.data.description or 0
            local gradient_idx = math.max(
                1,
                math.min(math.floor(desc_length / 16), gradient_steps)
            )
            desc_hl = hl_name .. gradient_idx
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
            { task.data.description or "", desc_hl },
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
        attach_mappings = vault_hl.make_attach_mappings(vault_mappings.tasks, hl_name, colors),
    })
    vault_state.set_global_key("picker", picker)
    return picker
end
