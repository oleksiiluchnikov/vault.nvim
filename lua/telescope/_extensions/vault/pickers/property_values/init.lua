--- Pick a value from the selected property.
--- @param opts table
--- @return Picker
return function(opts)
    local vault_state = require("vault.core.state")
    local entry_display = require("telescope.pickers.entry_display")
    local finders = require("telescope.finders")
    local pickers = require("telescope.pickers")
    local sorters = require("telescope.sorters")
    local vault_mappings = require("telescope._extensions.vault.mappings")
    local vault_hl = require("telescope._extensions.vault.highlights")
    local make_filter = require("telescope._extensions.vault.on_input_filter")

    opts = opts or {}
    opts.values = opts.values or error("No values provided")
    local values_list = {}
    for _, value in pairs(opts.values) do
        table.insert(values_list, value)
    end

    local uis = vim.api.nvim_list_uis()
    local ui_height = (uis[1] and uis[1].height) or 40
    local steps = math.min(ui_height, vim.tbl_count(values_list))
    local hl_name = "VaultProperty"
    local colors = vault_hl.setup(hl_name, steps, { "Comment", "Normal", "String" })

    local make_display = function(entry)
        local property = entry.value
        local sources_count = property.data.count

        local col_1 = property.data.type
        local col_2 = property.data.name
        local col_2_hl_name = "TelescopeResultsNormal"
        if colors then
            local i = math.min(math.floor(sources_count / 2), steps)
            if i == 0 then i = 1 end
            col_2_hl_name = hl_name .. tostring(i)
        end
        local col_3 = tostring(sources_count)

        local displayer = entry_display.create({
            separator = " ",
            items = {
                { width = 12 },
                { width = 40 },
                { remaining = true },
            },
        })

        return displayer({
            { col_1, "TelescopeResultsNormal" },
            { col_2, col_2_hl_name },
            { col_3, "TelescopeResultsNumber" },
        })
    end

    local entry_maker = function(property)
        return {
            value = property,
            ordinal = string.format("%s %s %s", property.data.name, property.data.type, tostring(property.data.count)),
            display = make_display,
        }
    end

    local finder = finders.new_table({
        results = values_list,
        entry_maker = entry_maker,
    })

    table.sort(values_list, function(a, b)
        return a.data.count > b.data.count
    end)

    local picker = pickers.new(opts, {
        prompt_title = opts.property_name,
        finder = finder,
        sorter = sorters.get_fzy_sorter(),
        attach_mappings = vault_hl.make_attach_mappings(vault_mappings.property_values, hl_name, colors),
        on_input_filter_cb = make_filter(values_list, entry_maker),
    })
    vault_state.set_global_key("picker", picker)
    return picker
end
