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
local uv = vim.uv or vim.loop

--- @class vault.FidgetProgressHandle
--- @field report fun(self: vault.FidgetProgressHandle, opts: { message?: string, percentage?: number|nil }): nil
--- @field finish fun(self: vault.FidgetProgressHandle): nil

--- @class vault.ProgressHandle
--- @field private _fidget? vault.FidgetProgressHandle
--- fidget ProgressHandle (nil if fidget unavailable)
--- @field private _title string
--- @field private _t0 number      hrtime nanoseconds at creation
local Handle = {}
Handle.__index = Handle

--- @alias vault.FidgetCreateOpts { title: string, message: string, lsp_client: { name: string }, percentage: number|nil }
--- @alias vault.FidgetProgressModule { create: fun(opts: vault.FidgetCreateOpts): vault.FidgetProgressHandle }

--- @class vault.ProgressModule
--- @field start fun(title: string, message?: string): vault.ProgressHandle

--- Try to load fidget.progress.handle. Cached after first attempt.
--- @return vault.FidgetProgressModule|nil
local _fidget_checked = false
--- @type vault.FidgetProgressModule|nil
local _fidget_handle_mod = nil

--- @return vault.FidgetProgressModule|nil
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
    local elapsed = (uv.hrtime() - self._t0) / 1e9
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
    --- @type vault.ProgressHandle
    local handle = setmetatable({
        _title = title,
        _t0 = uv.hrtime(),
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
