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

    --- Rewrite [[old_slug]] → [[new_slug]] across all source files for a wikilink.
    --- @param wl vault.Wikilink
    --- @param new_slug string
    --- @return number patched Number of files patched
    local function rewrite_wikilink(wl, new_slug)
        local old_slug = wl.data and wl.data.slug or ""
        if old_slug == "" or old_slug == new_slug then
            return 0
        end

        local sources = wl.data and wl.data.sources or {}
        local patched = 0

        -- Build all pattern variants to replace (stem, slug, with/without alias/heading)
        local old_stem = wl.data.stem or old_slug:match("([^/]+)$") or old_slug
        local old_patterns = {}
        -- Collect unique patterns to search for
        for _, pat in ipairs({ old_slug, old_stem }) do
            old_patterns[pat] = true
        end

        for source_slug, _ in pairs(sources) do
            local source_path = utils.slug_to_path(source_slug)
            if vim.fn.filereadable(source_path) == 1 then
                local lines = vim.fn.readfile(source_path)
                local changed = false
                for i, line in ipairs(lines) do
                    local new_line = line
                    for old_pat, _ in pairs(old_patterns) do
                        -- Replace [[old_pat]] → [[new_slug]] (with optional heading/alias preserved)
                        local escaped = old_pat:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
                        new_line = new_line:gsub(
                            "%[%[" .. escaped .. "(%]%])",
                            "[[" .. new_slug .. "%1"
                        )
                        new_line = new_line:gsub(
                            "%[%[" .. escaped .. "([#|])",
                            "[[" .. new_slug .. "%1"
                        )
                    end
                    if new_line ~= line then
                        lines[i] = new_line
                        changed = true
                    end
                end
                if changed then
                    vim.fn.writefile(lines, source_path)
                    patched = patched + 1
                end
            end
        end

        return patched
    end

    --- Remove the current entry from results and refresh the picker.
    --- @param picker_obj table Telescope picker
    --- @param wl vault.Wikilink The wikilink to remove
    local function remove_and_refresh(picker_obj, wl)
        -- Remove from results in-place
        for i = #results, 1, -1 do
            if results[i] == wl then
                table.remove(results, i)
                break
            end
        end

        if picker_obj and picker_obj.finder then
            local new_finder = finders.new_table({ results = results, entry_maker = entry_maker })
            picker_obj:refresh(new_finder, { reset_prompt = false })
        end
    end

    local attach_mappings = function(prompt_bufnr, map)
        local actions = require("telescope.actions")
        local action_state = require("telescope.actions.state")

        -- <CR> — open target (resolved) or create note (unresolved)
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
                local target = utils.slug_to_path(slug)
                vim.cmd("edit " .. vim.fn.fnameescape(target))
            else
                local Note = require("vault.notes.note")
                local path = utils.slug_to_path(slug)
                local note = Note(path)
                note:write(path)
                note:edit()
            end
        end)

        -- gr — resolve: close picker, show vim.ui.select, apply, reopen picker.
        -- This avoids the float-vs-float conflict between Telescope and dressing.nvim.
        local function resolve_action()
            local selection = action_state.get_selected_entry()
            if not selection or not selection.value then
                return
            end
            local wl = selection.value
            local slug = wl.data and wl.data.slug or ""
            if slug == "" then
                return
            end

            if is_resolved(wl) then
                vim.notify("[vault] Already resolved -> " .. (wl.data.target or ""), vim.log.levels.INFO)
                return
            end

            -- Build choices from strategy-grouped suggestions
            local choices = {}
            local suggestions = wl.data and wl.data.suggestions or {}
            local strategy_order = { "jaro_winkler", "levenshtein", "contains", "prefix" }
            local strategy_labels = {
                jaro_winkler = "fuzzy",
                levenshtein = "edit-dist",
                contains = "substr",
                prefix = "prefix",
            }
            local seen_slugs = {}
            for _, strategy in ipairs(strategy_order) do
                local candidates = suggestions[strategy]
                if type(candidates) == "table" then
                    local strat_label = strategy_labels[strategy] or strategy
                    for _, s in ipairs(candidates) do
                        local cand_slug = s.slug or s[1] or ""
                        if cand_slug ~= "" and not seen_slugs[cand_slug] then
                            seen_slugs[cand_slug] = true
                            local score = s.score or s[2] or 0
                            local pct = math.floor(score * 100 + 0.5)
                            choices[#choices + 1] = {
                                label = cand_slug .. " (" .. pct .. "% " .. strat_label .. ")",
                                slug = cand_slug,
                            }
                        end
                    end
                end
            end
            choices[#choices + 1] = { label = "Create new note: " .. slug, slug = nil, action = "create" }
            choices[#choices + 1] = { label = "Skip", slug = nil, action = "skip" }

            local labels = {}
            for _, c in ipairs(choices) do
                labels[#labels + 1] = c.label
            end

            -- Close the picker BEFORE vim.ui.select so dressing.nvim doesn't
            -- destroy the Telescope prompt buffer.
            actions.close(prompt_bufnr)

            vim.schedule(function()
                vim.ui.select(labels, {
                    prompt = "Resolve [[" .. slug .. "]]:",
                }, function(choice, idx)
                    local function reopen_picker()
                        vim.schedule(function()
                            local picker_mod = require("telescope._extensions.vault.pickers.wikilinks")
                            local p = picker_mod({
                                wikilinks = wikilinks,
                                _results = results,
                                sort_by = opts.sort_by,
                                show_resolved = opts.show_resolved,
                            })
                            if p then p:find() end
                        end)
                    end

                    if not choice or not idx then
                        reopen_picker()
                        return
                    end

                    local picked = choices[idx]

                    if picked.action ~= "skip" then
                        if picked.action == "create" then
                            local Note = require("vault.notes.note")
                            local path = utils.slug_to_path(slug)
                            local note = Note(path)
                            note:write(path)
                            vim.notify("[vault] Created: " .. slug, vim.log.levels.INFO)
                        else
                            local new_slug = picked.slug
                            local patched = rewrite_wikilink(wl, new_slug)
                            vim.notify(
                                "[vault] [[" .. slug .. "]] -> [[" .. new_slug .. "]] | " .. patched .. " files patched",
                                vim.log.levels.INFO
                            )
                        end

                        -- Remove resolved entry from results
                        for i = #results, 1, -1 do
                            if results[i] == wl then
                                table.remove(results, i)
                                break
                            end
                        end
                    end

                    -- Reopen the picker with updated results
                    reopen_picker()
                end)
            end)
        end

        map("i", "<c-l>", resolve_action)
        map("n", "<c-l>", resolve_action)

        -- <C-m> — merge: absorb selected wikilink's target into another note (or rewrite if unresolved)
        local function merge_action()
            local selection = action_state.get_selected_entry()
            if not selection or not selection.value then return end
            local wl = selection.value
            local slug = wl.data and wl.data.slug or ""
            if slug == "" then return end

            local resolved = is_resolved(wl)

            -- Close picker before opening sub-picker
            actions.close(prompt_bufnr)

            vim.schedule(function()
                local scoring = require("vault.scoring")

                -- Gather all slugs from the vault for scoring
                local ok_core, core = pcall(require, "vault_core")
                local vault_config = require("vault.config").options
                local candidate_slugs = {}
                if ok_core and core.slugs then
                    local ok_s, slug_map = pcall(core.slugs, vault_config.root, vault_config.ignore or {})
                    if ok_s and type(slug_map) == "table" then
                        for s, _ in pairs(slug_map) do
                            if s ~= slug then
                                candidate_slugs[#candidate_slugs + 1] = s
                            end
                        end
                    end
                end

                -- Score candidates using Rust slug similarity
                local scored = scoring.suggest(slug, candidate_slugs, 200)

                if #scored == 0 then
                    vim.notify("[vault] No merge candidates found for [[" .. slug .. "]]", vim.log.levels.WARN)
                    -- Reopen picker
                    vim.schedule(function()
                        local picker_mod = require("telescope._extensions.vault.pickers.wikilinks")
                        local p = picker_mod({
                            wikilinks = wikilinks,
                            _results = results,
                            sort_by = opts.sort_by,
                            show_resolved = opts.show_resolved,
                        })
                        if p then p:find() end
                    end)
                    return
                end

                -- Open sub-picker with ranked merge candidates
                local tele_actions = require("telescope.actions")
                local tele_action_state = require("telescope.actions.state")
                local tele_finders = require("telescope.finders")
                local tele_pickers = require("telescope.pickers")
                local tele_sorters = require("telescope.sorters")
                local tele_conf = require("telescope.config").values

                local function reopen_picker()
                    vim.schedule(function()
                        local picker_mod = require("telescope._extensions.vault.pickers.wikilinks")
                        local p = picker_mod({
                            wikilinks = wikilinks,
                            _results = results,
                            sort_by = opts.sort_by,
                            show_resolved = opts.show_resolved,
                        })
                        if p then p:find() end
                    end)
                end

                local action_label = resolved and "Merge" or "Rewrite"
                tele_pickers.new({}, {
                    prompt_title = string.format("%s [[%s]] → ?", action_label, slug),
                    finder = tele_finders.new_table({
                        results = scored,
                        entry_maker = function(e)
                            local pct = math.floor(e.score * 100 + 0.5)
                            local display_str = pct > 0
                                and string.format("%s (%d%%)", e.slug, pct)
                                or e.slug
                            local path = utils.slug_to_path(e.slug)
                            return {
                                value    = e,
                                display  = display_str,
                                ordinal  = e.slug,
                                path     = path,
                                filename = path,
                            }
                        end,
                    }),
                    sorter = tele_sorters.get_fuzzy_file(),
                    previewer = tele_conf.file_previewer({}),
                    attach_mappings = function(sub_prompt_bufnr, _sub_map)
                        tele_actions.select_default:replace(function()
                            tele_actions.close(sub_prompt_bufnr)
                            local sel = tele_action_state.get_selected_entry()
                            if not sel then
                                reopen_picker()
                                return
                            end
                            local target_slug = sel.value.slug
                            local target_path = utils.slug_to_path(target_slug)
                            local target_exists = vim.fn.filereadable(target_path) == 1

                            if resolved then
                                -- Source note exists on disk
                                local source_path = utils.slug_to_path(slug)
                                if target_exists then
                                    -- Both exist: full merge (A absorbs B, B trashed, wikilinks rewritten)
                                    require("vault.merge").merge(target_path, source_path, {
                                        on_done = function()
                                            -- Remove merged wikilink from results
                                            for i = #results, 1, -1 do
                                                if results[i] == wl then
                                                    table.remove(results, i)
                                                    break
                                                end
                                            end
                                            reopen_picker()
                                        end,
                                    })
                                else
                                    -- Target doesn't exist: rename source → target (move + rewrite wikilinks)
                                    local watcher = require("vault.watcher")
                                    if watcher.handle_rename then
                                        watcher.handle_rename(source_path, target_path)
                                    else
                                        vim.fn.rename(source_path, target_path)
                                    end
                                    -- Rewrite all [[slug]] → [[target_slug]]
                                    rewrite_wikilink(wl, target_slug)
                                    for i = #results, 1, -1 do
                                        if results[i] == wl then
                                            table.remove(results, i)
                                            break
                                        end
                                    end
                                    vim.notify(
                                        "[vault] Renamed [[" .. slug .. "]] → [[" .. target_slug .. "]]",
                                        vim.log.levels.INFO
                                    )
                                    reopen_picker()
                                end
                            else
                                -- Source wikilink is unresolved (no file on disk)
                                if target_exists then
                                    -- Target exists: rewrite all [[slug]] → [[target_slug]]
                                    local patched = rewrite_wikilink(wl, target_slug)
                                    vim.notify(
                                        "[vault] [[" .. slug .. "]] → [[" .. target_slug .. "]] | " .. patched .. " files patched",
                                        vim.log.levels.INFO
                                    )
                                else
                                    -- Neither exists: rewrite links anyway (both remain unresolved but consolidated)
                                    local patched = rewrite_wikilink(wl, target_slug)
                                    vim.notify(
                                        "[vault] [[" .. slug .. "]] → [[" .. target_slug .. "]] (both unresolved) | " .. patched .. " files patched",
                                        vim.log.levels.INFO
                                    )
                                end
                                -- Remove from results
                                for i = #results, 1, -1 do
                                    if results[i] == wl then
                                        table.remove(results, i)
                                        break
                                    end
                                end
                                reopen_picker()
                            end
                        end)
                        return true
                    end,
                }):find()
            end)
        end

        map("i", "<c-j>", merge_action)
        map("n", "<c-j>", merge_action)

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
        prompt_title = "Wikilinks  <C-l>=resolve  <C-j>=merge",
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
