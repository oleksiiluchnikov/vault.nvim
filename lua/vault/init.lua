---@class Vault
---@field setup fun(opts: table?): nil - Setup the vault plugin. 
---@field checkhealth fun(): nil - Check the health of the vault plugin.
local Vault = {}

--- Setup the vault plugin.
---
---@param opts table? - Configuration options (optional).
function Vault.setup(opts)
  opts = opts or {}
  require("vault.config").setup(opts)
  require("vault.commands")
  require("vault.cmp").setup()
end

--- Check the health of the vault plugin.
---
--- This function is used by the `:checkhealth` command.
---@return nil
function Vault.checkhealth()

  local function format_error(plugin_name)
    local has = pcall(require, plugin_name)
    local message = string.format("`%s` is required to run vault.nvim", plugin_name)
    if not has then
      return {
        status = "error",
        message = message,
      }
    end
  end

  if not pcall(require, "telescope") then
    return format_error("telescope")
  elseif not pcall(require, "cmp") then
    return format_error("cmp")
  end
  return {
    status = "ok",
    message = "All dependencies are installed",
  }
end

return Vault
