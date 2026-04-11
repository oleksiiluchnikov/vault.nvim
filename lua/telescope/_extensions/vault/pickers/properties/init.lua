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
    local layouts = require("telescope._extensions.vault.layouts")
    local vault_previewers = require("telescope._extensions.vault.previewers")
    local picker_cache = require("telescope._extensions.vault.pickers.cache")
    local make_filter = require("telescope._extensions.vault.on_input_filter")

    opts = opts or {}
    opts.query = opts.query or {}

    local properties_source
    if opts.properties then
        properties_source = {
            list = opts.properties:list(),
            map = opts.properties.map,
        }
    elseif next(opts.query) == nil then
        properties_source = picker_cache.get_or_set("properties.default", function()
            local properties = require("vault.properties")()
            local list = properties:list()
            table.sort(list, function(a, b)
                return a.data.count > b.data.count
            end)
            return {
                list = list,
                map = properties.map,
            }
        end)
    else
        local properties = require("vault.properties")()
        local list = properties:list()
        table.sort(list, function(a, b)
            return a.data.count > b.data.count
        end)
        properties_source = {
            list = list,
            map = properties.map,
        }
    end

    local properties_list = properties_source.list
    if next(properties_list) == nil then
        log.info("No properties found in vault")
    end

    local ui_height, _ = layouts.ui_size()
    local steps = math.min(ui_height, vim.tbl_count(properties_list))
    local hl_name = "VaultProperty"
    local colors = vault_hl.setup(hl_name, steps, { "Comment", "Normal", "String" })

    local vault_em = require("telescope._extensions.vault.entry_maker")
    local _, entry_maker = vault_em.counted({
        hl_name = hl_name,
        colors = colors,
        steps = steps,
        get_name = function(p)
            return p.data.name
        end,
        get_count = function(p)
            return p.data.count
        end,
    })

    -- Filter properties by query
    if next(opts.query) ~= nil then
        local filtered_properties = {}
        local filtered_list = {}
        for _, property in ipairs(opts.query) do
            local value = properties_source.map[property]
            if value ~= nil then
                filtered_properties[property] = value
                filtered_list[#filtered_list + 1] = value
            end
        end
        if next(filtered_properties) == nil then
            log.info("No properties found")
        end
        properties_source = {
            list = filtered_list,
            map = filtered_properties,
        }
        properties_list = filtered_list
    end

    if vim.tbl_count(properties_source.map) == 1 then
        local property_name = vim.tbl_keys(properties_source.map)[1]
        require("vault.properties.actions").open_picker_values(property_name)
        return nil
    end

    local finder = finders.new_table({
        results = properties_list,
        entry_maker = entry_maker,
    })

    local picker = pickers.new(opts, {
        prompt_title = "Properties",
        finder = finder,
        sorter = sorters.get_fzy_sorter(),
        previewer = vault_previewers.properties,
        attach_mappings = vault_hl.make_attach_mappings(vault_mappings.properties, hl_name, colors),
        on_input_filter_cb = make_filter(properties_list, entry_maker),
    })
    vault_state.set_global_key("picker", picker)
    return picker
end
