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
    local previewers = require("telescope.previewers")
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

    -- Helper: normalize a path-like value (string or table) into a string or nil
    local function normalize_path(val)
        if not val then
            return nil
        end
        if type(val) == "string" then
            return val
        end
        if type(val) == "table" then
            -- try common cases: first element is a string, or a table with a 'path' key
            if #val > 0 and type(val[1]) == "string" then
                return val[1]
            elseif type(val.path) == "string" then
                return val.path
            end
        end
        return nil
    end

    -- Make the display for each entry
    local make_display = function(entry)
        -- entry may be a telescope entry (with .value) or raw wikilink
        local wikilink = (entry and entry.value) and entry.value or entry
        local slug = wikilink.data and wikilink.data.slug or "<unknown>"
        local context = wikilink.data and (wikilink.data.context or wikilink.data.excerpt or "")
            or ""
        local target_raw = wikilink.data and wikilink.data.target or nil
        local target = normalize_path(target_raw)

        -- resolved if target exists and file is readable
        local resolved = false
        if target and type(target) == "string" and target ~= "" then
            resolved = vim.fn.filereadable(target) == 1
        end

        local mark = resolved and "✓" or "○"
        local mark_hl = resolved and "TelescopeResultsDiffAdd" or "TelescopeResultsDiffChange"

        local backlinks_count = 0
        if wikilink.data and type(wikilink.data.backlinks) == "table" then
            backlinks_count = #wikilink.data.backlinks
        elseif type(wikilinks.backlink_count) == "function" then
            local ok, res = pcall(function()
                return wikilinks:backlink_count(wikilink)
            end)
            if ok and type(res) == "number" then
                backlinks_count = res
            end
        end

        local col_1_hl = "TelescopeResultsNormal"
        if colors then
            local chars = #context
            local idx = math.min(math.max(1, math.floor(chars / 16)), steps)
            col_1_hl = hl_base .. tostring(idx)
        end

        local displayer = entry_display.create({
            separator = " ",
            items = {
                { width = 2 }, -- mark
                { width = 4 }, -- backlinks count
                { width = slug_max + 2 },
                { remaining = true },
            },
        })

        local display_value = {
            { mark, mark_hl },
            { tostring(backlinks_count), "TelescopeResultsComment" },
            { slug, col_1_hl },
            { (context:gsub("\n", " "):sub(1, 120)), "TelescopeResultsComment" },
        }
        return displayer(display_value)
    end

    local entry_maker = function(entry)
        local slug = (entry.data and entry.data.slug) or ""
        local context = (entry.data and (entry.data.context or entry.data.excerpt or "")) or ""

        -- normalize path/target so we only ever set string fields for Telescope helpers
        local path_field = nil
        local filename = nil
        if entry.data then
            local raw_path = entry.data.path
            local raw_target = entry.data.target
            local np = normalize_path(raw_target) or normalize_path(raw_path)
            if np and type(np) == "string" and np ~= "" then
                path_field = np
                -- filename should be the source file if available
                if type(raw_path) == "string" then
                    filename = raw_path
                end
            end
        end

        return {
            value = entry,
            ordinal = slug .. " " .. context,
            display = make_display,
            filename = filename,
            path = path_field,
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
            if a.data and a.data.path then
                local ap = normalize_path(a.data.path)
                if ap then
                    a_m = vim.fn.getftime(ap)
                end
            end
            if b.data and b.data.path then
                local bp = normalize_path(b.data.path)
                if bp then
                    b_m = vim.fn.getftime(bp)
                end
            end
            return a_m < b_m
        end)
    elseif opts.sort_by == "resolved" then
        table.sort(results, function(a, b)
            local ta = a.data and a.data.target or nil
            local tb = b.data and b.data.target or nil
            local ap = normalize_path(ta)
            local bp = normalize_path(tb)
            local ra = (ap and type(ap) == "string" and vim.fn.filereadable(ap) == 1) and 1 or 0
            local rb = (bp and type(bp) == "string" and vim.fn.filereadable(bp) == 1) and 1 or 0
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

    -- Previewer: show target file if available, otherwise show the source file and context line
    local previewer = previewers.vim_buffer_cat.new({
        get_buffer_by_name = function(_, entry)
            local bufnr = vim.api.nvim_create_buf(false, true)
            local lines = {}
            local ok = false
            -- -- entry may be telescope entry or raw wikilink
            -- local wl = (entry and entry.value) and entry.value or entry
            -- local target_raw = wl and wl.data and wl.data.target or nil
            -- local target = normalize_path(target_raw)
            -- if target and target ~= "" then
            --     ok, lines = pcall(vim.fn.readfile, target)
            -- end
            -- if not ok or not lines or #lines == 0 then
            --     -- Fallback: show the source note and try to highlight where link came from
            --     local src_raw = wl and wl.data and wl.data.path or nil
            --     local src = normalize_path(src_raw)
            --     if type(src) == "string" and src ~= "" then
            --         pcall(function()
            --             lines = vim.fn.readfile(src)
            --         end)
            --     else
            --         lines = { "(no preview available)" }
            --     end
            -- end
            -- if type(bufnr) ~= "number" then
            --     error("bufnr is not a number")
            -- end
            -- pcall(vim.api.nvim_buf_set_lines, bufnr, 0, -1, false, lines)
            -- pcall(vim.api.nvim_buf_set_option, bufnr, "filetype", "markdown")
            return bufnr
        end,
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
            -- actions.close(prompt_bufnr)
            local selection = action_state.get_selected_entry()
            -- P(selection)
            -- {
            --   display = <function 1>,
            --   index = 2,
            --   ordinal = "2016-08-12 Friday ",
            --   value = {
            --     class = {
            --       __meta = <1>{
            --         __index = <table 1>,
            --         __tostring = <function 2>,
            --         init = <function 3>,
            --         is_instance_of = <function 4>
            --       },
            --       __properties = {
            --         __tostring = <function 2>,
            --         init = <function 3>
            --       },
            --       name = "VaultWikilink",
            --       static = <2>{
            --         extend = <function 5>,
            --         is_subclass_of = <function 6>,
            --         new = <function 7>,
            --         <metatable> = {
            --           __index = <function 8>
            --         }
            --       },
            --       [<3>{ "<vault.utils.object:subclasses>" }] = {
            --         <metatable> = {
            --           __mode = "k"
            --         }
            --       },
            --       <metatable> = {
            --         __call = <function 9>,
            --         __index = <table 2>,
            --         __name = "VaultWikilink",
            --         __newindex = <function 10>,
            --         __tostring = <function 11>
            --       }
            --     },
            --     data = {
            --       aliases = {
            --         ["2016-08-12 Friday"] = true
            --       },
            --       class = {
            --         __meta = <4>{
            --           __index = <table 4>,
            --           __tostring = <function 12>,
            --           init = <function 13>,
            --           is_instance_of = <function 4>
            --         },
            --         __properties = {
            --           __tostring = <function 12>,
            --           init = <function 13>
            --         },
            --         name = "VaultWikilink",
            --         static = <5>{
            --           extend = <function 14>,
            --           is_subclass_of = <function 6>,
            --           new = <function 15>,
            --           <metatable> = {
            --             __index = <function 16>
            --           }
            --         },
            --         [<table 3>] = {
            --           <metatable> = {
            --             __mode = "k"
            --           }
            --         },
            --         <metatable> = {
            --           __call = <function 9>,
            --           __index = <table 5>,
            --           __name = "VaultWikilink",
            --           __newindex = <function 10>,
            --           __tostring = <function 11>
            --         }
            --       },
            --       count = 1,
            --       embedded = false,
            --       slug = "2016-08-12 Friday",
            --       sources = {
            --         ["drafts/20160812001203 - New Note"] = {
            --           [18] = {
            --             end_lnum = 18,
            --             lnum = 18
            --           }
            --         }
            --       },
            --       stem = "2016-08-12 Friday",
            --       variants = {
            --         ["2016-08-12 Friday"] = true
            --       },
            --       <metatable> = <table 4>
            --     },
            --     <metatable> = <table 1>
            --   }
            -- }
            local target = require("vault.utils").slug_to_path(selection.value.data.slug)
            -- print(target)
            vim.notify("Selected wikilink target: " .. tostring(target), vim.log.levels.INFO)
            -- if target and target ~= "" then
            --     vim.cmd("edit " .. vim.fn.fnameescape(target))
            -- end
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
        -- previewer = previewer,
        attach_mappings = attach_mappings,
        on_input_filter_cb = on_input_filter_cb,
        sorting_strategy = "ascending",
    }

    local picker = pickers.new({}, picker_opts)
    vault_state.set_global_key("picker", picker)
    return picker
end
