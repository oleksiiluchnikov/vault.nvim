--- resolve_picker.lua — Telescope-based resolve picker for wikilinks.
---
--- Provides a full-featured Telescope picker for resolving an unresolved wikilink
--- to any note, existing wikilink, or other unresolved wikilink in the vault.
---
--- Sources (mixed in a single result list):
---   1. Suggestion matches from the wikilink's fuzzy/edit-distance strategies (sorted first)
---   2. All notes in the vault (slug → path)
---   3. All wikilinks (resolved and unresolved)
---
--- Special entries:
---   - "Create new note: <slug>"
---   - "Skip"
---
--- Usage:
---   local resolve_picker = require("vault.ui.resolve_picker")
---   resolve_picker.open({
---       wikilink = wl,
---       wikilinks = all_wikilinks,     -- optional, for wikilink entries
---       prompt_prefix = "(1/6) ",      -- optional, for batch context
---       on_resolve = function(result)   -- { action, slug }
---           -- action: "rewrite" | "create" | "skip"
---           -- slug: target slug (nil for create/skip)
---       end,
---       on_cancel = function() end,    -- called on <Esc> / picker close
---   })
local M = {}

--- @class vault.ui.ResolvePickerOpts
--- @field wikilink vault.Wikilink The wikilink to resolve
--- @field wikilinks? table<string, vault.Wikilink> All wikilinks (for wikilink source entries)
--- @field prompt_prefix? string Prefix for the prompt title (e.g. "(1/6) ")
--- @field on_resolve fun(result: { action: string, slug: string? }) Called with the chosen action
--- @field on_cancel? fun() Called when the user cancels

--- @class ResolveEntry
--- @field slug string
--- @field display string
--- @field action string "rewrite" | "create" | "skip"
--- @field ordinal string
--- @field sort_priority number Lower = first
--- @field source string "suggestion" | "note" | "wikilink" | "special"

--- Build entries for the resolve picker.
--- @param wl vault.Wikilink
--- @param wikilinks? table<string, vault.Wikilink>
--- @return ResolveEntry[]
local function build_entries(wl, wikilinks)
    local entries = {}
    local seen = {}
    local slug = wl.data and wl.data.slug or ""

    -- 1. Suggestions (highest priority — shown first)
    local suggestions = wl.data and wl.data.suggestions or {}
    local strategy_order = { "jaro_winkler", "levenshtein", "contains", "prefix" }
    local strategy_labels = {
        jaro_winkler = "fuzzy",
        levenshtein = "edit-dist",
        contains = "substr",
        prefix = "prefix",
    }
    for si, strategy in ipairs(strategy_order) do
        local candidates = suggestions[strategy]
        if type(candidates) == "table" then
            local label = strategy_labels[strategy] or strategy
            for ci, s in ipairs(candidates) do
                local cand_slug = s.slug or s[1] or ""
                if cand_slug ~= "" and not seen[cand_slug] then
                    seen[cand_slug] = true
                    local score = s.score or s[2] or 0
                    local pct = math.floor(score * 100 + 0.5)
                    entries[#entries + 1] = {
                        slug = cand_slug,
                        display = string.format("★ %s (%d%% %s)", cand_slug, pct, label),
                        action = "rewrite",
                        ordinal = cand_slug,
                        sort_priority = si * 100 + ci,
                        source = "suggestion",
                    }
                end
            end
        end
    end

    -- 2. All notes from vault scanner
    local ok_scanner, scanner = pcall(require, "vault.scanner")
    if ok_scanner then
        local ok_slugs, all_slugs = pcall(scanner.slugs)
        if ok_slugs and type(all_slugs) == "table" then
            for note_slug, _ in pairs(all_slugs) do
                if not seen[note_slug] and note_slug ~= slug then
                    seen[note_slug] = true
                    entries[#entries + 1] = {
                        slug = note_slug,
                        display = note_slug,
                        action = "rewrite",
                        ordinal = note_slug,
                        sort_priority = 10000,
                        source = "note",
                    }
                end
            end
        end
    end

    -- 3. Wikilinks (resolved and unresolved)
    if wikilinks then
        for wl_slug, other_wl in pairs(wikilinks) do
            if not seen[wl_slug] and wl_slug ~= slug then
                seen[wl_slug] = true
                local resolved = other_wl.is_resolved_on_disk and other_wl:is_resolved_on_disk()
                local mark = resolved and "✓" or "○"
                local sources_n = other_wl.data and other_wl.data.sources and #other_wl.data.sources or 0
                entries[#entries + 1] = {
                    slug = wl_slug,
                    display = string.format("%s [[%s]] (%d sources)", mark, wl_slug, sources_n),
                    action = "rewrite",
                    ordinal = wl_slug,
                    sort_priority = 20000,
                    source = "wikilink",
                }
            end
        end
    end

    -- 4. Special entries
    entries[#entries + 1] = {
        slug = slug,
        display = "➕ Create new note: " .. slug,
        action = "create",
        ordinal = "create " .. slug,
        sort_priority = 90000,
        source = "special",
    }
    entries[#entries + 1] = {
        slug = nil,
        display = "⏭ Skip",
        action = "skip",
        ordinal = "skip",
        sort_priority = 99999,
        source = "special",
    }

    -- Sort by priority (suggestions first, then notes, wikilinks, specials)
    table.sort(entries, function(a, b) return a.sort_priority < b.sort_priority end)

    return entries
end

--- Open the resolve picker.
--- @param opts vault.ui.ResolvePickerOpts
function M.open(opts)
    local pickers = require("telescope.pickers")
    local finders = require("telescope.finders")
    local conf = require("telescope.config").values
    local actions = require("telescope.actions")
    local action_state = require("telescope.actions.state")
    local previewers = require("telescope.previewers")

    local wl = opts.wikilink
    local slug = wl.data and wl.data.slug or "?"
    local prefix = opts.prompt_prefix or ""
    local on_resolve = opts.on_resolve
    local on_cancel = opts.on_cancel or function() end

    local entries = build_entries(wl, opts.wikilinks)

    local utils = require("vault.utils")

    local finder = finders.new_table({
        results = entries,
        entry_maker = function(entry)
            return {
                value = entry,
                display = entry.display,
                ordinal = entry.ordinal,
            }
        end,
    })

    -- Previewer: show note content for rewrite targets
    local previewer = previewers.new_buffer_previewer({
        title = "Target Preview",
        define_preview = function(self, entry, _status)
            local e = entry.value
            if not e or e.action ~= "rewrite" then
                vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, {
                    e and e.action == "create" and ("Will create: " .. (e.slug or "")) or "No preview",
                })
                return
            end
            local path = utils.slug_to_path(e.slug)
            if path and vim.fn.filereadable(path) == 1 then
                conf.buffer_previewer_maker(path, self.state.bufnr, {
                    bufname = self.state.bufname,
                })
            else
                vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, {
                    "No file found for: " .. (e.slug or ""),
                })
            end
        end,
    })

    local picker = pickers.new({}, {
        prompt_title = prefix .. "Resolve [[" .. slug .. "]]",
        finder = finder,
        sorter = conf.generic_sorter({}),
        previewer = previewer,
        sorting_strategy = "ascending",
        attach_mappings = function(prompt_bufnr, map)
            actions.select_default:replace(function()
                local selection = action_state.get_selected_entry()
                actions.close(prompt_bufnr)
                if not selection or not selection.value then
                    on_cancel()
                    return
                end
                on_resolve({
                    action = selection.value.action,
                    slug = selection.value.slug,
                })
            end)

            -- Handle <Esc> / close as cancel
            local function cancel_close()
                actions.close(prompt_bufnr)
                on_cancel()
            end
            map("i", "<Esc>", cancel_close)
            map("n", "<Esc>", cancel_close)
            map("n", "q", cancel_close)

            return true
        end,
    })

    picker:find()
end

return M
