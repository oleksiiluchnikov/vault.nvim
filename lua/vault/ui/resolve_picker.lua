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
--- @field prompt_slug? string Override slug shown in the prompt title
--- @field include_create? boolean Whether to include the create-new-note special entry
--- @field prompt_prefix? string Prefix for the prompt title (e.g. "(1/6) ")
--- @field on_resolve fun(result: { action: string, slug: string?, prompt?: string }) Called with the chosen action
--- @field on_cancel? fun() Called when the user cancels

--- @class ResolveEntry
--- @field slug string
--- @field action string "rewrite" | "create" | "skip"
--- @field ordinal string
--- @field sort_priority number Lower = first
--- @field source string "suggestion" | "note" | "wikilink" | "special"
--- @field score? number  Suggestion match score (0-1)
--- @field strategy? string  Suggestion strategy label
--- @field resolved? boolean  For wikilink entries
--- @field sources_n? number  For wikilink entries, number of source files

--- Source type icons and highlight groups
local SOURCE_ICONS = {
    suggestion = "★",
    note = "◆",
    wikilink = "◇",
    special = "·",
}

---@param selection table|nil
---@param prompt string|nil
---@param include_create boolean|nil
---@return table|nil
local function submit_result(selection, prompt, include_create)
    local typed = vim.trim(prompt or "")
    if not selection or not selection.value then
        if include_create ~= false and typed ~= "" then
            return {
                action = "create",
                slug = typed,
                prompt = typed,
            }
        end
        return nil
    end

    if selection.value.action == "create" and typed ~= "" then
        return {
            action = "create",
            slug = typed,
            prompt = typed,
        }
    end

    return {
        action = selection.value.action,
        slug = selection.value.slug,
        prompt = typed,
    }
end

---@param prompt string|nil
---@param include_create boolean|nil
---@return table|nil
local function force_create_result(prompt, include_create)
    local typed = vim.trim(prompt or "")
    if include_create == false or typed == "" then
        return nil
    end
    return {
        action = "create",
        slug = typed,
        prompt = typed,
    }
end

--- Build entries for the resolve picker.
--- @param wl vault.Wikilink
--- @param wikilinks? table<string, vault.Wikilink>
--- @return ResolveEntry[]
local function build_entries(wl, wikilinks, include_create)
    local entries = {}
    local seen = {}
    local slug = wl.data and wl.data.slug or ""

    -- 1. Suggestions (highest priority — shown first)
    local suggestions = wl.data and wl.data.suggestions or {}
    local strategy_order = { "jaro_winkler", "levenshtein", "contains", "prefix" }
    local strategy_labels = {
        jaro_winkler = "fuzzy",
        levenshtein = "edit",
        contains = "sub",
        prefix = "pre",
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
                    entries[#entries + 1] = {
                        slug = cand_slug,
                        action = "rewrite",
                        ordinal = cand_slug,
                        sort_priority = si * 100 + ci,
                        source = "suggestion",
                        score = score,
                        strategy = label,
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
                local sources_n = 0
                if other_wl.data and type(other_wl.data.sources) == "table" then
                    sources_n = vim.tbl_count(other_wl.data.sources)
                end
                entries[#entries + 1] = {
                    slug = wl_slug,
                    action = "rewrite",
                    ordinal = wl_slug,
                    sort_priority = 20000,
                    source = "wikilink",
                    resolved = resolved,
                    sources_n = sources_n,
                }
            end
        end
    end

    -- 4. Special entries
    if include_create ~= false then
        entries[#entries + 1] = {
            slug = slug,
            action = "create",
            ordinal = "create " .. slug,
            sort_priority = 90000,
            source = "special",
        }
    end
    entries[#entries + 1] = {
        slug = nil,
        action = "skip",
        ordinal = "skip",
        sort_priority = 99999,
        source = "special",
    }

    -- Sort by priority (suggestions first, then notes, wikilinks, specials)
    table.sort(entries, function(a, b)
        return a.sort_priority < b.sort_priority
    end)

    return entries
end

--- Open the resolve picker.
--- @param opts vault.ui.ResolvePickerOpts
function M.open(opts)
    local entry_display = require("telescope.pickers.entry_display")
    local pickers = require("telescope.pickers")
    local finders = require("telescope.finders")
    local conf = require("telescope.config").values
    local actions = require("telescope.actions")
    local action_state = require("telescope.actions.state")
    local previewers = require("telescope.previewers")
    local vault_hl = require("telescope._extensions.vault.highlights")
    local utils = require("vault.utils")

    local wl = opts.wikilink
    local slug = opts.prompt_slug or (wl.data and wl.data.slug) or "?"
    local prefix = opts.prompt_prefix or ""
    local on_resolve = opts.on_resolve
    local on_cancel = opts.on_cancel or function() end

    local entries = build_entries(wl, opts.wikilinks, opts.include_create)

    -- Compute column widths
    local slug_max = 0
    for _, e in ipairs(entries) do
        local s = e.slug or ""
        if #s > slug_max then
            slug_max = #s
        end
    end
    slug_max = math.min(slug_max, 60) -- cap for very long slugs

    -- Gradient highlights for note entries
    local hl_base = "VaultResolve"
    local ui_height = vim.o.lines
    if #vim.api.nvim_list_uis() > 0 then
        ui_height = vim.api.nvim_list_uis()[1].height
    end
    local steps = math.min(ui_height, #entries)
    local colors = vault_hl.setup(hl_base, steps, { "String", "Normal", "Comment" })

    -- Display function
    local displayer = entry_display.create({
        separator = " ",
        items = {
            { width = 2 }, -- source icon
            { width = 6 }, -- score/info
            { width = slug_max + 2 }, -- slug
            { remaining = true }, -- context
        },
    })

    local function make_display(entry)
        local e = entry.value

        -- Icon
        local icon = SOURCE_ICONS[e.source] or " "
        local icon_hl

        -- Score / info column
        local info = ""
        local info_hl = "TelescopeResultsComment"

        -- Slug
        local display_slug = e.slug or ""
        local slug_hl = "TelescopeResultsNormal"

        -- Context (right column)
        local context = ""
        local context_hl = "TelescopeResultsComment"

        if e.source == "suggestion" then
            icon_hl = "TelescopeResultsDiffAdd"
            local pct = math.floor((e.score or 0) * 100 + 0.5)
            info = pct .. "%"
            info_hl = pct >= 80 and "DiagnosticOk"
                or pct >= 50 and "DiagnosticWarn"
                or "DiagnosticError"
            context = e.strategy or ""
            slug_hl = "TelescopeResultsDiffAdd"
        elseif e.source == "note" then
            icon_hl = "TelescopeResultsIdentifier"
            info = "note"
            -- Apply gradient based on entry position
            if colors then
                local idx = math.max(1, math.min(steps, entry.index or 1))
                slug_hl = hl_base .. tostring(idx)
            else
                slug_hl = "TelescopeResultsNormal"
            end
            local path = utils.slug_to_relpath(e.slug)
            if path and path ~= e.slug then
                context = path
            end
        elseif e.source == "wikilink" then
            if e.resolved then
                icon = "✓"
                icon_hl = "TelescopeResultsDiffAdd"
                slug_hl = "TelescopeResultsNormal"
            else
                icon = "○"
                icon_hl = "TelescopeResultsDiffChange"
                slug_hl = "TelescopeResultsComment"
            end
            local n = e.sources_n or 0
            info = n .. "src"
            context = e.resolved and "resolved" or "unresolved"
        elseif e.action == "create" then
            icon = "+"
            icon_hl = "DiagnosticOk"
            display_slug = "Create new note"
            slug_hl = "DiagnosticOk"
            context = e.slug or ""
            context_hl = "TelescopeResultsNormal"
        elseif e.action == "skip" then
            icon = "→"
            icon_hl = "TelescopeResultsComment"
            display_slug = "Skip"
            slug_hl = "TelescopeResultsComment"
        end

        return displayer({
            { icon, icon_hl },
            { info, info_hl },
            { display_slug, slug_hl },
            { context, context_hl },
        })
    end

    local entry_maker = function(entry)
        local filename = nil
        if entry.action == "rewrite" and entry.slug then
            local path = utils.slug_to_path(entry.slug)
            if path and vim.fn.filereadable(path) == 1 then
                filename = path
            end
        end

        return {
            value = entry,
            ordinal = entry.ordinal,
            display = make_display,
            filename = filename,
        }
    end

    local finder = finders.new_table({
        results = entries,
        entry_maker = entry_maker,
    })

    -- Previewer: for notes show file content, for wikilinks show source summary
    local previewer = previewers.new_buffer_previewer({
        title = "Target",
        define_preview = function(self, entry, _status)
            local e = entry.value
            local bufnr = self.state.bufnr

            if not e or e.action == "skip" then
                vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "No preview" })
                return
            end

            if e.action == "create" then
                vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
                    "# [[" .. (e.slug or "") .. "]]",
                    "",
                    "Will create a new note with this slug.",
                    "",
                    "The wikilink will become resolved after creation.",
                })
                vim.api.nvim_set_option_value("filetype", "markdown", { buf = bufnr })
                return
            end

            -- Try to show file content
            local path = utils.slug_to_path(e.slug)
            if path and vim.fn.filereadable(path) == 1 then
                conf.buffer_previewer_maker(path, bufnr, {
                    bufname = self.state.bufname,
                })
            else
                -- No file — show what we know
                local lines = {
                    "# [[" .. (e.slug or "") .. "]]",
                    "",
                }
                if e.source == "suggestion" then
                    local pct = math.floor((e.score or 0) * 100 + 0.5)
                    lines[#lines + 1] =
                        string.format("Suggestion match: %d%% (%s)", pct, e.strategy or "")
                    lines[#lines + 1] = ""
                end
                if e.source == "wikilink" then
                    lines[#lines + 1] = e.resolved and "Resolved wikilink" or "Unresolved wikilink"
                    lines[#lines + 1] =
                        string.format("Referenced in %d source(s)", e.sources_n or 0)
                    lines[#lines + 1] = ""
                end
                lines[#lines + 1] = "_No file found at expected path._"
                vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
                vim.api.nvim_set_option_value("filetype", "markdown", { buf = bufnr })
            end
        end,
    })

    local picker = pickers.new({}, {
        prompt_title = prefix .. "Resolve [[" .. slug .. "]]",
        results_title = #entries .. " targets",
        finder = finder,
        sorter = conf.generic_sorter({}),
        previewer = previewer,
        sorting_strategy = "ascending",
        attach_mappings = function(prompt_bufnr, map)
            actions.select_default:replace(function()
                local selection = action_state.get_selected_entry()
                local result =
                    submit_result(selection, action_state.get_current_line(), opts.include_create)
                actions.close(prompt_bufnr)
                if not result then
                    on_cancel()
                    return
                end
                on_resolve(result)
            end)

            local function force_create()
                local result =
                    force_create_result(action_state.get_current_line(), opts.include_create)
                actions.close(prompt_bufnr)
                if not result then
                    on_cancel()
                    return
                end
                on_resolve(result)
            end

            -- Handle <Esc> / close as cancel
            local function cancel_close()
                actions.close(prompt_bufnr)
                on_cancel()
            end
            map("i", "<Esc>", cancel_close)
            map("n", "<Esc>", cancel_close)
            map("n", "q", cancel_close)
            map("i", "<C-n>", force_create)
            map("n", "<C-n>", force_create)

            -- Cleanup gradient highlights on close
            if colors then
                pcall(vim.api.nvim_create_autocmd, "BufWipeout", {
                    buffer = prompt_bufnr,
                    once = true,
                    callback = function()
                        vault_hl.cleanup(hl_base, #colors)
                    end,
                })
            end

            return true
        end,
    })

    picker:find()
end

M._submit_result = submit_result
M._force_create_result = force_create_result

return M
