--- @class telescope_popup_options.vault.Tags: telescope_popup_options
--- @field tags? vault.Tags

--- Search for tags
--- @param opts? telescope_popup_options.vault.Tags
--- @return Picker
return function(opts)
    local vault_state = require("vault.core.state")
    local entry_display = require("telescope.pickers.entry_display")
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

    local ui_height = vim.o.lines
    if #vim.api.nvim_list_uis() > 0 then
        ui_height = vim.api.nvim_list_uis()[1].height
    end
    local steps = math.min(ui_height, vim.tbl_count(tags_list))

    local hl_name = "VaultTag"
    local colors = vault_hl.setup(hl_name, steps, { "Comment", "Normal", "String" })

    local make_display = function(entry)
        local tag = entry.value
        local sources_count = tag.data.count or 0

        local col_1 = tag.data.name
        local col_1_hl_name = "TelescopeResultsNormal"
        if colors then
            local i = math.min(math.floor(sources_count / 2), steps)
            if i == 0 then i = 1 end
            col_1_hl_name = hl_name .. tostring(i)
        end

        local col_2 = tostring(sources_count)

        local displayer = entry_display.create({
            separator = " ",
            items = {
                { width = 29 },
                { remaining = true },
            },
        })

        return displayer({
            { col_1, col_1_hl_name },
            { col_2, "TelescopeResultsNumber" },
        })
    end

    local entry_maker = function(tag)
        return {
            value = tag,
            ordinal = tag.data.name .. " " .. tostring(tag.data.count),
            display = make_display,
        }
    end

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
