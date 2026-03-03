--- wikilinks.merge — Merge sub-picker for similar note suggestions.
---
--- Extracted from actions.lua make_merge(). Opens a Telescope picker showing
--- scored slug candidates. On select: merges (both resolved), moves (one
--- resolved), or rewrites (unresolved) depending on state.
---
--- @module "telescope._extensions.vault.pickers.wikilinks.merge"

local M = {}

local log = require("vault.log").scope("wikilinks")
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

--- Confirm a destructive action.
--- @param enabled boolean
--- @param message string
--- @param on_yes function
--- @param on_no? function
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

--- Open the merge sub-picker for a single wikilink.
---
--- @param wl vault.Wikilink  The wikilink to merge/rewrite
--- @param ctx table  { wikilinks, results, opts } from the parent picker
--- @param reopen_picker function  Callback to reopen the parent wikilinks picker
function M.open(wl, ctx, reopen_picker)
    local actions_mod = require("telescope._extensions.vault.pickers.wikilinks.actions")
    local scoring = require("vault.scoring")
    local slug = wl.data and wl.data.slug or ""
    local resolved = wl:is_resolved_on_disk()

    -- Gather candidates from vault
    local ok_core, core = pcall(require, "vault_core")
    local vault_config = require("vault.config").options
    local candidate_slugs = {} --- @type string[]
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
        log.warn("No similar notes found for [[%s]]. Try <C-l> to resolve manually instead.", slug)
        reopen_picker()
        return
    end

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
            --- @param e table
            --- @return table
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
        attach_mappings = function(sub_prompt_bufnr, _)
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
                                        actions_mod.remove_from_results(ctx.results, wl)
                                        reopen_picker()
                                    end,
                                })
                            end,
                            reopen_picker
                        )
                    else
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
                                actions_mod.remove_from_results(ctx.results, wl)
                                log.info("Moved [[%s]] -> [[%s]]", slug, target_slug)
                                reopen_picker()
                            end,
                            reopen_picker
                        )
                    end
                else
                    local count, affected = wl:rewrite_preview(target_slug)
                    if count == 0 then
                        log.info("No files contain [[%s]], nothing to rewrite", slug)
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
                            log.info("Rewrote [[%s]] -> [[%s]] in %d file(s)", slug, target_slug, patched)
                            actions_mod.remove_from_results(ctx.results, wl)
                            reopen_picker()
                        end,
                        reopen_picker
                    )
                end
            end)
            return true
        end,
    }):find()
end

return M
