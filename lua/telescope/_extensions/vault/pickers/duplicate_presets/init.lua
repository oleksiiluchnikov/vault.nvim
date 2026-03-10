return function(opts)
    opts = opts or {}
    local presets = opts.presets or {}
    if vim.tbl_isempty(presets) then
        return nil
    end

    local actions = require("telescope.actions")
    local action_state = require("telescope.actions.state")
    local entry_display = require("telescope.pickers.entry_display")
    local finders = require("telescope.finders")
    local pickers = require("telescope.pickers")
    local sorters = require("telescope.sorters")
    local vault_layouts = require("telescope._extensions.vault.layouts")
    local vault_state = require("vault.core.state")

    local widths = {
        name = 0,
        description = 0,
    }
    for _, preset in ipairs(presets) do
        widths.name = math.max(widths.name, vim.fn.strdisplaywidth(preset.name or ""))
        widths.description =
            math.max(widths.description, vim.fn.strdisplaywidth(preset.description or ""))
    end
    widths.name = widths.name + 2
    widths.description = widths.description + 2

    local function make_display(entry)
        local displayer = entry_display.create({
            separator = " ",
            items = {
                { width = widths.name },
                { width = widths.description },
                { remaining = true },
            },
        })

        return displayer({
            { entry.value.name, "TelescopeResultsIdentifier" },
            { entry.value.description or "", "Comment" },
            { entry.value.summary or "", "TelescopeResultsComment" },
        })
    end

    local picker = pickers.new(vault_layouts.mini(), {
        prompt_title = "Duplicate Review Presets",
        finder = finders.new_table({
            results = presets,
            entry_maker = function(entry)
                return {
                    value = entry,
                    ordinal = table.concat(
                        { entry.name or "", entry.description or "", entry.summary or "" },
                        " "
                    ),
                    display = make_display,
                }
            end,
        }),
        sorter = sorters.get_fzy_sorter(),
        attach_mappings = function(prompt_bufnr)
            actions.select_default:replace(function()
                actions.close(prompt_bufnr)
                local selection = action_state.get_selected_entry()
                if selection and opts.on_select then
                    opts.on_select(selection.value)
                end
            end)
            return true
        end,
    })

    vault_state.set_global_key("picker", picker)
    return picker
end
