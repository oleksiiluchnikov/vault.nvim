--- @class vault.Error
--- @field public MISSING_PARAMETER fun(value: string, suggestion:? string): string
--- @field public INVALID_PARAMETER fun(value: string, suggestion:? string): string
--- @field public INVALID_TYPE fun(value: string, suggestion:? string): string
--- @field public INVALID_VALUE fun(value: string, suggestion:? string): string
--- @field public FILE_NOT_FOUND fun(value: string, suggestion:? string): string
--- @field public COMMAND_EXECUTION_ERROR fun(value: string, suggestion:? string): string
--- @field public CONFIGURATION_ERROR fun(value: string, suggestion:? string): string
--- @field public API_USAGE_ERROR fun(value: string, suggestion:? string): string
--- @field public INVALID_FILE fun(value: string, suggestion:? string): string
--- @field public ALREADY_EXISTS fun(value: string, suggestion:? string): string
--- @field public NOT_EXISTS fun(value: string, suggestion:? string): string
--- @field public NOT_READABLE fun(value: string, suggestion:? string): string
--- @field public NOT_WRITABLE fun(value: string, suggestion:? string): string
--- @field public NOT_EXECUTABLE fun(value: string, suggestion:? string): string
--- @field public INVALID_NAME fun(value: string, suggestion:? string): string
--- @field public IS_EMPTY fun(value: string, suggestion:? string): string
--- @field public format fun(error_code: string, value: string, suggestion:? string): string
local Error = {}

-- Default configuration
local ERROR_PREFIX = "[Vault.nvim] "
local ERROR_CODES = {
    MISSING_PARAMETER = 100,
    INVALID_PARAMETER = 200,
    INVALID_TYPE = 300,
    INVALID_VALUE = 400,
    FILE_NOT_FOUND = 500,
    COMMAND_EXECUTION_ERROR = 600,
    CONFIGURATION_ERROR = 700,
    API_USAGE_ERROR = 800,
    INVALID_FILE = 1000,
    ALREADY_EXISTS = 1700,
    NOT_EXISTS = 2000,
    NOT_READABLE = 2300,
    NOT_WRITABLE = 2600,
    NOT_EXECUTABLE = 2900,
    INVALID_NAME = 1400,
    IS_EMPTY = 1500,
}

--- Format an error message
--- @param error_code string Error code
--- @param value any Value to display
--- @param suggestion? string Suggested fix
--- @return string Formatted error message
function Error.format(error_code, value, suggestion)
    --- Prefix error code
    local formatted_message = ERROR_PREFIX .. error_code .. ": " .. value
    --- Append suggestion if provided
    if suggestion then
        formatted_message = formatted_message .. ". " .. suggestion
    end
    return formatted_message
end

--- Loop through ERROR_CODES and generate error constructor functions
for error_type, _ in pairs(ERROR_CODES) do
    --- Create error constructor function
    --- @param value any Value to display in error message
    --- @param suggestion? string Suggested fix for error
    --- @return string Formatted error message
    Error[error_type] = function(value, suggestion)
        --- Convert error type to uppercase
        local error_key = string.upper(error_type)
        if type(error_key) ~= "string" then
            error_key = "UNKNOWN_ERROR"
        end

        --- Format value as string in backticks
        value = "`" .. vim.inspect(value) .. "`"
        suggestion = suggestion or ""
        --- Generate formatted error message
        return Error.format(error_key, value, suggestion)
    end
end

return Error
