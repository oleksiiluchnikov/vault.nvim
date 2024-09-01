local vault = {}

--- Setup `vault.nvim` plugin.
--- @param opts? vault.Config.options
function vault.setup(opts)
    opts = opts or {}
    --- @type vault.Config
    local config = require("vault.config")
    config.setup(opts)

    if config.options.features.commands == true then
        require("vault.commands")
    end
    if config.options.features.cmp == true then
        require("vault.cmp").setup()
    end
end

--- Check the health of the vault plugin.
---
--- This function is used by the `:checkhealth` command.
--- @return table
function vault.checkhealth()
    --- @param plugin_name string
    --- @return table
    local function format_error(plugin_name)
        local has = pcall(require, plugin_name)
        local message = string.format("`%s` is required to run vault.nvim", plugin_name)
        if not has then
            return {
                status = "error",
                message = message,
            }
        else
            return {}
        end
    end

    if pcall(require, "telescope") == false then
        return format_error("telescope")
    elseif not pcall(require, "cmp") then
        return format_error("cmp")
    end
    return {
        status = "ok",
        message = "All dependencies are installed",
    }
end

return vault
