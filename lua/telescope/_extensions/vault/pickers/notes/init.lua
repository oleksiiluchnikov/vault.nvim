--- @class telescope_popup_options.vault.Notes: telescope_popup_options
--- @field notes? vault.Notes
--- @field sort_by? string

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
    local utils = require("vault.utils")
    local vault_previewers = require("telescope._extensions.vault.previewers")
    local vault_mappings = require("telescope._extensions.vault.mappings")
    local vault_layouts = require("telescope._extensions.vault.layouts")
    local vault_hl = require("telescope._extensions.vault.highlights")
    local make_filter = require("telescope._extensions.vault.on_input_filter")

    opts = opts or {}
    opts.notes = opts.notes or require("vault.notes")()
    opts.sort_by = opts.sort_by or "mtime"
    opts.prompt_title = opts.prompt_title or opts.sort_by

    local results = opts.notes:list()
    if next(results) == nil then
        log.info("No notes found")
        return
    end

    local ui_height = vim.o.lines
    if #vim.api.nvim_list_uis() > 0 then
        ui_height = vim.api.nvim_list_uis()[1].height
    end
    local steps = math.min(ui_height, vim.tbl_count(results))

    local hl_name = "VaultNoteContent"
    local colors = vault_hl.setup(hl_name, steps, { "Boolean", "Comment", "Normal", "String" })

    local col_2_maxwidth = 0
    for _, note in ipairs(results) do
        local relpath = note.data.relpath
        local col_2 = ""
        if utils.match(relpath, "/", "contains", false) then
            col_2 = string.match(relpath, "(.*/)") or ""
        end
        if col_2:len() > col_2_maxwidth then
            col_2_maxwidth = col_2:len()
        end
    end

    local make_display = function(entry)
        local col_1_hl_name = "TelescopeResultsNormal"
        local note = entry.value
        local content = note.data.content or ""

        if colors then
            local content_chars_count = #content
            local index = math.min(math.floor(content_chars_count / 16), steps)
            if index == 0 then index = 1 end
            col_1_hl_name = hl_name .. tostring(index)
        end

        local col_2 = vim.fn.fnamemodify(note.data.slug, ":h")
        local col_3 = vim.fn.fnamemodify(note.data.path, ":t:r")

        local displayer = entry_display.create({
            separator = " ",
            items = {
                { width = 2 },
                { width = col_2_maxwidth },
                { remaining = true },
            },
        })

        return displayer({
            { "██", col_1_hl_name },
            { col_2, "TelescopeResultsComment" },
            { col_3, col_1_hl_name },
        })
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

    if opts.sort_by == "title" then
        table.sort(results, function(a, b) return a.data.title < b.data.title end)
    elseif opts.sort_by == "ctime" then
        table.sort(results, function(a, b) return vim.fn.getftime(a.data.path) < vim.fn.getftime(b.data.path) end)
    elseif opts.sort_by == "mtime" then
        table.sort(results, function(a, b) return vim.fn.getftime(a.data.path) < vim.fn.getftime(b.data.path) end)
    elseif opts.sort_by == "slug" then
        table.sort(results, function(a, b) return a.data.slug < b.data.slug end)
    elseif opts.sort_by == "path" then
        table.sort(results, function(a, b) return a.data.path < b.data.path end)
    end

    local finder = finders.new_table({
        results = results,
        entry_maker = entry_maker,
    })

    -- Custom sorter: wraps fzy but boosts exact stem/title matches to the top.
    local fzy = sorters.get_fzy_sorter()
    local custom_sorter = sorters.new({
        scoring_function = function(self, prompt, line, entry)
            if prompt == "" or prompt == nil then return 1 end
            local fzy_score = fzy.scoring_function(fzy, prompt, line, entry)
            if fzy_score <= 0 then return -1 end

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
    local picker = pickers.new(vault_layouts.notes(), picker_opts)
    vault_state.set_global_key("picker", picker)
    return picker
end
