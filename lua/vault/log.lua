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

--- @param level vault.LogLevel
--- @return boolean
local function should_display(level)
  local cfg = get_config()
  local min = LEVELS[cfg.level] or LEVELS.info
  return (LEVELS[level] or LEVELS.info) >= min
end

--- Write a line to the log file
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

--- Core emit function. All public methods funnel through here.
--- @param level vault.LogLevel
--- @param scope string
--- @param fmt string
--- @param ... any
local function emit(level, scope, fmt, ...)
  -- Lazy format: only build the string if at least one sink needs it
  local needs_display = should_display(level)
  local cfg = get_config()
  local needs_file = cfg.file
  local needs_callback = cfg.on_message ~= nil

  if not needs_display and not needs_file and not needs_callback then
    return
  end

  -- Format the message
  local ok, msg = pcall(string.format, fmt, ...)
  if not ok then
    -- Fallback: concatenate raw args if format fails
    local parts = { fmt }
    for i = 1, select("#", ...) do
      parts[#parts + 1] = tostring(select(i, ...))
    end
    msg = table.concat(parts, " ")
  end

  -- Build prefixed message
  local prefix = scope ~= "" and string.format("[vault.%s]", scope) or "[vault]"
  local prefixed = string.format("%s %s", prefix, msg)

  -- Sink 1: vim.notify (filtered by level)
  if needs_display then
    vim.notify(prefixed, VIM_LEVELS[level])
  end

  -- Sink 2: log file (all levels, timestamped)
  if needs_file then
    local timestamp = os.date("%Y-%m-%d %H:%M:%S")
    local lvl_tag = level:upper()
    write_file(string.format("[%s] [%s] %s", timestamp, lvl_tag, prefixed))
  end

  -- Sink 3: callback (for process buffer log pane, tests, etc.)
  if needs_callback then
    local cb = cfg.on_message
    if type(cb) == "function" then
      pcall(cb, level, scope, msg)
    end
  end
end

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
  local path = get_file_path()
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
