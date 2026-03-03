--- vault.progress — Scan progress reporting via fidget.nvim
---
--- Wraps fidget.nvim's ProgressHandle API for vault scan operations.
--- Falls back to teolog-only logging when fidget is not available.
---
--- Usage:
---   local progress = require("vault.progress")
---   local handle = progress.start("Scanning notes")
---   -- ... synchronous work ...
---   handle:finish("Scanned 8000 notes")
---
--- @module "vault.progress"

local log = require("vault.log").scope("progress")

local M = {}

--- @class vault.ProgressHandle
--- @field private _fidget? table  fidget ProgressHandle (nil if fidget unavailable)
--- @field private _title string
--- @field private _t0 number      hrtime nanoseconds at creation
local Handle = {}
Handle.__index = Handle

--- Try to load fidget.progress.handle. Cached after first attempt.
--- @return table|nil
local _fidget_checked = false
--- @type table|nil
local _fidget_handle_mod = nil

local function get_fidget()
    if _fidget_checked then
        return _fidget_handle_mod
    end
    _fidget_checked = true
    local ok, mod = pcall(require, "fidget.progress.handle")
    if ok then
        _fidget_handle_mod = mod
    end
    return _fidget_handle_mod
end

--- Report a progress update (message change).
--- @param msg string
function Handle:report(msg)
    if self._fidget then
        self._fidget:report({ message = msg })
    end
    log.debug("%s: %s", self._title, msg)
end

--- Mark the progress as complete.
--- @param msg? string  Optional completion message (default: "Done")
function Handle:finish(msg)
    local elapsed = (vim.uv.hrtime() - self._t0) / 1e9
    local message = msg or "Done"
    if self._fidget then
        self._fidget:report({ message = ("%s (%.1fs)"):format(message, elapsed) })
        self._fidget:finish()
    end
    log.info("%s — %s (%.2fs)", self._title, message, elapsed)
end

--- Start a new progress indicator.
---
--- Shows a fidget.nvim spinner if available, otherwise logs only.
---
--- @param title string  Short description (e.g. "Scanning notes")
--- @param message? string  Initial detail message
--- @return vault.ProgressHandle
function M.start(title, message)
    local handle = setmetatable({
        _title = title,
        _t0 = vim.uv.hrtime(),
    }, Handle)

    local fidget_mod = get_fidget()
    if fidget_mod then
        handle._fidget = fidget_mod.create({
            title = title,
            message = message or "Working…",
            lsp_client = { name = "vault" },
            percentage = nil, -- indeterminate spinner
        })
    end

    log.debug("%s: started", title)
    return handle
end

return M
