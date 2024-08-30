--- @class vault
--- @field setup fun(opts:? table): nil - Setup the vault plugin.
--- @field checkhealth fun(): nil - Check the health of the vault plugin.
local Vault = {}

--- Setup `vault.nvim` plugin.
--- @param opts? vault.Config.options
function Vault.setup(opts)
    --- @type vault.Config
    local config = require("vault.config")
    config.setup(opts)
    if config.options.commands then
        require("vault.commands")
    end
    if config.options.cmp then
        require("vault.cmp").setup()
    end
end

--- Check the health of the vault plugin.
---
--- This function is used by the `:checkhealth` command.
--- @return table
function Vault.checkhealth()
    --- @param plugin_name string
    --- @return table|nil
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
