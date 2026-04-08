--- @class telescope_popup_options.vault.Bases: telescope_popup_options
--- @field bases? vault.Bases

--- List all bases in the vault (Level 1 picker).
--- Selecting a base drills into a Level 2 picker showing matched notes.
--- @param opts? telescope_popup_options.vault.Bases|table<string, any>
--- @return Picker?
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

    opts = opts or {}
    opts.bases = opts.bases or require("vault.bases")()

    --- @type vault.Base[]
    local results = opts.bases:list()
    if next(results) == nil then
        log.info("No bases found in vault")
        return
    end

    -- Sort bases alphabetically by name
    table.sort(results, function(a, b)
        return a.data.name < b.data.name
    end)

    --- @type integer
    local ui_height, _ = vault_layouts.ui_size()

    local steps = math.min(ui_height, vim.tbl_count(results))

    -- Gradient-based highlighting
    local hl_name = "VaultBase"
    local colors = vault_hl.setup(hl_name, steps, { "Comment", "Normal", "String" })

    -- Calculate column widths
    local name_maxwidth = 0
    for _, base in ipairs(results) do
        local w = vim.fn.strdisplaywidth(base.data.name)
        if w > name_maxwidth then
            name_maxwidth = w
        end
    end
    name_maxwidth = math.max(name_maxwidth, 10)

    local make_display = function(entry)
        --- @type vault.Base
        local base = entry.value

        -- Column 1: indicator block with gradient
        local col_1_hl_name = "TelescopeResultsNormal"
        if colors then
            local view_ct = base:view_count()
            local index = math.min(math.max(view_ct, 1), steps)
            col_1_hl_name = hl_name .. tostring(index)
        end

        -- Column 2: base name
        local col_2 = base.data.name
        local col_2_hl_name = col_1_hl_name

        -- Column 3: summary info (filters/formulas/views counts)
        local parts = {}
        if base:has_filters() then
            table.insert(parts, "F")
        end
        local formula_count = #base:formula_names()
        if formula_count > 0 then
            table.insert(parts, "f:" .. tostring(formula_count))
        end
        local view_count = base:view_count()
        if view_count > 0 then
            table.insert(parts, "v:" .. tostring(view_count))
        end
        local col_3 = table.concat(parts, " ")
        local col_3_hl_name = "TelescopeResultsComment"

        -- Column 4: relpath
        local col_4 = base.data.relpath or ""
        local col_4_hl_name = "TelescopeResultsComment"

        local displayer = entry_display.create({
            separator = " ",
            items = {
                { width = 2 },
                { width = name_maxwidth + 2 },
                { width = 12 },
                { remaining = true },
            },
        })

        return displayer({
            { "██", col_1_hl_name },
            { col_2, col_2_hl_name },
            { col_3, col_3_hl_name },
            { col_4, col_4_hl_name },
        })
    end

    --- @param base vault.Base
    --- @return vault.TelescopeEntry
    local entry_maker = function(base)
        local ordinal = base.data.name .. " " .. (base.data.relpath or "")
        return {
            value = base,
            ordinal = ordinal,
            display = make_display,
        }
    end

    local finder = finders.new_table({
        results = results,
        entry_maker = entry_maker,
    })

    local picker_opts = {
        prompt_title = "bases",
        finder = finder,
        sorter = sorters.get_fzy_sorter(),
        previewer = vault_previewers.bases or nil,
        attach_mappings = vault_hl.make_attach_mappings(vault_mappings.bases, hl_name, colors),
    }
    local picker = pickers.new(vault_layouts.bases(), picker_opts)

    vault_state.set_global_key("picker", picker)
    return picker
end
