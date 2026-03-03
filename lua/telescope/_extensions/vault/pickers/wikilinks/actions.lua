--- Wikilinks picker actions: resolve, merge, enter.
--- Domain logic delegates to Wikilink methods; this module handles only UI orchestration.
local M = {}

local log = require("vault.log").scope("wikilinks")
local utils = require("vault.utils")
local resolve_picker = require("vault.ui.resolve_picker")

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
    require("vault.ui.confirm").confirm({
        message = message,
        title = "Vault",
        on_yes = on_yes,
        on_no = on_no or function() end,
    })
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
                    log.info("Created note: %s", slug)
                end
            )
        end
    end
end

--- Handle the rewrite action for a wikilink (shared by single and batch resolve).
--- @param wl vault.Wikilink
--- @param new_slug string Target slug
--- @param ctx table { wikilinks, results, opts }
--- @param on_done function Called after rewrite completes (or is skipped)
local function handle_rewrite(wl, new_slug, ctx, on_done)
    local slug = wl.data and wl.data.slug or ""
    local conf = get_config()
    local count, affected = wl:rewrite_preview(new_slug)

    local function do_rewrite()
        local patched = wl:rewrite(new_slug)
        log.info("Rewrote [[%s]] -> [[%s]] in %d file(s)", slug, new_slug, patched)
        M.remove_from_results(ctx.results, wl)
        on_done()
    end

    if count == 0 then
        log.info("No files contain [[%s]], nothing to rewrite", slug)
        on_done()
        return
    end

    confirm(conf.confirm_rewrite,
        string.format(
            "Rewrite [[%s]] -> [[%s]] in %d file(s)?\n\nAffected:\n  %s",
            slug, new_slug, count,
            table.concat(affected, "\n  ")
        ),
        do_rewrite,
        on_done
    )
end

--- Open the resolve picker for a wikilink and handle the result.
--- @param wl vault.Wikilink
--- @param opts { wikilinks?: table, prompt_prefix?: string, on_done: fun(result: table), on_cancel?: fun() }
local function resolve_wikilink(wl, opts)
    resolve_picker.open({
        wikilink = wl,
        wikilinks = opts.wikilinks,
        prompt_prefix = opts.prompt_prefix,
        on_resolve = opts.on_done,
        on_cancel = opts.on_cancel or function()
            if opts.on_done then opts.on_done({ action = "skip" }) end
        end,
    })
end

--- <C-l> resolve action: close picker, open resolve Telescope picker, apply, reopen.
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
            log.info("[[%s]] already points to an existing note", slug)
            return
        end

        actions.close(prompt_bufnr)

        vim.schedule(function()
            resolve_wikilink(wl, {
                wikilinks = ctx.wikilinks,
                on_done = function(result)
                    if result.action == "skip" or not result.action then
                        reopen_picker()
                        return
                    end
                    if result.action == "create" then
                        wl:create_target()
                        log.info("Created note: %s", slug)
                        M.remove_from_results(ctx.results, wl)
                        reopen_picker()
                        return
                    end
                    -- Rewrite
                    handle_rewrite(wl, result.slug, ctx, reopen_picker)
                end,
                on_cancel = reopen_picker,
            })
        end)
    end
end

--- <C-j> merge action: compare two wikilinks in the resolver UI, or
--- fall back to sub-picker for single selection.
--- @param prompt_bufnr number
--- @param ctx table { wikilinks, results, opts }
--- @return function
function M.make_merge(prompt_bufnr, ctx)
    local actions = require("telescope.actions")
    local action_state = require("telescope.actions.state")
    local reopen_picker = M.make_reopen(ctx)

    return function()
        local picker = action_state.get_current_picker(prompt_bufnr)
        local multi = picker:get_multi_selection()

        -- Two items selected: open the resolver UI
        if #multi == 2 then
            local wl_a = multi[1].value
            local wl_b = multi[2].value
            if not wl_a or not wl_b then return end

            local a_slug = wl_a.data and wl_a.data.slug or ""
            local b_slug = wl_b.data and wl_b.data.slug or ""
            if a_slug == b_slug then
                log.warn("Cannot compare a wikilink with itself")
                return
            end

            actions.close(prompt_bufnr)
            vim.schedule(function()
                local resolver = require("vault.ui.resolver")
                resolver.open({
                    a = wl_a,
                    b = wl_b,
                    on_done = function()
                        M.remove_from_results(ctx.results, wl_a)
                        M.remove_from_results(ctx.results, wl_b)
                        reopen_picker()
                    end,
                })
            end)
            return
        end

        -- Single selection: fall back to merge sub-picker
        local selection = action_state.get_selected_entry()
        if not selection or not selection.value then return end
        --- @type vault.Wikilink
        local wl = selection.value
        local slug = wl.data and wl.data.slug or ""
        if slug == "" then return end

        actions.close(prompt_bufnr)

        vim.schedule(function()
            local merge = require("telescope._extensions.vault.pickers.wikilinks.merge")
            merge.open(wl, ctx, reopen_picker)
        end)
    end
end

--- <C-S-c> batch create: instantly create notes for all selected unresolved wikilinks.
--- @param prompt_bufnr number
--- @param ctx table { wikilinks, results, opts }
--- @return function
function M.make_batch_create(prompt_bufnr, ctx)
    local actions = require("telescope.actions")
    local action_state = require("telescope.actions.state")
    local reopen_picker = M.make_reopen(ctx)

    return function()
        local picker = action_state.get_current_picker(prompt_bufnr)
        local selections = picker:get_multi_selection()
        if #selections == 0 then
            log.warn("No items selected -- use <Tab> to select wikilinks first")
            return
        end

        -- Filter to unresolved only
        local queue = {}
        for _, sel in ipairs(selections) do
            local wl = sel.value
            if wl and not wl:is_resolved_on_disk() then
                queue[#queue + 1] = wl
            end
        end
        if #queue == 0 then
            log.info("All selected wikilinks are already resolved")
            return
        end

        actions.close(prompt_bufnr)

        vim.schedule(function()
            local created = {}
            for _, wl in ipairs(queue) do
                local slug = wl.data and wl.data.slug or ""
                local ok, err = pcall(wl.create_target, wl)
                if ok then
                    created[#created + 1] = slug
                    M.remove_from_results(ctx.results, wl)
                else
                    log.warn("Failed to create [[%s]]: %s", slug, tostring(err))
                end
            end

            if #created > 0 then
                local preview = #created <= 5
                    and table.concat(created, ", ")
                    or table.concat(vim.list_slice(created, 1, 5), ", ") .. string.format(" ... +%d more", #created - 5)
                log.info("Created %d note%s: %s", #created, #created == 1 and "" or "s", preview)
            end

            reopen_picker()
        end)
    end
end

--- <C-S-l> batch resolve: interactive queue with "Create all" pre-option.
--- @param prompt_bufnr number
--- @param ctx table { wikilinks, results, opts }
--- @return function
function M.make_batch_resolve(prompt_bufnr, ctx)
    local actions = require("telescope.actions")
    local action_state = require("telescope.actions.state")
    local reopen_picker = M.make_reopen(ctx)

    return function()
        local picker = action_state.get_current_picker(prompt_bufnr)
        local selections = picker:get_multi_selection()
        if #selections == 0 then
            log.warn("No items selected -- use <Tab> to select wikilinks first")
            return
        end

        -- Filter to unresolved only
        local queue = {}
        for _, sel in ipairs(selections) do
            local wl = sel.value
            if wl and not wl:is_resolved_on_disk() then
                queue[#queue + 1] = wl
            end
        end
        if #queue == 0 then
            log.info("All selected wikilinks are already resolved")
            return
        end

        actions.close(prompt_bufnr)

        vim.schedule(function()
            -- Pre-option: Create all, Resolve individually, or Cancel
            local vault_confirm = require("vault.ui.confirm")

            local function batch_create_all()
                local created = {}
                for _, wl in ipairs(queue) do
                    local slug = wl.data and wl.data.slug or ""
                    local ok, err = pcall(wl.create_target, wl)
                    if ok then
                        created[#created + 1] = slug
                        M.remove_from_results(ctx.results, wl)
                    else
                        log.warn("Failed to create [[%s]]: %s", slug, tostring(err))
                    end
                end
                if #created > 0 then
                    local preview = #created <= 5
                        and table.concat(created, ", ")
                        or table.concat(vim.list_slice(created, 1, 5), ", ") .. string.format(" ... +%d more", #created - 5)
                    log.info("Created %d note%s: %s", #created, #created == 1 and "" or "s", preview)
                end
                reopen_picker()
            end

            local function resolve_individually()
                local stats = { rewritten = 0, created = 0, skipped = 0 }
                local qi = 0

                local function process_next()
                    qi = qi + 1
                    if qi > #queue then
                        log.info("Batch resolve: %d rewritten, %d created, %d skipped",
                            stats.rewritten, stats.created, stats.skipped)
                        reopen_picker()
                        return
                    end

                    local wl = queue[qi]
                    local slug = wl.data and wl.data.slug or ""

                    if wl:is_resolved_on_disk() then
                        stats.skipped = stats.skipped + 1
                        vim.schedule(process_next)
                        return
                    end

                    resolve_wikilink(wl, {
                        wikilinks = ctx.wikilinks,
                        prompt_prefix = string.format("(%d/%d) ", qi, #queue),
                        on_done = function(result)
                            if result.action == "skip" or not result.action then
                                stats.skipped = stats.skipped + 1
                                vim.schedule(process_next)
                                return
                            end

                            if result.action == "create" then
                                local ok, err = pcall(wl.create_target, wl)
                                if ok then
                                    stats.created = stats.created + 1
                                    M.remove_from_results(ctx.results, wl)
                                else
                                    log.warn("Failed to create [[%s]]: %s", slug, tostring(err))
                                end
                                vim.schedule(process_next)
                                return
                            end

                            local ok, err = pcall(wl.rewrite, wl, result.slug)
                            if ok then
                                stats.rewritten = stats.rewritten + 1
                                M.remove_from_results(ctx.results, wl)
                            else
                                log.warn("Failed to rewrite [[%s]]: %s", slug, tostring(err))
                            end
                            vim.schedule(process_next)
                        end,
                        on_cancel = function()
                            stats.skipped = stats.skipped + 1
                            vim.schedule(process_next)
                        end,
                    })
                end

                vim.schedule(process_next)
            end

            vault_confirm.select({
                message = string.format("Batch resolve %d unresolved wikilinks:", #queue),
                title = "Vault",
                choices = {
                    { key = "a", label = string.format("Create all %d notes", #queue), action = batch_create_all },
                    { key = "r", label = "Resolve individually", action = resolve_individually },
                    { key = "c", label = "Cancel", action = reopen_picker },
                },
                on_cancel = reopen_picker,
            })
        end)
    end
end

return M
