--- @class vault.ErrorCategory
--- @field PARAMETER number # Parameter-related errors (100-299)
--- @field VALIDATION number # Validation errors (300-499)
--- @field IO number # File system operations (500-699)
--- @field SYSTEM number # System-level errors (700-899)
--- @field RUNTIME number # Runtime errors (900-1099)
--- @field RESOURCE number # Resource management (1100-1299)

--- @alias vault.ErrorCode
---| '"MISSING_PARAMETER"' # Required parameter not provided
---| '"INVALID_PARAMETER"' # Parameter value is invalid
---| '"INVALID_TYPE"' # Type mismatch
---| '"INVALID_VALUE"' # Value validation failed
---| '"FILE_NOT_FOUND"' # File doesn't exist
---| '"COMMAND_EXECUTION_ERROR"' # Command failed
---| '"CONFIGURATION_ERROR"' # Config validation failed
---| '"API_USAGE_ERROR"' # Incorrect API usage
---| '"INVALID_FILE"' # File validation failed
---| '"ALREADY_EXISTS"' # Resource already exists
---| '"NOT_EXISTS"' # Resource doesn't exist
---| '"NOT_READABLE"' # File not readable
---| '"NOT_WRITABLE"' # File not writable
---| '"NOT_EXECUTABLE"' # File not executable
---| '"INVALID_NAME"' # Invalid resource name
---| '"IS_EMPTY"' # Resource is empty

--- @class vault.ErrorConfig
--- @field prefix string # Error message prefix
--- @field show_codes boolean # Show numeric error codes
--- @field show_stack boolean # Include stack traces
--- @field format_style "minimal"|"detailed"|"json" # Error formatting style
--- @field highlight_values boolean # Highlight values in messages
--- @field max_stack_depth number # Maximum stack trace depth
--- @field log_errors boolean # Whether to log errors to file
--- @field log_path string # Path to error log file
--- @field suppress_similar number # Suppress similar errors within N seconds

--- @class vault.ErrorContext
--- @field code vault.ErrorCode # Error code identifier
--- @field value any # Problematic value
--- @field suggestion? string # Optional fix suggestion
--- @field stack? string # Call stack when error occurred
--- @field source? string # Source location of error
--- @field timestamp? number # Error creation timestamp

--- @class vault.Error
--- @field config vault.ErrorConfig
--- @field codes table<vault.ErrorCode, number>
--- @field _templates table<vault.ErrorCode, string>
--- @field _recent_errors table<string, number>
--- @field format fun(ctx: vault.ErrorContext): string
--- @field new fun(code: vault.ErrorCode, value: any, suggestion?: string): string
--- @field MISSING_PARAMETER fun(value: any, suggestion?: string): string
--- @field INVALID_PARAMETER fun(value: any, suggestion?: string): string
--- @field INVALID_TYPE fun(value: any, suggestion?: string): string
--- @field INVALID_VALUE fun(value: any, suggestion?: string): string
--- @field FILE_NOT_FOUND fun(value: any, suggestion?: string): string
--- @field COMMAND_EXECUTION_ERROR fun(value: any, suggestion?: string): string
--- @field CONFIGURATION_ERROR fun(value: any, suggestion?: string): string
--- @field API_USAGE_ERROR fun(value: any, suggestion?: string): string
--- @field INVALID_FILE fun(value: any, suggestion?: string): string
--- @field ALREADY_EXISTS fun(value: any, suggestion?: string): string
--- @field NOT_EXISTS fun(value: any, suggestion?: string): string
--- @field NOT_READABLE fun(value: any, suggestion?: string): string
--- @field NOT_WRITABLE fun(value: any, suggestion?: string): string
--- @field NOT_EXECUTABLE fun(value: any, suggestion?: string): string
--- @field INVALID_NAME fun(value: any, suggestion?: string): string
--- @field IS_EMPTY fun(value: any, suggestion?: string): string
local Error = {
    config = {},
    codes = {},
    _templates = {},
    _recent_errors = {},
}

--- Initialize configuration
Error.config = {
    prefix = "[Vault.nvim] ",
    show_codes = true,
    show_stack = vim.fn.has("nvim-0.9") == 1,
    format_style = "detailed",
    highlight_values = true,
    max_stack_depth = 10,
    log_errors = true,
    log_path = vim.fn.stdpath("cache") .. "/vault_errors.log",
    suppress_similar = 5,
}

-- Keep track of recent errors to suppress duplicates
Error._recent_errors = {}

Error.codes = {
    -- Parameter Errors (100-299)
    MISSING_PARAMETER = 100,
    INVALID_PARAMETER = 200,

    -- Validation Errors (300-499)
    INVALID_TYPE = 300,
    INVALID_VALUE = 400,

    -- I/O Errors (500-699)
    FILE_NOT_FOUND = 500,
    COMMAND_EXECUTION_ERROR = 600,

    -- System Errors (700-899)
    CONFIGURATION_ERROR = 700,
    API_USAGE_ERROR = 800,

    -- Runtime Errors (900-1099)
    INVALID_FILE = 900,

    -- Resource Errors (1100+)
    ALREADY_EXISTS = 1100,
    NOT_EXISTS = 1200,
    NOT_READABLE = 1300,
    NOT_WRITABLE = 1400,
    NOT_EXECUTABLE = 1500,
    INVALID_NAME = 1600,
    IS_EMPTY = 1700,
}

--- --- Pre-compiled error templates for performance
--- --- @type table<vault.ErrorCode, string>
--- _templates = {
---     [100] = "[Vault.nvim][E100] Missing parameter `%s`",
---     [200] = "[Vault.nvim][E200] Invalid parameter `%s`",
---     [300] = "[Vault.nvim][E300] Invalid type `%s`",
---     [400] = "[Vault.nvim][E400] Invalid value `%s`",
---     [500] = "[Vault.nvim][E500] File not found `%s`",
---     [600] = "[Vault.nvim][E600] Command execution error `%s`",
---     [700] = "[Vault.nvim][E700] Configuration error `%s`",
---     [800] = "[Vault.nvim][E800] API usage error `%s`",
---     [900] = "[Vault.nvim][E900] Invalid file `%s`",
---     [1100] = "[Vault.nvim][E1100] Already exists `%s`",
---     [1200] = "[Vault.nvim][E1200] Not exists `%s`",
---     [1300] = "[Vault.nvim][E1300] Not readable `%s`",
---     [1400] = "[Vault.nvim][E1400] Not writable `%s`",
---     [1500] = "[Vault.nvim][E1500] Not executable `%s`",
---     [1600] = "[Vault.nvim][E1600] Invalid name `%s`",
---     [1700] = "[Vault.nvim][E1700] Is empty `%s`",
---     UNKNOWN_ERROR = "[Vault.nvim][E999] Unknown error `%s`",
--- }

Error._templates = {
    [100] = "[Vault.nvim][E100] Missing parameter `%s`",
    [200] = "[Vault.nvim][E200] Invalid parameter `%s`",
    [300] = "[Vault.nvim][E300] Invalid type `%s`",
    [400] = "[Vault.nvim][E400] Invalid value `%s`",
    [500] = "[Vault.nvim][E500] File not found `%s`",
    [600] = "[Vault.nvim][E600] Command execution error `%s`",
    [700] = "[Vault.nvim][E700] Configuration error `%s`",
    [800] = "[Vault.nvim][E800] API usage error `%s`",
    [900] = "[Vault.nvim][E900] Invalid file `%s`",
    [1100] = "[Vault.nvim][E1100] Already exists `%s`",
    [1200] = "[Vault.nvim][E1200] Not exists `%s`",
    [1300] = "[Vault.nvim][E1300] Not readable `%s`",
    [1400] = "[Vault.nvim][E1400] Not writable `%s`",
    [1500] = "[Vault.nvim][E1500] Not executable `%s`",
    [1600] = "[Vault.nvim][E1600] Invalid name `%s`",
    [1700] = "[Vault.nvim][E1700] Is empty `%s`",
    UNKNOWN_ERROR = "[Vault.nvim][E999] Unknown error `%s",
}

--- Initialize error templates for faster formatting
local function init_templates()
    for code, _ in pairs(Error.codes) do
        Error._templates[code] = string.format(
            "%s[%s] %%s%s",
            Error.config.prefix,
            code,
            Error.config.show_codes and string.format(" (E%d)", Error.codes[code]) or ""
        )
    end
end

--- Format an error context into a message
--- @param ctx vault.ErrorContext Error context
--- @return string formatted_error Formatted error message
--- Format stack trace with depth limit
--- @param stack string Raw stack trace
--- @return string formatted_stack
local function format_stack(stack)
    if not stack then
        return ""
    end
    local lines = vim.split(stack, "\n")
    local depth = Error.config.max_stack_depth
    if #lines > depth then
        return table.concat(vim.list_slice(lines, 1, depth), "\n") .. "\n... (truncated)"
    end
    return stack
end

--- Check if error should be suppressed
--- @param ctx vault.ErrorContext
--- @return boolean
local function should_suppress(ctx)
    if Error.config.suppress_similar <= 0 then
        return false
    end

    local key = ctx.code .. tostring(ctx.value)
    local last_time = Error._recent_errors[key]
    local current_time = os.time()

    if last_time and (current_time - last_time) < Error.config.suppress_similar then
        return true
    end

    Error._recent_errors[key] = current_time
    return false
end

--- Log error to file
--- @param msg string Formatted error message
local function log_error(msg)
    if not Error.config.log_errors then
        return
    end

    local log_file = io.open(Error.config.log_path, "a")
    if log_file then
        log_file:write(string.format("[%s] %s\n", os.date("%Y-%m-%d %H:%M:%S"), msg))
        log_file:close()
    end
end

function Error.format(ctx)
    if should_suppress(ctx) then
        return ""
    end

    local output
    if Error.config.format_style == "json" then
        output = vim.fn.json_encode({
            code = ctx.code,
            value = ctx.value,
            suggestion = ctx.suggestion,
            source = ctx.source,
            stack = Error.config.show_stack and format_stack(ctx.stack) or nil,
            timestamp = ctx.timestamp,
        })
    else
        -- Standard formatting
        local template = Error._templates[ctx.code] or Error._templates.UNKNOWN_ERROR
        local value_str = Error.config.highlight_values
                and string.format("`%s`", vim.inspect(ctx.value))
            or tostring(ctx.value)

        output = string.format(template, value_str)

        if ctx.suggestion then
            output = output .. "\nSuggestion: " .. ctx.suggestion
        end

        if Error.config.format_style == "detailed" then
            if ctx.source then
                output = output .. "\nSource: " .. ctx.source
            end
            if Error.config.show_stack and ctx.stack then
                output = output .. "\nStack:\n" .. format_stack(ctx.stack)
            end
        end
    end

    if Error.config.log_errors then
        log_error(output)
    end

    return output
end

--- Create a new error instance
--- @param code vault.ErrorCode Error code
--- @param value any Value that caused the error
--- @param suggestion? string Optional suggestion for fixing
--- @return string error_message Formatted error message
function Error.new(code, value, suggestion)
    -- Get debug info
    local info = debug.getinfo(2, "Sl")
    local source = string.format("%s:%d", info.short_src, info.currentline)

    local ctx = {
        code = code,
        value = value,
        suggestion = suggestion,
        source = source,
        stack = Error.config.show_stack and debug.traceback("", 2) or nil,
        timestamp = os.time(),
    }

    return Error.format(ctx)
end

-- Generate error constructor functions
--- @type table<vault.ErrorCode, fun(value: any, suggestion?: string): string>
local error_constructors = {}
for code, _ in pairs(Error.codes) do
    error_constructors[code] = function(value, suggestion)
        return Error.new(code, value, suggestion)
    end
end
for code, func in pairs(error_constructors) do
    Error[code] = func
end

-- Initialize on module load
init_templates()

return Error
