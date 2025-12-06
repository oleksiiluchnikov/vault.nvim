--- @class telescope_popup_options.vault.Wikilinks: telescope_popup_options
--- @field query? string[] List of property names to show. If not provided, all properties will be shown.

--- Search for notes linking to current note
--- @param opts? telescope_popup_options.vault.Wikilinks
--- @return Picker
return function(opts)
    local Wikilinks = require("vault.wikilinks")
    local wikilinks = Wikilinks()
    local results = wikilinks:list()

    --- @param entry table
    local make_display = function(entry)
        --- @type vault.Wikilink
        local wikilink = entry.value

        local entry_width = string.len(wikilink.data.slug) + 2
        local displayer = entry_display.create({
            separator = " ",
            items = {
                { width = entry_width },
                { remaining = true },
            },
        })
        local display_value = {
            entry.value.data.slug,
            "TelescopeResultsNormal",
        }
        return displayer({
            display_value,
        })
    end

    local entry_maker = function(entry)
        return {
            value = entry,
            ordinal = entry.data.slug,
            display = make_display,
        }
    end

    local picker = pickers.new({}, {
        prompt_title = "Wikilinks",
        finder = finders.new_table({
            results = results,
            entry_maker = entry_maker,
        }),
        sorter = sorters.get_generic_fuzzy_sorter(),
        -- previewer = previewers.vim_buffer_cat.new({
        --     get_buffer_by_name = function(_, entry)
        --         local bufnr = vim.api.nvim_create_buf(false, true)
        --         local lines = vim.fn.readfile(entry.path)
        --         if type(bufnr) ~= "number" then
        --             error("bufnr is not a number")
        --         end
        --         vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
        --         vim.api.nvim_buf_set_option(bufnr, "filetype", "markdown")
        --         return bufnr
        --     end,
        -- }),
        sorting_strategy = "ascending",
    })
    vault_state.set_global_key("picker", picker)
    return picker
end
