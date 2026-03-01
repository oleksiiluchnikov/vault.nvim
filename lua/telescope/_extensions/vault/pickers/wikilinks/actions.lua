--- Wikilinks picker actions: resolve, merge, enter.
--- Domain logic delegates to Wikilink methods; this module handles only UI orchestration.
local M = {}

local utils = require("vault.utils")

--- Get wikilinks config options with defaults.
--- @return table
local function get_config()
    local ok, config = pcall(require, "vault.config")
    if ok and config.options and config.options.wikilinks then
        return config.options.wikilinks
    end
    return { confirm_rewrite = true, confirm_merge = true, confirm_create = false }
end

--- Remove a wikilink from results in-place (picker-level bookkeeping).
--- @param results vault.Wikilink[]
--- @param wl vault.Wikilink
function M.remove_from_results(results, wl)
    for i = #results, 1, -1 do
        if results[i] == wl then
            table.remove(results, i)
            break
        end
    end
end

--- Build a reopen_picker function for use after closing the picker.
--- @param ctx table { wikilinks, results, opts }
--- @return function
function M.make_reopen(ctx)
    return function()
        vim.schedule(function()
            local picker_mod = require("telescope._extensions.vault.pickers.wikilinks")
            local p = picker_mod({
                wikilinks = ctx.wikilinks,
                _results = ctx.results,
                sort_by = ctx.opts.sort_by,
                show_resolved = ctx.opts.show_resolved,
            })
            if p then p:find() end
        end)
    end
end

--- Confirm a destructive action. Calls `on_yes()` if confirmed or if confirmation is disabled.
--- @param enabled boolean Whether confirmation is enabled
--- @param message string The confirmation prompt
--- @param on_yes function Called when confirmed (or confirmation disabled)
--- @param on_no? function Called when cancelled
local function confirm(enabled, message, on_yes, on_no)
    if not enabled then
        on_yes()
        return
    end
    local choice = vim.fn.confirm(message, "&Yes\n&No", 2)
    if choice == 1 then
        on_yes()
    elseif on_no then
        on_no()
    end
end

--- <CR> action: open target (resolved) or create note (unresolved).
--- @param ctx table
--- @return function
function M.make_enter(ctx)
    return function(prompt_bufnr)
        local actions = require("telescope.actions")
        local action_state = require("telescope.actions.state")

        local selection = action_state.get_selected_entry()
        if not selection or not selection.value then
            return
        end
        --- @type vault.Wikilink
        local wl = selection.value
        local slug = wl.data and wl.data.slug or ""
        if slug == "" then
            return
        end

        actions.close(prompt_bufnr)

        if wl:is_resolved_on_disk() then
            local target = utils.slug_to_path(slug)
            vim.cmd("edit " .. vim.fn.fnameescape(target))
        else
            local conf = get_config()
            confirm(conf.confirm_create,
                string.format("Create new note [[%s]]?", slug),
                function()
                    local note = wl:create_target()
                    note:edit()
                    vim.notify(string.format("[vault] Created note: %s", slug), vim.log.levels.INFO)
                end
            )
        end
    end
end

--- <C-l> resolve action: close picker, show vim.ui.select, apply, reopen.
--- @param prompt_bufnr number
--- @param ctx table { wikilinks, results, opts }
--- @return function
function M.make_resolve(prompt_bufnr, ctx)
    local actions = require("telescope.actions")
    local action_state = require("telescope.actions.state")
    local reopen_picker = M.make_reopen(ctx)

    return function()
        local selection = action_state.get_selected_entry()
        if not selection or not selection.value then
            return
        end
        --- @type vault.Wikilink
        local wl = selection.value
        local slug = wl.data and wl.data.slug or ""
        if slug == "" then
            return
        end

        if wl:is_resolved_on_disk() then
            vim.notify(
                string.format("[vault] [[%s]] already points to an existing note", slug),
                vim.log.levels.INFO
            )
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
        choices[#choices + 1] = { label = "Cancel", slug = nil, action = "skip" }

        local labels = {}
        for _, c in ipairs(choices) do
            labels[#labels + 1] = c.label
        end

        -- Close the picker BEFORE vim.ui.select so dressing.nvim doesn't
        -- destroy the Telescope prompt buffer.
        actions.close(prompt_bufnr)

        vim.schedule(function()
            vim.ui.select(labels, {
                prompt = string.format("Resolve unlinked [[%s]] — pick target:", slug),
            }, function(choice, idx)
                if not choice or not idx then
                    reopen_picker()
                    return
                end

                local picked = choices[idx]
                local conf = get_config()

                if picked.action == "skip" then
                    reopen_picker()
                    return
                end

                if picked.action == "create" then
                    confirm(conf.confirm_create,
                        string.format("Create new note [[%s]]?", slug),
                        function()
                            wl:create_target()
                            vim.notify(string.format("[vault] Created note: %s", slug), vim.log.levels.INFO)
                            M.remove_from_results(ctx.results, wl)
                            reopen_picker()
                        end,
                        reopen_picker
                    )
                    return
                end

                -- Rewrite [[slug]] -> [[picked.slug]]
                local new_slug = picked.slug
                local count, affected = wl:rewrite_preview(new_slug)

                local function do_rewrite()
                    local patched = wl:rewrite(new_slug)
                    vim.notify(
                        string.format("[vault] Rewrote [[%s]] -> [[%s]] in %d file(s)", slug, new_slug, patched),
                        vim.log.levels.INFO
                    )
                    M.remove_from_results(ctx.results, wl)
                    reopen_picker()
                end

                if count == 0 then
                    vim.notify(
                        string.format("[vault] No files contain [[%s]], nothing to rewrite", slug),
                        vim.log.levels.INFO
                    )
                    reopen_picker()
                    return
                end

                confirm(conf.confirm_rewrite,
                    string.format(
                        "Rewrite [[%s]] -> [[%s]] in %d file(s)?\n\nAffected:\n  %s",
                        slug, new_slug, count,
                        table.concat(affected, "\n  ")
                    ),
                    do_rewrite,
                    reopen_picker
                )
            end)
        end)
    end
end

--- <C-j> merge action: absorb selected wikilink into another note.
--- @param prompt_bufnr number
--- @param ctx table { wikilinks, results, opts }
--- @return function
function M.make_merge(prompt_bufnr, ctx)
    local actions = require("telescope.actions")
    local action_state = require("telescope.actions.state")
    local reopen_picker = M.make_reopen(ctx)

    return function()
        local selection = action_state.get_selected_entry()
        if not selection or not selection.value then return end
        --- @type vault.Wikilink
        local wl = selection.value
        local slug = wl.data and wl.data.slug or ""
        if slug == "" then return end

        local resolved = wl:is_resolved_on_disk()

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

            local scored = scoring.suggest(slug, candidate_slugs, 200)

            if #scored == 0 then
                vim.notify(
                    string.format(
                        "[vault] No similar notes found for [[%s]]. Try <C-l> to resolve manually instead.",
                        slug
                    ),
                    vim.log.levels.WARN
                )
                reopen_picker()
                return
            end

            -- Open sub-picker with ranked merge candidates
            local tele_actions = require("telescope.actions")
            local tele_action_state = require("telescope.actions.state")
            local tele_finders = require("telescope.finders")
            local tele_pickers = require("telescope.pickers")
            local tele_sorters = require("telescope.sorters")
            local tele_conf = require("telescope.config").values
            local conf = get_config()

            local action_label = resolved and "Merge" or "Rewrite"
            local prompt_hint = resolved
                and string.format("Merge [[%s]] into (target absorbs source, source trashed):", slug)
                or string.format("Rewrite [[%s]] -> pick target (rewrites links across vault):", slug)

            tele_pickers.new({}, {
                prompt_title = prompt_hint,
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
                            local source_path = utils.slug_to_path(slug)
                            if target_exists then
                                -- Both exist: full merge (absorb + trash source + rewrite links)
                                confirm(conf.confirm_merge,
                                    string.format(
                                        "Merge [[%s]] into [[%s]]?\n\n"
                                        .. "This will:\n"
                                        .. "  1. Append content of [[%s]] to [[%s]]\n"
                                        .. "  2. Rewrite all links [[%s]] -> [[%s]]\n"
                                        .. "  3. Move [[%s]] to .trash/",
                                        slug, target_slug,
                                        slug, target_slug,
                                        slug, target_slug,
                                        slug
                                    ),
                                    function()
                                        require("vault.merge").merge(target_path, source_path, {
                                            on_done = function()
                                                M.remove_from_results(ctx.results, wl)
                                                reopen_picker()
                                            end,
                                        })
                                    end,
                                    reopen_picker
                                )
                            else
                                -- Target doesn't exist: rename source -> target
                                confirm(conf.confirm_rewrite,
                                    string.format(
                                        "Move [[%s]] -> [[%s]]?\n\n"
                                        .. "This will rename the file and rewrite all links.",
                                        slug, target_slug
                                    ),
                                    function()
                                        local watcher = require("vault.watcher")
                                        if watcher.handle_rename then
                                            watcher.handle_rename(source_path, target_path)
                                        else
                                            vim.fn.rename(source_path, target_path)
                                        end
                                        wl:rewrite(target_slug)
                                        M.remove_from_results(ctx.results, wl)
                                        vim.notify(
                                            string.format("[vault] Moved [[%s]] -> [[%s]]", slug, target_slug),
                                            vim.log.levels.INFO
                                        )
                                        reopen_picker()
                                    end,
                                    reopen_picker
                                )
                            end
                        else
                            -- Source wikilink is unresolved — rewrite via domain method
                            local count, affected = wl:rewrite_preview(target_slug)

                            if count == 0 then
                                vim.notify(
                                    string.format("[vault] No files contain [[%s]], nothing to rewrite", slug),
                                    vim.log.levels.INFO
                                )
                                reopen_picker()
                                return
                            end

                            local msg_suffix = target_exists and "" or " (both unresolved)"
                            confirm(conf.confirm_rewrite,
                                string.format(
                                    "Rewrite [[%s]] -> [[%s]]%s in %d file(s)?\n\nAffected:\n  %s",
                                    slug, target_slug, msg_suffix, count,
                                    table.concat(affected, "\n  ")
                                ),
                                function()
                                    local patched = wl:rewrite(target_slug)
                                    vim.notify(
                                        string.format("[vault] Rewrote [[%s]] -> [[%s]] in %d file(s)", slug, target_slug, patched),
                                        vim.log.levels.INFO
                                    )
                                    M.remove_from_results(ctx.results, wl)
                                    reopen_picker()
                                end,
                                reopen_picker
                            )
                        end
                    end)
                    return true
                end,
            }):find()
        end)
    end
end

return M
