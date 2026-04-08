--- @class telescope_popup_options.vault.Tags: telescope_popup_options
--- @field tags? vault.Tags

--- Search for tags
--- @param opts? telescope_popup_options.vault.Tags
--- @return Picker
return function(opts)
    local vault_state = require("vault.core.state")
    local finders = require("telescope.finders")
    local pickers = require("telescope.pickers")
    local sorters = require("telescope.sorters")
    local log = require("vault.log").scope("telescope")
    local vault_previewers = require("telescope._extensions.vault.previewers")
    local vault_mappings = require("telescope._extensions.vault.mappings")
    local vault_layouts = require("telescope._extensions.vault.layouts")
    local vault_hl = require("telescope._extensions.vault.highlights")
    local make_filter = require("telescope._extensions.vault.on_input_filter")

    opts = opts or {}
    opts.tags = opts.tags or require("vault.tags")()

    local tags_list = opts.tags:list()
    if next(tags_list) == nil then
        log.info("No tags found in vault")
        return
    end

    table.sort(tags_list, function(a, b)
        return a.data.count > b.data.count
    end)

    local ui_height, _ = vault_layouts.ui_size()
    local steps = math.min(ui_height, vim.tbl_count(tags_list))

    local hl_name = "VaultTag"
    local colors = vault_hl.setup(hl_name, steps, { "Comment", "Normal", "String" })

    local vault_em = require("telescope._extensions.vault.entry_maker")
    local _, entry_maker = vault_em.counted({
        hl_name = hl_name,
        colors = colors,
        steps = steps,
        get_name = function(t) return t.data.name end,
        get_count = function(t) return t.data.count or 0 end,
    })

    local finder = finders.new_table({
        results = tags_list,
        entry_maker = entry_maker,
    })

    local picker_opts = {
        prompt_title = "tags",
        finder = finder,
        sorter = sorters.get_fzy_sorter(),
        previewer = vault_previewers.tags,
        attach_mappings = vault_hl.make_attach_mappings(vault_mappings.tags, hl_name, colors),
        on_input_filter_cb = make_filter(tags_list, entry_maker),
    }
    local picker = pickers.new(vault_layouts.tags(), picker_opts)
    vault_state.set_global_key("picker", picker)
    return picker
end
