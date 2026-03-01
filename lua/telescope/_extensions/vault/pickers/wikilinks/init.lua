--- @class telescope_popup_options.vault.Wikilinks: telescope_popup_options
--- @field query? string[] List of property names to show. If not provided, all properties will be shown.
--- @field sort_by? string
--- @field show_resolved? boolean Whether to show resolved links first

--- Enhanced Wikilinks picker
--- @param opts? telescope_popup_options.vault.Wikilinks
--- @return Picker
return function(opts)
    opts = opts or {}
    opts.sort_by = opts.sort_by or "resolved" -- default sorting by resolved state
    opts.show_resolved = opts.show_resolved == nil and true or opts.show_resolved

    local entry_display = require("telescope.pickers.entry_display")
    local finders = require("telescope.finders")
    local pickers = require("telescope.pickers")
    local sorters = require("telescope.sorters")
    local vault_previewers = require("telescope._extensions.vault.previewers")
    local VaultWikilinks = require("vault.wikilinks")
    local wikilinks = opts.wikilinks or VaultWikilinks()
    local vault_state = require("vault.core.state")
    local utils = require("vault.utils")
    local vault_hl = require("telescope._extensions.vault.highlights")
    local make_filter = require("telescope._extensions.vault.on_input_filter")
    local wl_actions = require("telescope._extensions.vault.pickers.wikilinks.actions")

    local results = opts._results or wikilinks:list() or {}

    -- Early exit if empty
    if next(results) == nil then
        return
    end

    -- Compute UI dimensions
    local ui_height = vim.o.lines
    if #vim.api.nvim_list_uis() > 0 then
        ui_height = vim.api.nvim_list_uis()[1].height
    end
    local steps = math.min(ui_height, vim.tbl_count(results))

    -- Gradient-based highlighting (best-effort)
    local hl_base = "VaultWikilink"
    local colors = vault_hl.setup(hl_base, steps, { "Boolean", "Comment", "Normal", "String" })

    -- Compute column widths
    local slug_max = 0
    for _, w in ipairs(results) do
        local slug = (w.data and w.data.slug) or ""
        if #slug > slug_max then
            slug_max = #slug
        end
    end

    -- Make the display for each entry
    local make_display = function(entry)
        local wikilink = (entry and entry.value) and entry.value or entry
        local slug = wikilink.data and wikilink.data.slug or "<unknown>"
        local context = wikilink.data and (wikilink.data.context or wikilink.data.excerpt or "")
            or ""

        local resolved = wikilink:is_resolved_on_disk()

        local mark = resolved and "✓" or "○"
        local mark_hl = resolved and "TelescopeResultsDiffAdd" or "TelescopeResultsDiffChange"

        local backlinks_count = (wikilink.data and type(wikilink.data.sources) == "table")
            and vim.tbl_count(wikilink.data.sources) or 0

        local slug_hl = resolved and "TelescopeResultsNormal" or "TelescopeResultsComment"
        if resolved and colors then
            local chars = #context
            local idx = math.min(math.max(1, math.floor(chars / 16)), steps)
            slug_hl = hl_base .. tostring(idx)
        end

        local displayer = entry_display.create({
            separator = " ",
            items = {
                { width = 2 }, -- mark (resolved/unresolved)
                { width = 4 }, -- source count
                { width = slug_max + 2 },
                { remaining = true },
            },
        })

        return displayer({
            { mark, mark_hl },
            { tostring(backlinks_count), "TelescopeResultsComment" },
            { slug, slug_hl },
            { (context:gsub("\n", " "):sub(1, 120)), "TelescopeResultsComment" },
        })
    end

    local entry_maker = function(entry)
        local slug = (entry.data and entry.data.slug) or ""
        local context = (entry.data and (entry.data.context or entry.data.excerpt or "")) or ""

        local filename = nil
        if entry:is_resolved_on_disk() then
            filename = utils.slug_to_path(entry.data.target)
        else
            if entry.data and type(entry.data.sources) == "table" then
                local first_source_slug = next(entry.data.sources)
                if first_source_slug then
                    filename = utils.slug_to_path(first_source_slug)
                end
            end
        end

        return {
            value = entry,
            ordinal = slug .. " " .. context,
            display = make_display,
            filename = filename,
        }
    end

    -- Sorting: support resolved, slug, path, mtime
    if opts.sort_by == "slug" then
        table.sort(results, function(a, b)
            return (a.data.slug or "") < (b.data.slug or "")
        end)
    elseif opts.sort_by == "mtime" then
        table.sort(results, function(a, b)
            local a_m = 0
            local b_m = 0
            if a.data and a.data.target then
                local ap = utils.slug_to_path(a.data.target)
                a_m = vim.fn.getftime(ap)
            end
            if b.data and b.data.target then
                local bp = utils.slug_to_path(b.data.target)
                b_m = vim.fn.getftime(bp)
            end
            return a_m < b_m
        end)
    elseif opts.sort_by == "resolved" then
        table.sort(results, function(a, b)
            local ra = a:is_resolved_on_disk() and 1 or 0
            local rb = b:is_resolved_on_disk() and 1 or 0
            if ra == rb then
                return (a.data.slug or "") < (b.data.slug or "")
            end
            if opts.show_resolved then
                return ra > rb
            else
                return ra < rb
            end
        end)
    end

    local finder = finders.new_table({
        results = results,
        entry_maker = entry_maker,
    })

    -- Shared context for action factories
    local ctx = {
        wikilinks = wikilinks,
        results = results,
        opts = opts,
    }

    local attach_mappings = function(prompt_bufnr, map)
        local actions = require("telescope.actions")

        -- <CR> — open target (resolved) or create note (unresolved)
        actions.select_default:replace(wl_actions.make_enter(ctx))

        -- <C-l> — resolve
        local resolve = wl_actions.make_resolve(prompt_bufnr, ctx)
        map("i", "<c-l>", resolve)
        map("n", "<c-l>", resolve)

        -- <C-S-l> — batch resolve (interactive queue with "Create all" option)
        local batch_resolve = wl_actions.make_batch_resolve(prompt_bufnr, ctx)
        map("i", "<c-s-l>", batch_resolve)
        map("n", "<c-s-l>", batch_resolve)

        -- <C-S-c> — batch create (instant, no prompts)
        local batch_create = wl_actions.make_batch_create(prompt_bufnr, ctx)
        map("i", "<c-s-c>", batch_create)
        map("n", "<c-s-c>", batch_create)

        -- <C-j> — merge
        local merge = wl_actions.make_merge(prompt_bufnr, ctx)
        map("i", "<c-j>", merge)
        map("n", "<c-j>", merge)

        -- Cleanup gradient highlights on close
        if colors then
            pcall(vim.api.nvim_create_autocmd, "BufWipeout", {
                buffer = prompt_bufnr,
                once = true,
                callback = function()
                    vault_hl.cleanup(hl_base, #colors)
                end,
            })
        end

        return true
    end

    local picker_opts = {
        prompt_title = "Wikilinks  <C-l>=resolve  <C-S-l>=batch  <C-S-c>=create-all  <C-j>=compare/merge",
        finder = finder,
        sorter = sorters.get_generic_fuzzy_sorter(),
        previewer = vault_previewers.wikilinks,
        attach_mappings = attach_mappings,
        on_input_filter_cb = make_filter(results, entry_maker),
        sorting_strategy = "ascending",
    }

    local picker = pickers.new({}, picker_opts)
    vault_state.set_global_key("picker", picker)
    return picker
end
