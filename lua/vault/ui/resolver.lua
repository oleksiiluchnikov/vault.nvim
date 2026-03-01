--- vault.ui.resolver — 4-pane floating UI for comparing two wikilinks or notes.
---
--- ## Concept
---
--- The resolver is a side-by-side comparison UI for two wikilinks (or notes).
--- It shows previews of the relevant notes on the left and right, with a center
--- panel displaying metadata and context-sensitive actions.
---
--- ## Layout
---
--- ╭─ Note A Preview ─╮  ╭── A info ──┬── B info ──╮  ╭─ Note B Preview ─╮
--- │  (markdown)       │  │ ○ [[slug]] │ ✓ [[slug]] │  │  (markdown)       │
--- │                   │  │ Sources: N │ Target: …  │  │                   │
--- │                   │  ├────────────┴────────────┤  │                   │
--- │                   │  │  Actions…               │  │                   │
--- ╰───────────────────╯  ╰─────────────────────────╯  ╰───────────────────╯
---
--- Preview logic:
---   resolved   → show the TARGET note (the file the wikilink points to)
---   unresolved → show a SOURCE note (a file that contains the wikilink)
---
--- ## Future features (not yet implemented)
---
--- - Batch mode: process a queue of pairs, auto-advance after each resolution.
--- - Merge mode: when both sides are resolved notes, show frontmatter conflict
---   diff in the center panel (field-by-field a/b picking, like a git mergetool).
--- - Editable center panel: directly type into cells instead of vim.ui.input.
--- - Configurable preview position: top/bottom instead of left/right.
--- - Integration with telescope as a previewer layout replacement.
--- - Undo: snapshot files before mutation, allow single-level undo.
---
--- @class vault.ui.ResolverOpts
--- @field a vault.Wikilink Left-side wikilink
--- @field b vault.Wikilink Right-side wikilink
--- @field on_done? fun() Called after any action completes (e.g. reopen picker)
--- @field show_previews? boolean Show note preview panes (default true)

local M = {}

local utils = require("vault.utils")

-- ── NUI confirmation popup (delegates to shared module) ────────────────────

--- Show a yes/no confirmation popup via the shared vault.ui.confirm module.
--- @param message string The confirmation message
--- @param on_yes fun() Called if user presses 'y' or clicks Yes
--- @param on_no fun() Called if user presses 'n' or clicks No
local function confirm_popup(message, on_yes, on_no)
    require("vault.ui.confirm").confirm({
        message = message,
        title = "Vault Resolver",
        on_yes = on_yes,
        on_no = on_no,
    })
end

-- ── Highlight groups ───────────────────────────────────────────────────────

local NS = vim.api.nvim_create_namespace("vault_resolver")

local function setup_highlights()
    local hl = vim.api.nvim_set_hl
    hl(0, "VaultResolverResolved", { link = "DiagnosticOk", default = true })
    hl(0, "VaultResolverUnresolved", { link = "DiagnosticWarn", default = true })
    hl(0, "VaultResolverSlug", { link = "Title", default = true })
    hl(0, "VaultResolverAction", { link = "Function", default = true })
    hl(0, "VaultResolverActionKey", { link = "Keyword", default = true })
    hl(0, "VaultResolverDim", { link = "Comment", default = true })
    hl(0, "VaultResolverSeparator", { link = "FloatBorder", default = true })
end

-- ── Layout helpers ─────────────────────────────────────────────────────────

--- Compute window positions and sizes for the 4-pane layout.
--- @param show_previews boolean
--- @return table layout { a_preview, center, b_preview } with win_config tables
local function compute_layout(show_previews)
    local ui = vim.api.nvim_list_uis()[1] or { width = vim.o.columns, height = vim.o.lines }
    local total_w = ui.width
    local total_h = ui.height - 2 -- leave room for cmdline

    local margin = 2
    local usable_w = total_w - margin * 2
    local usable_h = math.min(total_h - margin * 2, 40)

    local center_w, preview_w
    if show_previews then
        -- 30% | 40% | 30%
        center_w = math.floor(usable_w * 0.4)
        preview_w = math.floor((usable_w - center_w - 2) / 2) -- -2 for gaps
    else
        center_w = math.min(usable_w, 80)
        preview_w = 0
    end

    local top = margin
    local center_col
    if show_previews then
        center_col = margin + preview_w + 1
    else
        center_col = math.floor((total_w - center_w) / 2)
    end

    local layout = {
        center = {
            relative = "editor",
            width = center_w,
            height = usable_h,
            row = top,
            col = center_col,
            style = "minimal",
            border = "rounded",
        },
    }

    if show_previews then
        layout.a_preview = {
            relative = "editor",
            width = preview_w,
            height = usable_h,
            row = top,
            col = margin,
            style = "minimal",
            border = "rounded",
        }
        layout.b_preview = {
            relative = "editor",
            width = preview_w,
            height = usable_h,
            row = top,
            col = center_col + center_w + 1,
            style = "minimal",
            border = "rounded",
        }
    end

    return layout
end

-- ── Preview rendering ──────────────────────────────────────────────────────

--- Load note content into a preview buffer.
--- @param bufnr integer
--- @param path string|nil
--- @param title string Border title
--- @param win integer|nil
local function load_preview(bufnr, path, title, win)
    vim.bo[bufnr].modifiable = true
    if path and vim.fn.filereadable(path) == 1 then
        local lines = vim.fn.readfile(path, "", 200) -- cap at 200 lines
        vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
    else
        vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "(no file to preview)" })
    end
    vim.bo[bufnr].modifiable = false
    vim.bo[bufnr].filetype = "markdown"

    if win and vim.api.nvim_win_is_valid(win) then
        pcall(vim.api.nvim_win_set_config, win, { title = " " .. title .. " ", title_pos = "center" })
    end
end

--- Determine which file to preview for a wikilink side.
--- @param wl vault.Wikilink
--- @return string|nil path, string title
local function preview_path_for(wl)
    local slug = wl.data and wl.data.slug or ""
    if wl:is_resolved_on_disk() then
        -- Resolved: show the target note
        local target = wl.data.target or slug
        local path = utils.slug_to_path(target)
        return path, slug .. " (target)"
    else
        -- Unresolved: show the first source note
        local sources = wl.data and wl.data.sources or {}
        for src_slug, _ in pairs(sources) do
            local path = utils.slug_to_path(src_slug)
            if vim.fn.filereadable(path) == 1 then
                return path, slug .. " (source: " .. src_slug .. ")"
            end
        end
        return nil, slug .. " (no source)"
    end
end

-- ── Center panel rendering ─────────────────────────────────────────────────

--- @class vault.ui.ResolverState
--- @field a vault.Wikilink
--- @field b vault.Wikilink
--- @field a_resolved boolean
--- @field b_resolved boolean
--- @field actions table[] { key, label, fn }

--- Build the info lines and actions for the center panel.
--- @param st vault.ui.ResolverState
--- @param width integer? The center panel width (defaults to 60)
--- @return string[] lines, table[] hl_marks { line, col_start, col_end, group }
local function build_center_content(st, width)
    local lines = {}
    local hls = {}
    local a_slug = st.a.data and st.a.data.slug or "?"
    local b_slug = st.b.data and st.b.data.slug or "?"
    local a_mark = st.a_resolved and "✓" or "○"
    local b_mark = st.b_resolved and "✓" or "○"
    local a_hl = st.a_resolved and "VaultResolverResolved" or "VaultResolverUnresolved"
    local b_hl = st.b_resolved and "VaultResolverResolved" or "VaultResolverUnresolved"

    -- Half width for each side, computed from actual panel width
    local panel_w = width or 60
    local half = math.floor((panel_w - 1) / 2) -- -1 for the center separator char

    local function pad(s, w)
        local dw = vim.fn.strdisplaywidth(s)
        if dw >= w then return s end
        return s .. string.rep(" ", w - dw)
    end

    -- Header
    local a_header = pad("  " .. a_mark .. " [[" .. a_slug .. "]]", half)
    local b_header = "  " .. b_mark .. " [[" .. b_slug .. "]]"
    lines[#lines + 1] = a_header .. "│" .. b_header
    hls[#hls + 1] = { line = #lines - 1, col_start = 0, col_end = #a_header, group = a_hl }
    hls[#hls + 1] = { line = #lines - 1, col_start = #a_header + 3, col_end = #a_header + 3 + #b_header, group = b_hl }

    -- Sources count
    local a_src_count = 0
    if st.a.data and st.a.data.sources then
        a_src_count = vim.tbl_count(st.a.data.sources)
    end
    local b_src_count = 0
    if st.b.data and st.b.data.sources then
        b_src_count = vim.tbl_count(st.b.data.sources)
    end

    local a_info
    if st.a_resolved then
        a_info = "  Target: " .. (st.a.data.target or a_slug)
    else
        a_info = "  Sources: " .. a_src_count .. " file" .. (a_src_count == 1 and "" or "s")
    end
    local b_info
    if st.b_resolved then
        b_info = "  Target: " .. (st.b.data.target or b_slug)
    else
        b_info = "  Sources: " .. b_src_count .. " file" .. (b_src_count == 1 and "" or "s")
    end
    local info_line = pad(a_info, half) .. "│" .. b_info
    lines[#lines + 1] = info_line
    hls[#hls + 1] = { line = #lines - 1, col_start = 0, col_end = #info_line, group = "VaultResolverDim" }

    -- Separator
    local sep_line = string.rep("─", half) .. "┴" .. string.rep("─", half)
    lines[#lines + 1] = sep_line
    hls[#hls + 1] = { line = #lines - 1, col_start = 0, col_end = #sep_line, group = "VaultResolverSeparator" }

    -- Blank line
    lines[#lines + 1] = ""

    -- Actions header
    lines[#lines + 1] = "  Actions:"
    hls[#hls + 1] = { line = #lines - 1, col_start = 0, col_end = 10, group = "VaultResolverSlug" }
    lines[#lines + 1] = ""

    -- Build context-sensitive actions
    st.actions = {}
    local a_count = a_src_count
    local b_count = b_src_count

    if not st.a_resolved and not st.b_resolved then
        -- Both unresolved
        st.actions[#st.actions + 1] = {
            key = "a",
            label = string.format("Rewrite [[%s]] → [[%s]]  (%d files)", b_slug, a_slug, b_count),
            fn = function() return "rewrite", st.b, a_slug end,
        }
        st.actions[#st.actions + 1] = {
            key = "b",
            label = string.format("Rewrite [[%s]] → [[%s]]  (%d files)", a_slug, b_slug, a_count),
            fn = function() return "rewrite", st.a, b_slug end,
        }
        st.actions[#st.actions + 1] = {
            key = "e",
            label = "Merge both into a new slug",
            fn = function() return "merge_new" end,
        }
        st.actions[#st.actions + 1] = {
            key = "A",
            label = string.format("Create note for [[%s]]", a_slug),
            fn = function() return "create", st.a end,
        }
        st.actions[#st.actions + 1] = {
            key = "B",
            label = string.format("Create note for [[%s]]", b_slug),
            fn = function() return "create", st.b end,
        }
    elseif not st.a_resolved and st.b_resolved then
        -- A unresolved, B resolved
        st.actions[#st.actions + 1] = {
            key = "b",
            label = string.format("Rewrite [[%s]] → [[%s]]  (%d files)", a_slug, b_slug, a_count),
            fn = function() return "rewrite", st.a, b_slug end,
        }
        st.actions[#st.actions + 1] = {
            key = "a",
            label = string.format("Rename %s.md → %s.md  (move + patch links)", b_slug, a_slug),
            fn = function() return "rename", st.b, a_slug end,
        }
        st.actions[#st.actions + 1] = {
            key = "e",
            label = "Rewrite both into a new slug",
            fn = function() return "merge_new" end,
        }
    elseif st.a_resolved and not st.b_resolved then
        -- A resolved, B unresolved
        st.actions[#st.actions + 1] = {
            key = "a",
            label = string.format("Rewrite [[%s]] → [[%s]]  (%d files)", b_slug, a_slug, b_count),
            fn = function() return "rewrite", st.b, a_slug end,
        }
        st.actions[#st.actions + 1] = {
            key = "b",
            label = string.format("Rename %s.md → %s.md  (move + patch links)", a_slug, b_slug),
            fn = function() return "rename", st.a, b_slug end,
        }
        st.actions[#st.actions + 1] = {
            key = "e",
            label = "Rewrite both into a new slug",
            fn = function() return "merge_new" end,
        }
    else
        -- Both resolved
        st.actions[#st.actions + 1] = {
            key = "a",
            label = string.format("Merge [[%s]] into [[%s]]  (trash %s)", b_slug, a_slug, b_slug),
            fn = function() return "merge_notes", st.a, st.b end,
        }
        st.actions[#st.actions + 1] = {
            key = "b",
            label = string.format("Merge [[%s]] into [[%s]]  (trash %s)", a_slug, b_slug, a_slug),
            fn = function() return "merge_notes", st.b, st.a end,
        }
        st.actions[#st.actions + 1] = {
            key = "e",
            label = "Rewrite both into a new slug",
            fn = function() return "merge_new" end,
        }
    end

    -- Render action lines
    for _, act in ipairs(st.actions) do
        local line = string.format("  %s)  %s", act.key, act.label)
        lines[#lines + 1] = line
        -- Highlight the key
        hls[#hls + 1] = { line = #lines - 1, col_start = 2, col_end = 3, group = "VaultResolverActionKey" }
    end

    return lines, hls
end

-- ── Window management ──────────────────────────────────────────────────────

--- Create a scratch buffer.
--- @param name string
--- @return integer bufnr
local function make_buf(name)
    local buf = vim.api.nvim_create_buf(false, true)
    vim.bo[buf].bufhidden = "wipe"
    vim.bo[buf].swapfile = false
    pcall(vim.api.nvim_buf_set_name, buf, name)
    return buf
end

--- Close a window and wipe its buffer.
--- @param win integer|nil
--- @param buf integer|nil
local function close_win(win, buf)
    if win and vim.api.nvim_win_is_valid(win) then
        pcall(vim.api.nvim_win_close, win, true)
    end
    if buf and vim.api.nvim_buf_is_valid(buf) then
        pcall(vim.api.nvim_buf_delete, buf, { force = true })
    end
end

-- ── Action execution ───────────────────────────────────────────────────────

--- Execute a resolver action.
--- @param action_result table returned by action.fn()
--- @param st vault.ui.ResolverState
--- @param close_fn fun() closes all resolver windows
--- @param on_done fun()|nil
local function execute_action(action_result, st, close_fn, on_done)
    local kind = action_result[1]
    on_done = on_done or function() end

    if kind == "rewrite" then
        local wl = action_result[2]
        local new_slug = action_result[3]
        local slug = wl.data and wl.data.slug or ""
        local count, _ = wl:rewrite_preview(new_slug)
        local msg = string.format("Rewrite [[%s]] → [[%s]] in %d file(s)?", slug, new_slug, count)
        confirm_popup(msg,
            function()
                local patched = wl:rewrite(new_slug)
                vim.notify(
                    string.format("[vault] Rewrote [[%s]] → [[%s]] in %d file(s)", slug, new_slug, patched),
                    vim.log.levels.INFO
                )
                close_fn()
                on_done()
            end,
            function()
                close_fn()
                on_done()
            end
        )

    elseif kind == "rename" then
        local wl = action_result[2]
        local new_slug = action_result[3]
        local target = wl.data.target or (wl.data and wl.data.slug or "")
        local old_path = utils.slug_to_path(target)
        local new_path = utils.slug_to_path(new_slug)
        local msg = string.format("Rename %s → %s? (file move + wikilink patch)", target, new_slug)
        confirm_popup(msg,
            function()
                local Note = require("vault.notes.note")
                local note_ok, note = pcall(Note, old_path)
                if note_ok and note then
                    local move_ok, err = pcall(note.move, note, new_path, false, true)
                    if not move_ok then
                        vim.notify("[vault] Rename failed: " .. tostring(err), vim.log.levels.ERROR)
                    end
                else
                    vim.notify("[vault] Could not load note: " .. old_path, vim.log.levels.ERROR)
                end
                close_fn()
                on_done()
            end,
            function()
                close_fn()
                on_done()
            end
        )

    elseif kind == "merge_new" then
        close_fn()
        vim.ui.input({ prompt = "[vault] New slug for both wikilinks: " }, function(new_slug)
            if not new_slug or new_slug == "" then
                on_done()
                return
            end
            local a_slug = st.a.data and st.a.data.slug or ""
            local b_slug = st.b.data and st.b.data.slug or ""
            local a_count = select(1, st.a:rewrite_preview(new_slug))
            local b_count = select(1, st.b:rewrite_preview(new_slug))
            local msg = string.format(
                "Rewrite [[%s]] (%d files) and [[%s]] (%d files) → [[%s]]?",
                a_slug, a_count, b_slug, b_count, new_slug
            )
            confirm_popup(msg,
                function()
                    local pa = st.a:rewrite(new_slug)
                    local pb = st.b:rewrite(new_slug)
                    vim.notify(
                        string.format("[vault] Rewrote [[%s]] + [[%s]] → [[%s]] (%d + %d files)",
                            a_slug, b_slug, new_slug, pa, pb),
                        vim.log.levels.INFO
                    )
                    on_done()
                end,
                function()
                    on_done()
                end
            )
        end)

    elseif kind == "merge_notes" then
        local target_wl = action_result[2]
        local source_wl = action_result[3]
        local target_slug = target_wl.data.target or (target_wl.data and target_wl.data.slug or "")
        local source_slug = source_wl.data.target or (source_wl.data and source_wl.data.slug or "")
        local target_path = utils.slug_to_path(target_slug)
        local source_path = utils.slug_to_path(source_slug)
        local msg = string.format(
            "Merge [[%s]] into [[%s]]?\n\n"
            .. "This will:\n"
            .. "  1. Append content of [[%s]] to [[%s]]\n"
            .. "  2. Rewrite all links [[%s]] → [[%s]]\n"
            .. "  3. Move [[%s]] to .trash/",
            source_slug, target_slug,
            source_slug, target_slug,
            source_slug, target_slug,
            source_slug
        )
        confirm_popup(msg,
            function()
                close_fn()
                require("vault.merge").merge(target_path, source_path, {
                    on_done = on_done,
                })
            end,
            function()
                close_fn()
                on_done()
            end
        )

    elseif kind == "create" then
        local wl = action_result[2]
        local slug = wl.data and wl.data.slug or ""
        local ok, err = pcall(wl.create_target, wl)
        if ok then
            vim.notify(string.format("[vault] Created note: %s", slug), vim.log.levels.INFO)
        else
            vim.notify(string.format("[vault] Failed to create [[%s]]: %s", slug, tostring(err)), vim.log.levels.WARN)
        end
        close_fn()
        on_done()
    end
end

-- ── Public API ─────────────────────────────────────────────────────────────

--- Open the resolver UI for two wikilinks.
--- @param opts vault.ui.ResolverOpts
function M.open(opts)
    assert(opts.a, "resolver: opts.a (wikilink) is required")
    assert(opts.b, "resolver: opts.b (wikilink) is required")

    local show_previews = opts.show_previews ~= false
    setup_highlights()

    -- Build state
    --- @type vault.ui.ResolverState
    local st = {
        a = opts.a,
        b = opts.b,
        a_resolved = opts.a:is_resolved_on_disk(),
        b_resolved = opts.b:is_resolved_on_disk(),
        actions = {},
    }

    -- Compute layout
    local layout = compute_layout(show_previews)

    -- Track all windows/buffers for cleanup
    local wins = {}
    local bufs = {}

    local function close_all()
        for _, w in pairs(wins) do
            if w and vim.api.nvim_win_is_valid(w) then
                pcall(vim.api.nvim_win_close, w, true)
            end
        end
        for _, b in pairs(bufs) do
            if b and vim.api.nvim_buf_is_valid(b) then
                pcall(vim.api.nvim_buf_delete, b, { force = true })
            end
        end
        wins = {}
        bufs = {}
    end

    -- Create preview windows
    if show_previews then
        bufs.a_preview = make_buf("vault://resolver/preview-a")
        wins.a_preview = vim.api.nvim_open_win(bufs.a_preview, false, layout.a_preview)
        vim.wo[wins.a_preview].number = false
        vim.wo[wins.a_preview].signcolumn = "no"
        vim.wo[wins.a_preview].wrap = true
        vim.wo[wins.a_preview].winhighlight = "NormalFloat:Normal,FloatBorder:FloatBorder"

        bufs.b_preview = make_buf("vault://resolver/preview-b")
        wins.b_preview = vim.api.nvim_open_win(bufs.b_preview, false, layout.b_preview)
        vim.wo[wins.b_preview].number = false
        vim.wo[wins.b_preview].signcolumn = "no"
        vim.wo[wins.b_preview].wrap = true
        vim.wo[wins.b_preview].winhighlight = "NormalFloat:Normal,FloatBorder:FloatBorder"

        -- Load initial previews
        local a_path, a_title = preview_path_for(st.a)
        load_preview(bufs.a_preview, a_path, a_title, wins.a_preview)

        local b_path, b_title = preview_path_for(st.b)
        load_preview(bufs.b_preview, b_path, b_title, wins.b_preview)
    end

    -- Create center panel
    bufs.center = make_buf("vault://resolver/center")
    wins.center = vim.api.nvim_open_win(bufs.center, true, layout.center)
    vim.wo[wins.center].number = false
    vim.wo[wins.center].signcolumn = "no"
    vim.wo[wins.center].cursorline = true
    vim.wo[wins.center].wrap = true
    vim.wo[wins.center].winhighlight = "NormalFloat:Normal,FloatBorder:FloatBorder,CursorLine:Visual"

    -- Render center content
    local lines, hls = build_center_content(st, layout.center.width)
    vim.bo[bufs.center].modifiable = true
    vim.api.nvim_buf_set_lines(bufs.center, 0, -1, false, lines)
    vim.bo[bufs.center].modifiable = false

    -- Apply highlights
    for _, h in ipairs(hls) do
        pcall(vim.api.nvim_buf_add_highlight, bufs.center, NS, h.group, h.line, h.col_start, h.col_end)
    end

    -- Set border title
    pcall(vim.api.nvim_win_set_config, wins.center, {
        title = " Resolver ",
        title_pos = "center",
    })

    -- ── Keymaps ────────────────────────────────────────────────────────────

    local km_opts = { buffer = bufs.center, nowait = true, silent = true }

    -- Close
    vim.keymap.set("n", "q", close_all, km_opts)
    vim.keymap.set("n", "<Esc>", close_all, km_opts)

    -- Action keys
    for _, act in ipairs(st.actions) do
        vim.keymap.set("n", act.key, function()
            local result = { act.fn() }
            execute_action(result, st, close_all, opts.on_done)
        end, km_opts)
    end

    -- Close on BufLeave (only if leaving to a non-resolver window)
    vim.api.nvim_create_autocmd("BufLeave", {
        buffer = bufs.center,
        callback = function()
            vim.schedule(function()
                -- Check if the new current buffer is one of ours
                local cur_buf = vim.api.nvim_get_current_buf()
                for _, b in pairs(bufs) do
                    if b == cur_buf then return end
                end
                close_all()
            end)
        end,
    })
end

return M
