--- confirm.lua — Shared NUI-based floating confirmation popups for vault.nvim.
---
--- Replaces all vim.fn.confirm / vim.fn.inputlist / vim.ui.select calls with
--- non-blocking floating popups that don't freeze the RPC socket.
---
--- Two functions:
---   M.confirm(opts) — Yes/No confirmation
---   M.select(opts)  — Multi-choice selection
---
--- Falls back to vim.ui.select if NUI is not available.
local M = {}

-- ── Highlight groups ───────────────────────────────────────────────────────

local function ensure_highlights()
    local set = vim.api.nvim_set_hl
    -- Only set if not already defined by colorscheme
    local function link(name, target)
        local existing = vim.api.nvim_get_hl(0, { name = name })
        if not existing or vim.tbl_isempty(existing) then
            set(0, name, { link = target })
        end
    end
    link("VaultConfirmBorder", "FloatBorder")
    link("VaultConfirmTitle", "FloatTitle")
    link("VaultConfirmKey", "Special")
    link("VaultConfirmDanger", "DiagnosticError")
end

-- ── Helpers ────────────────────────────────────────────────────────────────

--- Compute popup size from message + choices.
--- @param msg_lines string[]
--- @param button_line string
--- @return number width, number height
local function compute_size(msg_lines, button_line)
    local max_w = #button_line
    for _, line in ipairs(msg_lines) do
        if #line > max_w then max_w = #line end
    end
    local width = math.min(max_w + 4, 80)   -- +4 for padding
    local height = #msg_lines + 3            -- message + blank + buttons + padding
    return width, height
end

--- Split a string by newlines.
--- @param s string
--- @return string[]
local function split_lines(s)
    local lines = {}
    for line in (s .. "\n"):gmatch("([^\n]*)\n") do
        lines[#lines + 1] = line
    end
    return lines
end

--- Create and mount a NUI popup with the given content and keymaps.
--- @param opts { title?: string, lines: string[], width: number, height: number, keymaps: table<string, fun()>, on_close?: fun() }
--- @return { close: fun() }
local function create_popup(opts)
    local ok_nui, Popup = pcall(require, "nui.popup")
    if not ok_nui then
        return nil
    end

    ensure_highlights()

    local border_opts = {
        padding = { 1, 2, 1, 2 },
        style = "rounded",
    }
    if opts.title then
        border_opts.text = { top = " " .. opts.title .. " ", top_align = "center" }
    end

    local popup = Popup({
        position = "50%",
        size = {
            width = opts.width,
            height = opts.height,
        },
        enter = true,
        focusable = true,
        border = border_opts,
        buf_options = {
            modifiable = false,
            filetype = "vault_confirm",
        },
        win_options = {
            winhighlight = "Normal:Normal,FloatBorder:VaultConfirmBorder",
        },
    })

    popup:mount()
    local bufnr = popup.bufnr

    -- Set content
    vim.bo[bufnr].modifiable = true
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, opts.lines)
    vim.bo[bufnr].modifiable = false

    -- Highlight the button line (last non-empty line)
    -- Find [key] patterns and highlight them
    local last_line = opts.lines[#opts.lines] or ""
    local line_idx = #opts.lines - 1
    local col = 0
    for bracket_key in last_line:gmatch("%[.-%]") do
        local start = last_line:find(bracket_key, col + 1, true)
        if start then
            pcall(vim.api.nvim_buf_add_highlight, bufnr, -1, "VaultConfirmKey", line_idx, start - 1, start - 1 + #bracket_key)
            col = start + #bracket_key
        end
    end

    -- Close tracking
    local closed = false
    local function close()
        if closed then return end
        closed = true
        pcall(popup.unmount, popup)
        if opts.on_close then
            opts.on_close()
        end
    end

    -- Keymaps
    for key, fn in pairs(opts.keymaps) do
        vim.keymap.set("n", key, function()
            close()
            fn()
        end, { buffer = bufnr, nowait = true })
    end

    -- Also close on BufLeave (user navigated away)
    vim.api.nvim_create_autocmd("BufLeave", {
        buffer = bufnr,
        once = true,
        callback = function()
            vim.schedule(close)
        end,
    })

    return { close = close }
end

-- ── Fallback (no NUI) ─────────────────────────────────────────────────────

--- Fallback confirm via vim.ui.select.
--- @param message string
--- @param on_yes fun()
--- @param on_no fun()
local function fallback_confirm(message, on_yes, on_no)
    vim.ui.select({ "Yes", "No" }, { prompt = message .. " " }, function(choice)
        if choice == "Yes" then
            on_yes()
        else
            on_no()
        end
    end)
end

--- Fallback select via vim.ui.select.
--- @param message string
--- @param choices vault.ui.SelectChoice[]
--- @param on_cancel fun()
local function fallback_select(message, choices, on_cancel)
    local labels = {}
    for _, c in ipairs(choices) do
        labels[#labels + 1] = string.format("[%s] %s", c.key, c.label)
    end
    vim.ui.select(labels, { prompt = message }, function(_, idx)
        if not idx then
            on_cancel()
            return
        end
        choices[idx].action()
    end)
end

-- ── Public API ─────────────────────────────────────────────────────────────

--- @class vault.ui.ConfirmOpts
--- @field message string       Multi-line message (newlines supported)
--- @field title? string        Optional border title
--- @field on_yes fun()         Called when user confirms
--- @field on_no? fun()         Called when user declines or cancels

--- Show a yes/no confirmation popup.
--- @param opts vault.ui.ConfirmOpts
--- @return { close: fun() }?
function M.confirm(opts)
    local on_yes = opts.on_yes
    local on_no = opts.on_no or function() end

    local msg_lines = split_lines(opts.message)
    local button_line = "  [y]es    [n]o"
    local width, height = compute_size(msg_lines, button_line)

    local lines = {}
    for _, l in ipairs(msg_lines) do lines[#lines + 1] = l end
    lines[#lines + 1] = ""
    lines[#lines + 1] = button_line

    local keymaps = {
        ["y"]      = on_yes,
        ["Y"]      = on_yes,
        ["<CR>"]   = on_yes,
        ["n"]      = on_no,
        ["N"]      = on_no,
        ["q"]      = on_no,
        ["<Esc>"]  = on_no,
    }

    local handle = create_popup({
        title = opts.title,
        lines = lines,
        width = width,
        height = height,
        keymaps = keymaps,
        on_close = nil, -- keymaps handle callbacks
    })

    if not handle then
        fallback_confirm(opts.message, on_yes, on_no)
    end

    return handle
end

--- @class vault.ui.SelectChoice
--- @field key string           Single-char hotkey (e.g. "y", "n", "c")
--- @field label string         Button text (e.g. "Yes, trash them")
--- @field action fun()         Called when this choice is selected
--- @field danger? boolean      Highlight label in red

--- @class vault.ui.SelectOpts
--- @field message string       Multi-line message
--- @field title? string        Optional border title
--- @field choices vault.ui.SelectChoice[]
--- @field on_cancel? fun()     Called on <Esc> / q (default: first choice with key "c" or "n", or noop)

--- Show a multi-choice selection popup.
--- @param opts vault.ui.SelectOpts
--- @return { close: fun() }?
function M.select(opts)
    local choices = opts.choices
    local on_cancel = opts.on_cancel or function() end

    local msg_lines = split_lines(opts.message)

    -- Build button line
    local parts = {}
    for _, c in ipairs(choices) do
        parts[#parts + 1] = string.format("[%s] %s", c.key, c.label)
    end
    local button_line = "  " .. table.concat(parts, "    ")
    local width, height = compute_size(msg_lines, button_line)

    local lines = {}
    for _, l in ipairs(msg_lines) do lines[#lines + 1] = l end
    lines[#lines + 1] = ""
    lines[#lines + 1] = button_line

    -- Build keymaps from choices
    local keymaps = {
        ["q"]     = on_cancel,
        ["<Esc>"] = on_cancel,
    }
    for _, c in ipairs(choices) do
        keymaps[c.key] = c.action
        -- Also map uppercase
        if c.key:match("^%l$") then
            keymaps[c.key:upper()] = c.action
        end
    end

    local handle = create_popup({
        title = opts.title,
        lines = lines,
        width = width,
        height = height,
        keymaps = keymaps,
        on_close = nil,
    })

    if not handle then
        fallback_select(opts.message, choices, on_cancel)
    end

    return handle
end

return M
