--- @class telescope_popup_options.vault.dirs: telescope_popup_options

--- @param opts? table
--- @return Picker
return function(opts)
    local finders = require("telescope.finders")
    local sorters = require("telescope.sorters")
    local vault_state = require("vault.core.state")
    local pickers = require("telescope.pickers")
    local vault_layouts = require("telescope._extensions.vault.layouts")
    local default_prep = require("telescope._extensions.vault.pickers.dirs.default_prep")
    local vault_hl = require("telescope._extensions.vault.highlights")
    local vault_mappings = require("telescope._extensions.vault.mappings")
    local make_filter = require("telescope._extensions.vault.on_input_filter")

    --- @param items any[]
    --- @return any[]
    local function copy_list(items)
        local copy = {}
        for i = 1, #items do
            copy[i] = items[i]
        end
        return copy
    end

    opts = opts or {}

    local prepared = default_prep.get_or_prepare()

    local dirs_list = copy_list(prepared.by_count)
    if next(dirs_list) == nil then
        require("vault.log").scope("telescope").info("No directories found in vault")
    end

    local ui_height, _ = vault_layouts.ui_size()
    local steps = math.min(ui_height, vim.tbl_count(dirs_list))
    local hl_name = (dirs_list[1] and dirs_list[1].class and dirs_list[1].class.name) or "VaultDirs"
    local colors = vault_hl.setup(hl_name, steps, { "Comment", "Normal", "String" })

    local dir_counts = prepared.dir_counts --- @type table<string, integer>

    local vault_em = require("telescope._extensions.vault.entry_maker")
    local _, entry_maker = vault_em.counted({
        hl_name = hl_name,
        colors = colors,
        steps = steps,
        get_name = function(d)
            return d.data.relpath
        end,
        get_count = function(d)
            return dir_counts[d.data.relpath] or 0
        end,
        get_ordinal = function(d)
            return d.data.relpath
        end,
    })

    local finder = finders.new_table({
        results = dirs_list,
        entry_maker = entry_maker,
    })

    opts.sort_by = opts.sort_by or "count"

    if opts.sort_by == "count" then
        table.sort(dirs_list, function(a, b)
            return (dir_counts[a.data.relpath] or 0) > (dir_counts[b.data.relpath] or 0)
        end)
    elseif opts.sort_by == "name" then
        table.sort(dirs_list, function(a, b)
            local an = a.data.name or ""
            local bn = b.data.name or ""
            if bn:sub(1, 1) == "_" then
                return false
            end
            if an:sub(1, 1) == "_" then
                return true
            end
            return an < bn
        end)
    end

    local picker = pickers.new(vault_layouts.mini(), {
        prompt_title = "Directories",
        finder = finder,
        sorter = sorters.get_fzy_sorter(),
        on_input_filter_cb = make_filter(dirs_list, entry_maker),
        attach_mappings = vault_hl.make_attach_mappings(
            vault_mappings.directories,
            hl_name,
            colors
        ),
    })

    vault_state.set_global_key("picker", picker)
    return picker
end
