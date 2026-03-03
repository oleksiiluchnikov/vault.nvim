--- @class telescope_popup_options.vault.properties: telescope_popup_options
--- @field properties? vault.Properties

--- @param opts? telescope_popup_options.vault.properties
--- @return Picker
return function(opts)
    local finders = require("telescope.finders")
    local pickers = require("telescope.pickers")
    local sorters = require("telescope.sorters")
    local vault_state = require("vault.core.state")
    local log = require("vault.log").scope("telescope")
    local vault_mappings = require("telescope._extensions.vault.mappings")
    local vault_hl = require("telescope._extensions.vault.highlights")
    local make_filter = require("telescope._extensions.vault.on_input_filter")

    opts = opts or {}
    opts.query = opts.query or {}
    opts.properties = opts.properties or require("vault.properties")()

    local properties_list = opts.properties:list()
    if next(properties_list) == nil then
        log.info("No properties found in vault")
    end

    table.sort(properties_list, function(a, b)
        return a.data.count > b.data.count
    end)

    local uis = vim.api.nvim_list_uis()
    local ui_height = (uis[1] and uis[1].height) or 40
    local steps = math.min(ui_height, vim.tbl_count(properties_list))
    local hl_name = "VaultProperty"
    local colors = vault_hl.setup(hl_name, steps, { "Comment", "Normal", "String" })

    local vault_em = require("telescope._extensions.vault.entry_maker")
    local _, entry_maker = vault_em.counted({
        hl_name = hl_name,
        colors = colors,
        steps = steps,
        get_name = function(p) return p.data.name end,
        get_count = function(p) return p.data.count end,
    })

    local finder = finders.new_table({
        results = properties_list,
        entry_maker = entry_maker,
    })

    -- Filter properties by query
    if next(opts.query) ~= nil then
        local filtered_properties = {}
        for _, property in ipairs(opts.query) do
            if opts.properties.map[property] ~= nil then
                filtered_properties[property] = opts.properties.map[property]
            end
        end
        if next(filtered_properties) == nil then
            log.info("No properties found")
        end
        opts.properties.map = filtered_properties
    end

    if vim.tbl_count(opts.properties.map) == 1 then
        local property_name = vim.tbl_keys(opts.properties.map)[1]
        require("vault.api").open_picker_property_values(property_name)
        return nil
    end

    local picker = pickers.new(opts, {
        prompt_title = "Properties",
        finder = finder,
        sorter = sorters.get_fzy_sorter(),
        attach_mappings = vault_hl.make_attach_mappings(vault_mappings.properties, hl_name, colors),
        on_input_filter_cb = make_filter(properties_list, entry_maker),
    })
    vault_state.set_global_key("picker", picker)
    return picker
end
