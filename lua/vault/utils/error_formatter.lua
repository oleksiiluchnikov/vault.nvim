local M = {}

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

function M.format_error_message(error_code, value, suggestion)
  local formatted_message = ERROR_PREFIX .. error_code .. ": " .. value
  if suggestion then
    formatted_message = formatted_message .. ". " .. suggestion
  end
  return formatted_message
end

for error_type, _ in pairs(ERROR_CODES) do
  M[string.lower(error_type)] = function(value, suggestion)
    local error_key = string.upper(error_type)
    value = "`" .. vim.inspect(value) .. "`"
    return M.format_error_message(error_key, value, suggestion)
  end
end

return M
