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
    local layouts = require("telescope._extensions.vault.layouts")
    local link_index = require("vault.notes.link_index")
    local picker_cache = require("telescope._extensions.vault.pickers.cache")
    local vault_state = require("vault.core.state")
    local utils = require("vault.utils")
    local vault_hl = require("telescope._extensions.vault.highlights")
    local make_filter = require("telescope._extensions.vault.on_input_filter")
    local wl_actions = require("telescope._extensions.vault.pickers.wikilinks.actions")

    --- @param items any[]
    --- @return any[]
    local function copy_list(items)
        local copy = {}
        for i = 1, #items do
            copy[i] = items[i]
        end
        return copy
    end

    --- @param results vault.Wikilink[]
    --- @return table<vault.Wikilink, { backlinks_count: integer, filename: string|nil, resolved: boolean }>, integer
    local function build_wikilink_meta(results)
        local meta = {}
        local slug_max = 0

        for _, wikilink in ipairs(results) do
            local slug = (wikilink.data and wikilink.data.slug) or ""
            if #slug > slug_max then
                slug_max = #slug
            end

            local resolved = type(wikilink.data.target) == "string" and wikilink.data.target ~= ""
            local filename = nil
            if resolved then
                filename = utils.slug_to_path(wikilink.data.target)
            else
                local first_source_slug = type(wikilink.data.sources) == "table"
                        and next(wikilink.data.sources)
                    or nil
                if first_source_slug then
                    filename = utils.slug_to_path(first_source_slug)
                end
            end

            meta[wikilink] = {
                backlinks_count = type(wikilink.data.sources) == "table" and vim.tbl_count(
                    wikilink.data.sources
                ) or 0,
                filename = filename,
                resolved = resolved,
            }
        end

        return meta, slug_max
    end

    --- @param results vault.Wikilink[]
    --- @param meta table<vault.Wikilink, { backlinks_count: integer, filename: string|nil, resolved: boolean }>
    --- @return vault.Wikilink[]
    local function sort_by_slug(results, meta)
        local sorted = copy_list(results)
        table.sort(sorted, function(a, b)
            local a_slug = (a.data and a.data.slug) or ""
            local b_slug = (b.data and b.data.slug) or ""
            if a_slug == b_slug then
                return (meta[a] and meta[a].backlinks_count or 0)
                    > (meta[b] and meta[b].backlinks_count or 0)
            end
            return a_slug < b_slug
        end)
        return sorted
    end

    --- @param results vault.Wikilink[]
    --- @param meta table<vault.Wikilink, { backlinks_count: integer, filename: string|nil, resolved: boolean }>
    --- @param show_resolved boolean
    --- @return vault.Wikilink[]
    local function sort_by_resolved(results, meta, show_resolved)
        local sorted = copy_list(results)
        table.sort(sorted, function(a, b)
            local ra = meta[a] and meta[a].resolved and 1 or 0
            local rb = meta[b] and meta[b].resolved and 1 or 0
            if ra == rb then
                return ((a.data and a.data.slug) or "") < ((b.data and b.data.slug) or "")
            end
            if show_resolved then
                return ra > rb
            end
            return ra < rb
        end)
        return sorted
    end

    local prepared = nil
    local wikilinks = opts.wikilinks
    local results = opts._results
    local meta
    local slug_max
    local VaultWikilinks = require("vault.wikilinks")

    if not wikilinks and not results and (opts.sort_by == "resolved" or opts.sort_by == "slug") then
        prepared = picker_cache.get_or_set("wikilinks.default", function()
            local collection = VaultWikilinks.from_map(link_index.wikilinks())
            local prepared_results = collection:list() or {}
            local prepared_meta, prepared_slug_max = build_wikilink_meta(prepared_results)

            return {
                meta = prepared_meta,
                resolved_first = sort_by_resolved(prepared_results, prepared_meta, true),
                slug_max = prepared_slug_max,
                slug_sorted = sort_by_slug(prepared_results, prepared_meta),
                unresolved_first = sort_by_resolved(prepared_results, prepared_meta, false),
                wikilinks = collection,
            }
        end)
        wikilinks = prepared.wikilinks
        meta = prepared.meta
        slug_max = prepared.slug_max
        if opts.sort_by == "slug" then
            results = copy_list(prepared.slug_sorted)
        elseif opts.show_resolved then
            results = copy_list(prepared.resolved_first)
        else
            results = copy_list(prepared.unresolved_first)
        end
    else
        wikilinks = wikilinks or VaultWikilinks.from_map(link_index.wikilinks())
        results = results or wikilinks:list() or {}
        meta, slug_max = build_wikilink_meta(results)
    end

    -- Early exit if empty
    if next(results) == nil then
        return
    end

    -- Compute UI dimensions
    local ui_height, _ = layouts.ui_size()
    local steps = math.min(ui_height, vim.tbl_count(results))

    -- Gradient-based highlighting (best-effort)
    local hl_base = "VaultWikilink"
    local colors = vault_hl.setup(hl_base, steps, { "Boolean", "Comment", "Normal", "String" })

    local displayer = entry_display.create({
        separator = " ",
        items = {
            { width = 2 }, -- mark (resolved/unresolved)
            { width = 4 }, -- source count
            { width = slug_max + 2 },
            { remaining = true },
        },
    })

    -- Make the display for each entry
    local make_display = function(entry)
        local wikilink = (entry and entry.value) and entry.value or entry
        local info = meta[wikilink] or { backlinks_count = 0, resolved = false }
        local slug = wikilink.data and wikilink.data.slug or "<unknown>"
        local context = wikilink.data and (wikilink.data.context or wikilink.data.excerpt or "")
            or ""

        local resolved = info.resolved

        local mark = resolved and "✓" or "○"
        local mark_hl = resolved and "TelescopeResultsDiffAdd" or "TelescopeResultsDiffChange"

        local backlinks_count = info.backlinks_count

        local slug_hl = resolved and "TelescopeResultsNormal" or "TelescopeResultsComment"
        if resolved and colors then
            local chars = #context
            local idx = math.min(math.max(1, math.floor(chars / 16)), steps)
            slug_hl = hl_base .. tostring(idx)
        end

        return displayer({
            { mark, mark_hl },
            { tostring(backlinks_count), "TelescopeResultsComment" },
            { slug, slug_hl },
            { (context:gsub("\n", " "):sub(1, 120)), "TelescopeResultsComment" },
        })
    end

    local entry_maker = function(entry)
        local info = meta[entry] or { filename = nil }
        local slug = (entry.data and entry.data.slug) or ""
        local context = (entry.data and (entry.data.context or entry.data.excerpt or "")) or ""

        return {
            value = entry,
            ordinal = slug .. " " .. context,
            display = make_display,
            filename = info.filename,
        }
    end

    -- Sorting: support resolved, slug, path, mtime
    if opts.sort_by == "slug" and not prepared then
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
    elseif opts.sort_by == "resolved" and not prepared then
        table.sort(results, function(a, b)
            local ra = meta[a] and meta[a].resolved and 1 or 0
            local rb = meta[b] and meta[b].resolved and 1 or 0
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

    -- Keybinding definitions: { lhs, description, action_factory }
    local keybinds = {
        { "<C-l>", "resolve", "make_resolve" },
        { "<C-b>", "batch", "make_batch_resolve" },
        { "<C-a>", "create-all", "make_batch_create" },
        { "<C-j>", "compare", "make_merge" },
    }

    local attach_mappings = function(prompt_bufnr, map)
        local actions = require("telescope.actions")

        -- <CR> — open target (resolved) or create note (unresolved)
        if opts.on_select then
            actions.select_default:replace(function()
                local selection = require("telescope.actions.state").get_selected_entry()
                actions.close(prompt_bufnr)
                if selection and selection.value then
                    opts.on_select(selection.value)
                end
            end)
        else
            actions.select_default:replace(wl_actions.make_enter(ctx))
        end

        for _, kb in ipairs(keybinds) do
            local action = wl_actions[kb[3]](prompt_bufnr, ctx)
            map("i", kb[1], action)
            map("n", kb[1], action)
        end

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

    -- Build prompt title from keybinds
    local hints = {}
    for _, kb in ipairs(keybinds) do
        hints[#hints + 1] = kb[1] .. "=" .. kb[2]
    end
    local picker_opts = {
        prompt_title = "Wikilinks  " .. table.concat(hints, "  "),
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
