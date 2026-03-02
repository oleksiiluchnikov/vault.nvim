--- Centralized logging for vault.nvim
---
--- Single source of truth for all plugin messages.
--- Replaces all direct vim.notify() calls across the codebase.
---
--- Usage:
---   local log = require("vault.log")
---   log.info("Saved: %d notes", count)
---   log.debug("Diff computed: %d creates", #creates)
---
---   -- Scoped logger (adds subsystem tag):
---   local log = require("vault.log").scope("editor")
---   log.info("Saved: %d notes", count)  --> "[vault.editor] Saved: 3 notes"
---
--- Levels (lowest to highest):
---   TRACE  — file-only, never shown in vim.notify
---   DEBUG  — internal state, only shown when level="debug" or "trace"
---   INFO   — normal user-facing messages (default display level)
---   WARN   — something unexpected but recoverable
---   ERROR  — something failed
---
--- Backend: uses teolog (structured NDJSON) when available, falls back to
--- built-in vim.notify + io.open when teolog is not on the runtimepath.

local M = {}

--- @alias vault.LogLevel "trace"|"debug"|"info"|"warn"|"error"

--- @class vault.LogConfig
--- @field level vault.LogLevel  Minimum level for vim.notify display
--- @field file boolean          Write all levels to log file
--- @field file_path? string     Override log file path (default: stdpath("cache")/vault.log)
--- @field on_message? fun(level: vault.LogLevel, scope: string, msg: string)  Callback for programmatic access

--- Numeric level values for comparison
--- @type table<vault.LogLevel, number>
local LEVELS = {
    trace = 0,
    debug = 1,
    info = 2,
    warn = 3,
    error = 4,
}

--- Map to vim.log.levels
--- @type table<vault.LogLevel, number>
local VIM_LEVELS = {
    trace = vim.log.levels.TRACE,
    debug = vim.log.levels.DEBUG,
    info = vim.log.levels.INFO,
    warn = vim.log.levels.WARN,
    error = vim.log.levels.ERROR,
}

--- @return vault.LogConfig
local function get_config()
    local ok, cfg = pcall(function()
        return require("vault.config").options.log
    end)
    if ok and cfg then
        return cfg
    end
    return { level = "info", file = false }
end

--- @return string
local function get_file_path()
    local cfg = get_config()
    return cfg.file_path or (vim.fn.stdpath("cache") .. "/vault.log")
end

-------------------------------------------------------------------------------
-- teolog backend (structured NDJSON, async file writes)
-------------------------------------------------------------------------------

--- Try to load teolog. Cached after first attempt.
--- @return table|nil teolog module or nil
local _teolog_checked = false
local _teolog = nil

local function get_teolog()
    if _teolog_checked then
        return _teolog
    end
    _teolog_checked = true
    local ok, mod = pcall(require, "teolog")
    if ok then
        _teolog = mod
    end
    return _teolog
end

--- Lazily build the teolog Logger instance.
--- Rebuilt when config changes (file toggle, path, callbacks).
--- @type teolog.Logger|nil
local _logger = nil
local _logger_config_hash = ""

--- Build a config hash to detect changes.
local function config_hash()
    local cfg = get_config()
    return string.format(
        "%s:%s:%s:%s",
        tostring(cfg.level),
        tostring(cfg.file),
        tostring(cfg.file_path),
        tostring(cfg.on_message ~= nil)
    )
end

--- Get or create the teolog Logger, rebuilding if config changed.
--- @return teolog.Logger|nil
local function get_logger()
    local teolog = get_teolog()
    if not teolog then
        return nil
    end

    local hash = config_hash()
    if _logger and _logger_config_hash == hash then
        return _logger
    end

    local cfg = get_config()
    local sinks = {}

    -- Sink 1: vim.notify (filtered by configured level)
    local notify_min = LEVELS[cfg.level] or LEVELS.info
    table.insert(
        sinks,
        teolog.sinks.NotifySink.new("vault", VIM_LEVELS[cfg.level] or vim.log.levels.INFO)
    )

    -- Sink 2: shared teolog NDJSON file (always, so :Teolog live can see vault events)
    table.insert(sinks, teolog.sinks.FileSink.new())

    -- Sink 3: vault-specific log file (when file=true, separate from shared log)
    if cfg.file then
        local path = cfg.file_path or get_file_path()
        if path ~= (vim.fn.stdpath("log") .. "/teolog.log") then
            table.insert(sinks, teolog.sinks.FileSink.new(path))
        end
    end

    -- Sink 4: live panel (direct delivery to :Teolog live if open)
    local panel_ok, panel = pcall(require, "teolog.panel")
    if panel_ok then
        table.insert(sinks, panel.PanelSink.new())
    end

    -- Sink 5: callback sink (for process buffer log pane, tests, etc.)
    if cfg.on_message and type(cfg.on_message) == "function" then
        local cb = cfg.on_message
        table.insert(
            sinks,
            teolog.sinks.CallbackSink.new(function(event)
                -- Adapt teolog event back to vault callback signature: (level, scope, msg)
                local scope = (event.ctx and event.ctx.scope) or ""
                pcall(cb, event.lvl, scope, event.msg)
            end)
        )
    end

    local sink
    if #sinks == 1 then
        sink = sinks[1]
    else
        sink = teolog.sinks.MultiSink.new(sinks)
    end

    _logger = teolog.new("vault.nvim", sink)
    -- Set teolog level to TRACE so all filtering is done per-sink
    -- (NotifySink handles its own min_level, FileSink gets everything)
    _logger:set_level(teolog.Level.TRACE)
    _logger_config_hash = hash

    return _logger
end

-------------------------------------------------------------------------------
-- Fallback backend (original implementation, no teolog dependency)
-------------------------------------------------------------------------------

--- @param level vault.LogLevel
--- @return boolean
local function should_display(level)
    local cfg = get_config()
    local min = LEVELS[cfg.level] or LEVELS.info
    return (LEVELS[level] or LEVELS.info) >= min
end

--- Write a line to the log file (synchronous fallback)
--- @param line string
local function write_file(line)
    local cfg = get_config()
    if not cfg.file then
        return
    end
    local f = io.open(get_file_path(), "a")
    if f then
        f:write(line)
        f:write("\n")
        f:close()
    end
end

--- Fallback emit (no teolog). Preserves original behavior exactly.
--- @param level vault.LogLevel
--- @param scope string
--- @param fmt string
--- @param ... any
local function emit_fallback(level, scope, fmt, ...)
    local needs_display = should_display(level)
    local cfg = get_config()
    local needs_file = cfg.file
    local needs_callback = cfg.on_message ~= nil

    if not needs_display and not needs_file and not needs_callback then
        return
    end

    local ok, msg = pcall(string.format, fmt, ...)
    if not ok then
        local parts = { fmt }
        for i = 1, select("#", ...) do
            parts[#parts + 1] = tostring(select(i, ...))
        end
        msg = table.concat(parts, " ")
    end

    local prefix = scope ~= "" and string.format("[vault.%s]", scope) or "[vault]"
    local prefixed = string.format("%s %s", prefix, msg)

    if needs_display then
        vim.notify(prefixed, VIM_LEVELS[level])
    end

    if needs_file then
        local timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ")
        local lvl_tag = level:upper()
        write_file(string.format("[%s] [%s] %s", timestamp, lvl_tag, prefixed))
    end

    if needs_callback then
        local cb = cfg.on_message
        if type(cb) == "function" then
            pcall(cb, level, scope, msg)
        end
    end
end

-------------------------------------------------------------------------------
-- Unified emit: teolog backend or fallback
-------------------------------------------------------------------------------

--- teolog level map
local TEOLOG_LEVELS = {
    trace = 0,
    debug = 1,
    info = 2,
    warn = 3,
    error = 4,
}

--- Core emit function. All public methods funnel through here.
--- @param level vault.LogLevel
--- @param scope string
--- @param fmt string
--- @param ... any
local function emit(level, scope, fmt, ...)
    local logger = get_logger()

    if not logger then
        -- No teolog available — use original fallback
        emit_fallback(level, scope, fmt, ...)
        return
    end

    -- Format the message (same fallback logic as before)
    local ok, msg = pcall(string.format, fmt, ...)
    if not ok then
        local parts = { fmt }
        for i = 1, select("#", ...) do
            parts[#parts + 1] = tostring(select(i, ...))
        end
        msg = table.concat(parts, " ")
    end

    -- Emit through teolog with scope as context
    local teolog_level = TEOLOG_LEVELS[level] or TEOLOG_LEVELS.info
    if scope ~= "" then
        logger:emit(teolog_level, msg, { scope = scope, module = scope })
    else
        logger:emit(teolog_level, msg)
    end
end

-------------------------------------------------------------------------------
-- Public API (unchanged)
-------------------------------------------------------------------------------

--- Create level methods for a given scope
--- @param scope string
--- @return table
local function make_logger(scope)
    local logger = {}

    --- @param fmt string
    --- @param ... any
    function logger.trace(fmt, ...)
        emit("trace", scope, fmt, ...)
    end

    --- @param fmt string
    --- @param ... any
    function logger.debug(fmt, ...)
        emit("debug", scope, fmt, ...)
    end

    --- @param fmt string
    --- @param ... any
    function logger.info(fmt, ...)
        emit("info", scope, fmt, ...)
    end

    --- @param fmt string
    --- @param ... any
    function logger.warn(fmt, ...)
        emit("warn", scope, fmt, ...)
    end

    --- @param fmt string
    --- @param ... any
    function logger.error(fmt, ...)
        emit("error", scope, fmt, ...)
    end

    --- Create a sub-scoped logger
    --- @param sub string
    --- @return table
    function logger.scope(sub)
        local new_scope = scope ~= "" and (scope .. "." .. sub) or sub
        return make_logger(new_scope)
    end

    return logger
end

-- M is the root logger (scope = "")
local root = make_logger("")
M.trace = root.trace
M.debug = root.debug
M.info = root.info
M.warn = root.warn
M.error = root.error
M.scope = root.scope

--- Get the log file path (useful for :Vault log commands)
--- @return string
function M.get_file_path()
    return get_file_path()
end

--- Tail the log file into a scratch buffer
function M.open()
    local path = M.get_file_path()
    if vim.fn.filereadable(path) == 0 then
        M.info("No log file yet: %s", path)
        return
    end
    vim.cmd("split " .. vim.fn.fnameescape(path))
    vim.bo.buftype = ""
    vim.bo.modifiable = false
    vim.cmd("normal! G")
end

return M
