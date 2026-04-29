return function(opts)
    local finders = require("telescope.finders")
    local pickers = require("telescope.pickers")
    local sorters = require("telescope.sorters")
    local entry_display = require("telescope.pickers.entry_display")
    local vault_state = require("vault.core.state")
    local vault_registry = require("telescope._extensions.vault.pickers.registry")
    local vault_layouts = require("telescope._extensions.vault.layouts")
    opts = opts or {}

    local available_pickers = vault_registry.entries()

    -- Calculate optimal widths based on content
    local widths = {
        name = 0,
        description = 0,
    }

    -- Find maximum widths
    for _, picker in ipairs(available_pickers) do
        widths.name = math.max(widths.name, vim.fn.strdisplaywidth(picker.name))
        widths.description =
            math.max(widths.description, vim.fn.strdisplaywidth(picker.description))
    end

    -- Add some padding
    widths.name = widths.name + 2

    local results = available_pickers

    local make_display = function(entry)
        local displayer = entry_display.create({
            separator = " ",
            items = {
                { width = widths.name },
                { remaining = true },
            },
        })

        return displayer({
            { entry.value.name, "TelescopeResultsNormal" },
            { entry.value.description, "Comment" },
        })
    end

    local entry_maker = function(entry)
        return {
            value = entry,
            ordinal = entry.name,
            display = make_display,
        }
    end

    local finder = finders.new_table({
        results = results,
        entry_maker = entry_maker,
    })
    local number_of_pickers = vim.tbl_count(available_pickers) + 5

    opts = vim.tbl_deep_extend("force", opts, vault_layouts.mini())
    -- Calculate total width needed for the layout
    local total_width = widths.name + widths.description + 5 -- 5 for padding and separator

    opts = vim.tbl_deep_extend("force", opts, {
        layout_config = {
            height = number_of_pickers,
            width = math.min(total_width, math.floor(vim.o.columns * 0.8)), -- Cap at 80% of screen width
        },
        sorting_strategy = "ascending",
        results_title = false,
        border = true,
        borderchars = {
            prompt = { "─", "│", " ", "│", "╭", "╮", "│", "│" },
            results = { "─", "│", "─", "│", "├", "┤", "╯", "╰" },
        },
    })

    local picker = pickers.new(opts, {
        prompt_title = "",
        finder = finder,
        sorter = sorters.get_fzy_sorter(),
        attach_mappings = require("telescope._extensions.vault.mappings").vault,
    })
    vault_state.set_global_key("picker", picker)
    return picker
end
