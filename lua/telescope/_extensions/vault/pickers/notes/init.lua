--- @class telescope_popup_options.vault.Notes: telescope_popup_options
--- @field notes? vault.Notes
--- @field sort_by? string
--- @field columns? (string|vault.TelescopeNotesColumnSpec)[]

---@class vault.TelescopeNotesReadyEvent
---@field result_count integer
---@field state "loading"|"ready"|"error"

---@param opts? telescope_popup_options.vault.Notes|table<string, any>
---@return Picker?
return function(opts)
    local vault_state = require("vault.core.state")
    local entry_display = require("telescope.pickers.entry_display")
    local finders = require("telescope.finders")
    local pickers = require("telescope.pickers")
    local sorters = require("telescope.sorters")
    local telescope_config = require("telescope.config")
    local log = require("vault.log").scope("telescope")
    local vault_previewers = require("telescope._extensions.vault.previewers")
    local vault_mappings = require("telescope._extensions.vault.mappings")
    local vault_layouts = require("telescope._extensions.vault.layouts")
    local vault_hl = require("telescope._extensions.vault.highlights")
    local make_filter = require("telescope._extensions.vault.on_input_filter")
    local default_prep = require("telescope._extensions.vault.pickers.notes.default_prep")
    local progressive = require("telescope._extensions.vault.pickers.notes.progressive")
    local link_index = require("vault.notes.link_index")
    local note_stats = require("telescope._extensions.vault.pickers.notes.stats")
    local note_columns = require("telescope._extensions.vault.pickers.notes.columns")

    opts = opts or {}
    opts.sort_by = opts.sort_by or "mtime"
    opts.prompt_title = opts.prompt_title or opts.sort_by

    local layout = vault_layouts.notes()
    local ui_height, ui_width = vault_layouts.ui_size()
    local steps = math.max(1, tonumber(ui_height) or 1)
    local hl_name = "VaultNoteContent"
    local colors = vault_hl.setup(hl_name, steps, { "Boolean", "Comment", "Normal", "String" })

    ---@return Sorter
    local function base_sorter()
        local generic_sorter = telescope_config.values and telescope_config.values.generic_sorter
        if type(generic_sorter) == "function" then
            return generic_sorter({})
        end
        return sorters.get_fzy_sorter()
    end

    ---@param results vault.Note[]
    ---@param prepared boolean
    ---@return nil
    local function sort_results(results, prepared)
        if opts.sort_by == "ctime" then
            table.sort(results, function(a, b)
                local ac = a.data.created or ""
                local bc = b.data.created or ""
                return ac < bc
            end)
            return
        end

        if opts.sort_by == "mtime" and not prepared then
            local ftime = {} --- @type table<string, integer>
            for _, note in ipairs(results) do
                ftime[note.data.path] = vim.fn.getftime(note.data.path)
            end
            table.sort(results, function(a, b)
                return ftime[a.data.path] < ftime[b.data.path]
            end)
            return
        end

        if opts.sort_by == "title" then
            table.sort(results, function(a, b)
                return a.data.title < b.data.title
            end)
            return
        end

        if opts.sort_by == "slug" then
            table.sort(results, function(a, b)
                return a.data.slug < b.data.slug
            end)
            return
        end

        if opts.sort_by == "path" then
            table.sort(results, function(a, b)
                return a.data.path < b.data.path
            end)
        end
    end

    ---@param results vault.Note[]
    ---@param link_counts table<string, vault.NotePickerLinkCounts>
    ---@return fun(note: vault.Note): table
    local function build_entry_maker(results, link_counts)
        local columns = note_columns.resolve(opts.columns)
        local render_ctx = {
            colors = colors,
            hl_name = hl_name,
            layout = layout,
            link_counts = link_counts,
            steps = math.max(1, math.min(steps, vim.tbl_count(results))),
            ui_width = ui_width,
        }
        local column_widths = note_columns.measure(results, columns, render_ctx)
        local displayer = entry_display.create({
            separator = " ",
            items = note_columns.items(columns, column_widths),
        })

        local function make_display(entry)
            local note = entry.value
            return displayer(note_columns.cells(note, columns, render_ctx))
        end

        return function(note)
            local stem = vim.fn.fnamemodify(note.data.path, ":t:r")
            return {
                value = note,
                ordinal = stem .. " " .. (note.data.slug or "") .. " " .. (note.data.content or ""),
                display = make_display,
                filename = note.data.path,
            }
        end
    end

    ---@return { results: vault.Note[], entry_maker: fun(note: vault.Note): table }
    local function prepare_picker_data()
        local source = type(opts._prepare) == "function" and opts._prepare() or {}
        if type(source) ~= "table" then
            source = {}
        end

        local prepared = source.prepared
        local notes = opts.notes or source.notes
        local wikilinks_map = opts._wikilinks_map or source._wikilinks_map or source.wikilinks_map

        if not notes and type(opts._notes_provider) == "function" then
            notes = opts._notes_provider()
        end

        if not notes and not wikilinks_map then
            if opts.sort_by == "mtime" and type(opts._prepare) ~= "function" then
                prepared = default_prep.get_or_prepare()
                notes = prepared.notes
            else
                local Scanner = require("vault.scanner")
                local raw_paths, wl_map = Scanner.paths_and_wikilinks_cached()
                notes = require("vault.notes").from_paths(raw_paths)
                wikilinks_map = wl_map
            end
        else
            notes = notes or require("vault.notes")()
            if not wikilinks_map then
                wikilinks_map = link_index.wikilinks()
            end
        end

        local results = prepared and prepared.results or notes:list()
        local result_count = vim.tbl_count(results)
        if result_count == 0 then
            log.info("No notes found")
            return {
                results = {},
                entry_maker = build_entry_maker({}, {}),
            }
        end

        local link_counts = prepared and prepared.link_counts
            or note_stats.collect(results, wikilinks_map)
        sort_results(results, prepared ~= nil)

        return {
            results = results,
            entry_maker = build_entry_maker(results, link_counts),
        }
    end

    if opts._measure_ready_only == true then
        return prepare_picker_data()
    end

    local fuzzy = base_sorter()
    local custom_sorter = sorters.new({
        init = function()
            if type(fuzzy._init) == "function" then
                fuzzy:_init()
            elseif type(fuzzy.init) == "function" then
                fuzzy:init()
            end
        end,
        start = function(_, prompt)
            if type(fuzzy._start) == "function" then
                fuzzy:_start(prompt)
            elseif type(fuzzy.start) == "function" then
                fuzzy:start(prompt)
            end
        end,
        finish = function(_, prompt)
            if type(fuzzy._finish) == "function" then
                fuzzy:_finish(prompt)
            elseif type(fuzzy.finish) == "function" then
                fuzzy:finish(prompt)
            end
        end,
        destroy = function()
            if type(fuzzy._destroy) == "function" then
                fuzzy:_destroy()
            elseif type(fuzzy.destroy) == "function" then
                fuzzy:destroy()
            end
        end,
        scoring_function = function(_, prompt, line, entry)
            if prompt == "" or prompt == nil then
                return 1
            end

            if entry and entry.value and entry.value.kind == "status" then
                return 0
            end

            local fuzzy_score = fuzzy.scoring_function(fuzzy, prompt, line, entry)
            if fuzzy_score <= 0 then
                return -1
            end

            local note = entry.value
            if note and note.data then
                local stem = vim.fn.fnamemodify(note.data.path or "", ":t:r"):lower()
                local query = prompt:lower()
                if stem == query then
                    return 0.001
                end
                if stem:find(query, 1, true) then
                    return math.min(fuzzy_score, 0.01)
                end
            end

            return fuzzy_score
        end,
        highlighter = function(_, prompt, display)
            if type(fuzzy.highlighter) ~= "function" then
                return {}
            end

            return fuzzy.highlighter(fuzzy, prompt, display)
        end,
    })

    local base_attach = vault_hl.make_attach_mappings(vault_mappings.notes, hl_name, colors)
    local picker
    local should_use_dynamic = opts._dynamic == true
        or type(opts._prepare) == "function"
        or type(opts._notes_provider) == "function"
        or opts.notes == nil

    local picker_opts = {
        prompt_title = opts.prompt_title,
        sorter = custom_sorter,
    }

    if should_use_dynamic then
        local session = progressive.new({
            empty_prompt_limit = opts.empty_prompt_limit,
            loading_message = opts.loading_message,
            prepare = prepare_picker_data,
            prompt_result_limit = opts.prompt_result_limit,
        })

        picker_opts.finder = session:finder()
        picker_opts.previewer = vault_previewers.notes or nil
        picker_opts.get_status_text = function()
            if session.state ~= "ready" then
                return " collecting"
            end

            if session.count_pending then
                return string.format(" ... / %d", #session.results)
            end

            return string.format(" %d / %d", session.last_matched_count or 0, #session.results)
        end
        picker_opts.attach_mappings = function(prompt_bufnr, map)
            local attached = base_attach(prompt_bufnr, map)
            session:start(picker, {
                after_refresh = function(current_picker)
                    if type(opts._on_ready) == "function" then
                        opts._on_ready({
                            result_count = #session.results,
                            state = session.state,
                        })
                    end
                end,
            })
            return attached
        end
    else
        local prepared = prepare_picker_data()
        if #prepared.results == 0 then
            return
        end

        picker_opts.finder = finders.new_table({
            results = prepared.results,
            entry_maker = prepared.entry_maker,
        })
        picker_opts.previewer = vault_previewers.notes or nil
        picker_opts.attach_mappings = base_attach
        picker_opts.on_input_filter_cb = make_filter(prepared.results, prepared.entry_maker)
    end

    picker = pickers.new(layout, picker_opts)
    vault_state.set_global_key("picker", picker)
    return picker
end
