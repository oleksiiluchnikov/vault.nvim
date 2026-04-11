--- @class telescope_popup_options.vault.Notes: telescope_popup_options
--- @field notes? vault.Notes
--- @field sort_by? string
--- @field columns? (string|vault.TelescopeNotesColumnSpec)[]

--- Search for notes in vault
--- @param opts? telescope_popup_options.vault.Notes|table<string, any>
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
    local make_filter = require("telescope._extensions.vault.on_input_filter")
    local default_prep = require("telescope._extensions.vault.pickers.notes.default_prep")
    local link_index = require("vault.notes.link_index")
    local note_stats = require("telescope._extensions.vault.pickers.notes.stats")
    local note_columns = require("telescope._extensions.vault.pickers.notes.columns")

    opts = opts or {}
    opts.sort_by = opts.sort_by or "mtime"
    opts.prompt_title = opts.prompt_title or opts.sort_by

    local prepared = nil
    -- When no notes provided, use incremental cached scan for both paths
    -- and wikilinks in a single pass. First open ~1.6s, subsequent <100ms.
    local wikilinks_map = opts._wikilinks_map
    if not opts.notes and not wikilinks_map then
        if opts.sort_by == "mtime" then
            prepared = default_prep.get_or_prepare()
            opts.notes = prepared.notes
        else
            local Scanner = require("vault.scanner")
            local raw_paths, wl_map = Scanner.paths_and_wikilinks_cached()
            opts.notes = require("vault.notes").from_paths(raw_paths)
            wikilinks_map = wl_map
        end
    else
        opts.notes = opts.notes or require("vault.notes")()
        -- Load wikilinks once (no suggestions — picker only needs counts)
        if not wikilinks_map then
            wikilinks_map = link_index.wikilinks()
        end
    end

    local results = prepared and prepared.results or opts.notes:list()
    if next(results) == nil then
        log.info("No notes found")
        return
    end

    local layout = vault_layouts.notes()
    local ui_height, ui_width = vault_layouts.ui_size()
    local steps = math.min(ui_height, vim.tbl_count(results))

    local hl_name = "VaultNoteContent"
    local colors = vault_hl.setup(hl_name, steps, { "Boolean", "Comment", "Normal", "String" })

    local link_counts = prepared and prepared.link_counts
        or note_stats.collect(results, wikilinks_map)
    local columns = note_columns.resolve(opts.columns)
    local render_ctx = {
        colors = colors,
        hl_name = hl_name,
        link_counts = link_counts,
        steps = steps,
        ui_width = ui_width,
        layout = layout,
    }
    local column_widths = note_columns.measure(results, columns, render_ctx)
    local displayer = entry_display.create({
        separator = " ",
        items = note_columns.items(columns, column_widths),
    })

    local make_display = function(entry)
        local note = entry.value
        return displayer(note_columns.cells(note, columns, render_ctx))
    end

    local entry_maker = function(note)
        local stem = vim.fn.fnamemodify(note.data.path, ":t:r")
        return {
            value = note,
            ordinal = stem .. " " .. (note.data.slug or "") .. " " .. (note.data.content or ""),
            display = make_display,
            filename = note.data.path,
        }
    end

    if opts.sort_by == "ctime" then
        -- Sort by semantic creation date from frontmatter (note.data.created).
        table.sort(results, function(a, b)
            local ac = a.data.created or ""
            local bc = b.data.created or ""
            return ac < bc
        end)
    elseif opts.sort_by == "mtime" and not prepared then
        -- Pre-compute file modification timestamps to avoid O(n log n) stat()
        -- syscalls inside the comparator (getftime is a syscall per call).
        local ftime = {} --- @type table<string, integer>
        for _, note in ipairs(results) do
            ftime[note.data.path] = vim.fn.getftime(note.data.path)
        end
        table.sort(results, function(a, b)
            return ftime[a.data.path] < ftime[b.data.path]
        end)
    elseif opts.sort_by == "title" then
        table.sort(results, function(a, b)
            return a.data.title < b.data.title
        end)
    elseif opts.sort_by == "slug" then
        table.sort(results, function(a, b)
            return a.data.slug < b.data.slug
        end)
    elseif opts.sort_by == "path" then
        table.sort(results, function(a, b)
            return a.data.path < b.data.path
        end)
    end

    local finder = finders.new_table({
        results = results,
        entry_maker = entry_maker,
    })

    -- Custom sorter: wraps fzy but boosts exact stem/title matches to the top.
    local fzy = sorters.get_fzy_sorter()
    local custom_sorter = sorters.new({
        scoring_function = function(_, prompt, line, entry)
            if prompt == "" or prompt == nil then
                return 1
            end
            local fzy_score = fzy.scoring_function(fzy, prompt, line, entry)
            if fzy_score <= 0 then
                return -1
            end

            local note = entry.value
            if note and note.data then
                local stem = vim.fn.fnamemodify(note.data.path or "", ":t:r"):lower()
                local query = prompt:lower()
                if stem == query then
                    return 0.001
                elseif stem:find(query, 1, true) then
                    return math.min(fzy_score, 0.01)
                end
            end
            return fzy_score
        end,
        highlighter = fzy.highlighter,
    })

    local picker_opts = {
        prompt_title = opts.prompt_title,
        finder = finder,
        sorter = custom_sorter,
        previewer = vault_previewers.notes or nil,
        attach_mappings = vault_hl.make_attach_mappings(vault_mappings.notes, hl_name, colors),
        on_input_filter_cb = make_filter(results, entry_maker),
    }
    local picker = pickers.new(layout, picker_opts)
    vault_state.set_global_key("picker", picker)
    return picker
end
