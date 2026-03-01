--- @class telescope_popup_options.vault.dirs: telescope_popup_options

--- @param opts? table
--- @return Picker
return function(opts)
    local dirs = require("vault.dirs")()
    local utils = require("vault.utils")
    local entry_display = require("telescope.pickers.entry_display")
    local finders = require("telescope.finders")
    local sorters = require("telescope.sorters")
    local vault_state = require("vault.core.state")
    local Scanner = require("vault.scanner")
    local pickers = require("telescope.pickers")
    local vault_layouts = require("telescope._extensions.vault.layouts")
    local vault_hl = require("telescope._extensions.vault.highlights")
    local vault_mappings = require("telescope._extensions.vault.mappings")
    local make_filter = require("telescope._extensions.vault.on_input_filter")

    opts = opts or {}

    local dirs_list = dirs:list()
    if next(dirs_list) == nil then
        require("plenary.log").info("No directories found in vault")
    end

    local uis = vim.api.nvim_list_uis()
    local ui_height = (uis[1] and uis[1].height) or 40
    local steps = math.min(ui_height, vim.tbl_count(dirs_list))
    local hl_name = dirs.class.name
    local colors = vault_hl.setup(hl_name, steps, { "Comment", "Normal", "String" })

    local slugs = Scanner.slugs()

    local make_display = function(entry)
        local directory = entry.value
        local sources_count = 0
        for slug, _ in pairs(slugs) do
            if utils.match(slug, directory.data.relpath, "startswith", false) then
                sources_count = sources_count + 1
            end
        end

        local col_1 = directory.data.relpath
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

    local entry_maker = function(directory)
        return {
            value = directory,
            ordinal = directory.data.relpath,
            display = make_display,
        }
    end

    local finder = finders.new_table({
        results = dirs_list,
        entry_maker = entry_maker,
    })

    opts.sort_by = opts.sort_by or "count"

    if opts.sort_by == "count" then
        table.sort(dirs_list, function(a, b)
            local a_relpath = a.data.relpath
            local b_relpath = b.data.relpath
            local a_count = 0
            for slug, _ in pairs(slugs) do
                if utils.match(slug, a_relpath, "startswith", false) then
                    a_count = a_count + 1
                end
            end
            local b_count = 0
            for slug, _ in pairs(slugs) do
                if utils.match(slug, b_relpath, "startswith", false) then
                    b_count = b_count + 1
                end
            end
            return a_count > b_count
        end)
    elseif opts.sort_by == "name" then
        table.sort(dirs_list, function(a, b)
            local an = a.data.name or ""
            local bn = b.data.name or ""
            if bn:sub(1, 1) == "_" then return false end
            if an:sub(1, 1) == "_" then return true end
            return an < bn
        end)
    end

    local picker = pickers.new(vault_layouts.mini(), {
        prompt_title = "Directories",
        finder = finder,
        sorter = sorters.get_fzy_sorter(),
        on_input_filter_cb = make_filter(dirs_list, entry_maker),
        attach_mappings = vault_hl.make_attach_mappings(vault_mappings.directories, hl_name, colors),
    })

    vault_state.set_global_key("picker", picker)
    return picker
end
