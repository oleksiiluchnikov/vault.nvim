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
    local wikilinks = VaultWikilinks()
    local vault_state = require("vault.core.state")
    local utils = require("vault.utils")

    local results = wikilinks:list() or {}

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
    local colors = nil
    do
        local ok, maybe_colors = pcall(function()
            local Gradient = require("gradient")
            return Gradient.from_stops(steps, "Boolean", "Comment", "Normal", "String")
        end)
        if ok and type(maybe_colors) == "table" then
            colors = maybe_colors
            for i, color in ipairs(colors) do
                pcall(vim.api.nvim_set_hl, 0, hl_base .. tostring(i), { fg = color })
            end
        end
    end

    -- Compute column widths
    local slug_max = 0
    for _, w in ipairs(results) do
        local slug = (w.data and w.data.slug) or ""
        if #slug > slug_max then
            slug_max = #slug
        end
    end

    --- Check whether a wikilink resolves to an existing file.
    --- wikilink.data.target is a slug (e.g. "my-note"), NOT an absolute path.
    --- We convert via utils.slug_to_path() to get the real path on disk.
    --- @param wikilink vault.Wikilink
    --- @return boolean
    local function is_resolved(wikilink)
        local target_slug = wikilink.data and wikilink.data.target
        if not target_slug or target_slug == "" then
            return false
        end
        local abs_path = utils.slug_to_path(target_slug)
        return vim.fn.filereadable(abs_path) == 1
    end

    --- Count sources (backlinks) for a wikilink.
    --- @param wikilink vault.Wikilink
    --- @return number
    local function source_count(wikilink)
        if wikilink.data and type(wikilink.data.sources) == "table" then
            return vim.tbl_count(wikilink.data.sources)
        end
        return 0
    end

    -- Make the display for each entry
    local make_display = function(entry)
        -- entry may be a telescope entry (with .value) or raw wikilink
        local wikilink = (entry and entry.value) and entry.value or entry
        local slug = wikilink.data and wikilink.data.slug or "<unknown>"
        local context = wikilink.data and (wikilink.data.context or wikilink.data.excerpt or "")
            or ""

        local resolved = is_resolved(wikilink)

        local mark = resolved and "✓" or "○"
        local mark_hl = resolved and "TelescopeResultsDiffAdd" or "TelescopeResultsDiffChange"

        local backlinks_count = source_count(wikilink)

        -- Slug highlight: resolved links get a stronger color, unresolved are dimmed
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

        local display_value = {
            { mark, mark_hl },
            { tostring(backlinks_count), "TelescopeResultsComment" },
            { slug, slug_hl },
            { (context:gsub("\n", " "):sub(1, 120)), "TelescopeResultsComment" },
        }
        return displayer(display_value)
    end

    local entry_maker = function(entry)
        local slug = (entry.data and entry.data.slug) or ""
        local context = (entry.data and (entry.data.context or entry.data.excerpt or "")) or ""

        -- Determine filename for Telescope's built-in file-open actions (<C-t>, <C-v>, <C-x>)
        local filename = nil
        if is_resolved(entry) then
            -- Resolved: target file exists, point directly to it
            filename = utils.slug_to_path(entry.data.target)
        else
            -- Unresolved: fall back to the first source note (so Telescope can still open something)
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
            local ra = is_resolved(a) and 1 or 0
            local rb = is_resolved(b) and 1 or 0
            if ra == rb then
                return (a.data.slug or "") < (b.data.slug or "")
            end
            if opts.show_resolved then
                return ra > rb -- show resolved first
            else
                return ra < rb
            end
        end)
    end

    local finder = finders.new_table({
        results = results,
        entry_maker = entry_maker,
    })

    -- Interactive filter callback similar to the notes picker (supports trailing / pattern and negative prefix -)
    local on_input_filter_cb = function(prompt)
        local picker = vault_state.get_global_key("picker")
        if not picker then
            return { prompt = "" }
        end

        local default_finder = function()
            local new_finder = finders.new_table({ results = results, entry_maker = entry_maker })
            picker.finder:close()
            picker.finder = new_finder
            vault_state.set_global_key("prompt", prompt)
            return { prompt = prompt or "" }
        end

        if prompt == nil or #prompt == 0 then
            return default_finder()
        end

        if prompt:sub(-1) ~= "/" then
            return default_finder()
        end

        local is_negative = false
        if prompt:sub(1, 1) == "-" then
            is_negative = true
        end

        local pattern = prompt:sub(1, -2)
        pattern = pattern:sub(2)
        if is_negative then
            pattern = pattern:sub(2)
        end

        local new_results = {}
        local results_without_excluded = {}
        for _, entry in ipairs(picker.finder.results) do
            local wl = entry.value
            local slug = wl.data and wl.data.slug or ""
            local ok = pcall(vim.fn.match, slug, pattern)
            if not ok then
                goto continue
            end
            if vim.fn.match(slug, pattern) ~= -1 then
                table.insert(new_results, wl)
                if is_negative then
                    table.insert(results_without_excluded, wl)
                end
            end
            ::continue::
        end

        if next(new_results) == nil then
            return default_finder()
        elseif is_negative then
            new_results = {}
            for _, entry in ipairs(picker.finder.results) do
                if not vim.tbl_contains(results_without_excluded, entry.value) then
                    table.insert(new_results, entry.value)
                end
            end
        end

        local new_finder = finders.new_table({ results = new_results, entry_maker = entry_maker })
        picker.finder:close()
        picker.finder = new_finder
        vault_state.set_global_key("prompt", prompt)
        return { prompt = "" }
    end

    -- Attach mappings: default select opens target if available, otherwise open source; provide toggle-resolved mapping if supported by wikilinks
    local attach_mappings = function(prompt_bufnr, map)
        local actions = require("telescope.actions")
        local action_state = require("telescope.actions.state")

        actions.select_default:replace(function()
            local selection = action_state.get_selected_entry()
            if not selection or not selection.value then
                return
            end
            local wl = selection.value
            local slug = wl.data and wl.data.slug or ""
            if slug == "" then
                return
            end

            actions.close(prompt_bufnr)

            if is_resolved(wl) then
                -- Resolved: open the target file
                local target = utils.slug_to_path(slug)
                vim.cmd("edit " .. vim.fn.fnameescape(target))
            else
                -- Unresolved: create a new note (same mechanism as :VaultNoteNew)
                local Note = require("vault.notes.note")
                local path = utils.slug_to_path(slug)
                local note = Note(path)
                note:write(path)
                note:edit()
            end
        end)

        -- Toggle resolved mark (best-effort, uses wikilinks:toggle_resolved or wikilinks:resolve if available)
        local function toggle_resolved()
            local selection = require("telescope.actions.state").get_selected_entry()
            if not selection or not selection.value then
                return
            end
            local wl = selection.value
            if type(wikilinks.toggle_resolved) == "function" then
                pcall(function()
                    wikilinks:toggle_resolved(wl)
                end)
            elseif type(wikilinks.resolve) == "function" then
                -- call resolve as a toggle if it exists
                pcall(function()
                    wikilinks:resolve(wl)
                end)
            else
                vim.notify(
                    "Wikilinks: toggle_resolved not implemented in backend",
                    vim.log.levels.INFO
                )
            end
            -- Refresh picker contents if possible
            local picker = vault_state.get_global_key("picker")
            if picker and picker.finder and type(picker.finder.close) == "function" then
                local refreshed = wikilinks:list() or {}
                local new_finder =
                    finders.new_table({ results = refreshed, entry_maker = entry_maker })
                picker.finder:close()
                picker.finder = new_finder
            end
        end

        -- Map <C-r> to toggle resolved (non-destructive)
        pcall(function()
            local map_fn = map
                or function(mode, lhs, rhs)
                    vim.api.nvim_buf_set_keymap(
                        prompt_bufnr,
                        mode,
                        lhs,
                        rhs,
                        { noremap = true, silent = true }
                    )
                end
            -- when map is telescope's map, it will accept mode and lhs/rhs as usual
            if type(map) == "function" then
                map("i", "<c-r>", "<cmd>lua require('telescope.actions')._close()<CR>")
            end
            -- Use telescope's actions to bind a function (recommended way)
            local action_set = require("telescope.actions.set")
            pcall(function()
                action_set.select:replace(function()
                    toggle_resolved()
                end)
            end)
        end)

        -- Cleanup gradient highlights on close
        local function cleanup()
            if colors then
                for i = 1, #colors do
                    pcall(vim.api.nvim_set_hl, 0, hl_base .. tostring(i), {})
                end
            end
        end
        pcall(vim.api.nvim_create_autocmd, "BufWipeout", {
            buffer = prompt_bufnr,
            once = true,
            callback = cleanup,
        })

        return true
    end

    local picker_opts = {
        prompt_title = "Wikilinks",
        finder = finder,
        sorter = sorters.get_generic_fuzzy_sorter(),
        previewer = vault_previewers.wikilinks,
        attach_mappings = attach_mappings,
        on_input_filter_cb = on_input_filter_cb,
        sorting_strategy = "ascending",
    }

    local picker = pickers.new({}, picker_opts)
    vault_state.set_global_key("picker", picker)
    return picker
end
