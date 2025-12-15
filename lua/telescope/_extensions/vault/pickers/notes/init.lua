--[[



--]]
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
    local Log = require("plenary.log")
    local Gradient = require("gradient")
    local Error = require("vault.utils.error")
    local utils = require("vault.utils")
    local vault_previewers = require("telescope._extensions.vault.previewers")
    local vault_mappings = require("telescope._extensions.vault.mappings")
    local vault_layouts = require("telescope._extensions.vault.layouts")

    opts = opts or {}
    opts.notes = opts.notes or require("vault.notes")()
    opts.sort_by = opts.sort_by or "mtime"

    --- @type vault.Note[]
    local results = opts.notes:list()
    if next(results) == nil then
        Log.info("No notes found in vault")
        return
    end

    local prompt_title = opts.sort_by

    --- @type integer
    local ui_height = vim.o.lines
    if #vim.api.nvim_list_uis() > 0 then
        ui_height = vim.api.nvim_list_uis()[1].height
    end

    local steps = math.min(ui_height, vim.tbl_count(results))

    -- Gradient-based highlighting
    local hl_name = "VaultNoteContent"
    local colors = nil
    local ok, maybe_colors = pcall(function()
        return Gradient.from_stops(steps, "Boolean", "Comment", "Normal", "String")
    end)
    if ok and type(maybe_colors) == "table" then
        colors = maybe_colors
        for i, color in ipairs(colors) do
            pcall(vim.api.nvim_set_hl, 0, hl_name .. tostring(i), { fg = color })
        end
    else
        -- If gradient failed, keep colors = nil and fallback to standard groups
        colors = nil
    end

    --- @type string
    local col_2 = ""
    local col_2_maxwidth = 0

    for _, note in ipairs(results) do
        local relpath = note.data.relpath
        if utils.match(relpath, "/", "contains", false) then
            col_2 = string.match(relpath, "(.*/)") or ""
        end
        local col2_width = col_2:len()
        if col2_width > col_2_maxwidth then
            col_2_maxwidth = col2_width
        end
    end

    local make_display = function(entry)
        local col_1_hl_name = "TelescopeResultsNormal"
        --- @type vault.Note
        local note = entry.value

        --- --
        local content = note.data.content or ""
        -- Gradient index calculation (fallbacks to default group)
        if colors then
            local content_chars_count = #content
            local index = math.min(math.floor(content_chars_count / 16), steps)
            if index == 0 then
                index = 1
            end
            col_1_hl_name = hl_name .. tostring(index)
        else
            col_1_hl_name = "TelescopeResultsNormal"
        end


        --- --
        -- Display dir before note name
        col_2 = vim.fn.fnamemodify(note.data.slug, ":h")
        local col_2_hl_name = "TelescopeResultsComment"

        -- Alternative for display_group
        -- if note.data.frontmatter.data.type then
        --     display_group = note.data.frontmatter.data.type
        -- end

        --- --
        --- @type vault.stem
        local col_3 = vim.fn.fnamemodify(note.data.path, ":t:r")
        local col_3_hl_name = col_1_hl_name

        --- -
        --- @type vault.TelescopeDisplayerConfig
        --- @see entry_display.create
        local displayer_config = {
            separator = " ",
            items = {
                { width = 2 },
                { width = col_2_maxwidth },
                { remaining = true },
                { remaining = true },
            },
        }

        --- @type fun(self: table, picker: any): string, table
        local displayer = entry_display.create(displayer_config)

        local display_value = {
            { "██", col_1_hl_name },
            { col_2, col_2_hl_name },
            { col_3, col_3_hl_name },
        }

        return displayer(display_value)
    end

    --- @param note vault.Note
    --- @return vault.TelescopeEntry
    local entry_maker = function(note)
        return {
            value = note,
            ordinal = note.data.path .. " " .. (note.data.content or ""),
            display = make_display,
            filename = note.data.path,
        }
    end

    if opts.sort_by == "title" then
        table.sort(results, function(a, b)
            return a.data.title < b.data.title
        end)
    elseif opts.sort_by == "ctime" then
        table.sort(results, function(a, b)
            local a_ctime = vim.fn.getftime(a.data.path)
            local b_ctime = vim.fn.getftime(b.data.path)
            return a_ctime < b_ctime
        end)
    elseif opts.sort_by == "mtime" then
        table.sort(results, function(a, b)
            local a_mtime = vim.fn.getftime(a.data.path)
            local b_mtime = vim.fn.getftime(b.data.path)
            return a_mtime < b_mtime
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

    -- interactive in-line filter callback (supports trailing / pattern and negative prefix -)
    local on_input_filter_cb = function(prompt)
        local picker = vault_state.get_global_key("picker")
        local is_negative = false

        local function default_finder()
            local new_finder = finders.new_table({
                results = results,
                entry_maker = entry_maker,
            })
            picker.finder:close() -- TODO: Find a way to close picker without closing previewer
            picker.finder = new_finder

            vault_state.set_global_key("prompt", prompt)
            return {
                prompt = prompt or "",
            }
        end

        if prompt:sub(-1) ~= "/" then
            return default_finder()
        end

        if prompt:sub(1, 1) == "-" then
            is_negative = true
        end

        local pattern = prompt:sub(1, -2)
        pattern = pattern:sub(2)
        if is_negative == true then
            pattern = pattern:sub(2)
        end
        local new_results = {}
        local results_without_excluded = {}

        for _, entry in ipairs(picker.finder.results) do
            local note = entry.value
            local slug = note.data.slug
            if slug == nil then
                goto continue
            end
            local is_valid_regex = pcall(vim.fn.match, slug, pattern)
            if is_valid_regex == false then
                goto continue
            end
            if vim.fn.match(slug, pattern) ~= -1 then
                table.insert(new_results, note)
                if is_negative == true then
                    table.insert(results_without_excluded, note)
                end
            end
            ::continue::
        end
        if next(new_results) == nil then
            return default_finder()
        elseif is_negative == true then
            new_results = {}
            for _, entry in ipairs(picker.finder.results) do -- TODO: Use results_without_excluded
                if not vim.tbl_contains(results_without_excluded, entry.value) then
                    table.insert(new_results, entry.value)
                end
            end
        end

        local new_finder = finders.new_table({
            results = new_results,
            entry_maker = entry_maker,
        })
        picker.finder:close()
        picker.finder = new_finder

        vault_state.set_global_key("prompt", prompt)

        return {
            prompt = "",
        }
    end

    -- Attach mappings with cleanup for highlight groups to avoid leakage
    local attach_mappings = function(prompt_bufnr, map)
        -- Ensure original mappings are preserved if provided
        if type(vault_mappings.notes) == "function" then
            local ok, res = pcall(vault_mappings.notes, prompt_bufnr, map)
            if not ok then
                -- ignore mapping errors
            end
        end

        -- Cleanup highlights when picker buffer is closed
        local function cleanup()
            if colors then
                for i = 1, #colors do
                    pcall(vim.api.nvim_set_hl, 0, hl_name .. tostring(i), {})
                end
            end
        end

        -- Register BufWipeout autocmd for the prompt buffer to cleanup highlights
        pcall(vim.api.nvim_create_autocmd, "BufWipeout", {
            buffer = prompt_bufnr,
            once = true,
            callback = cleanup,
        })

        return true
    end

    local picker_opts = {
        prompt_title = prompt_title,
        finder = finder,
        sorter = sorters.get_fzy_sorter(),
        previewer = vault_previewers.notes or nil,
        attach_mappings = attach_mappings,
        on_input_filter_cb = on_input_filter_cb,
    }
    local picker = pickers.new(vault_layouts.notes(), picker_opts)

    vault_state.set_global_key("picker", picker)
    return picker
end
