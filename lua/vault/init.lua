local vault = {}

--- Setup `vault.nvim` plugin.
--- ```lua
--- require("vault").setup()
--- ```
--- @param opts? vault.Config.options
function vault.setup(opts)
    opts = opts or {}
    --- @type vault.Config
    local config = require("vault.config")
    config.setup(opts)

    if config.options.features.commands == true then
        require("vault.commands")
    end
    -- if config.options.features.cmp == true then
    --     require("vault.cmp").setup()
    -- end
end

--- Check the health of the vault plugin.
--- This function is used by the `:checkhealth` command.
--- @return table
function vault.checkhealth()
    local dependencies = {
        "telescope",
        -- "cmp",
    }

    local results = {}
    local all_ok = true

    for _, plugin_name in ipairs(dependencies) do
        local has_plugin = pcall(require, plugin_name)
        if not has_plugin then
            all_ok = false
            table.insert(results, {
                status = "error",
                message = string.format("`%s` is required to run vault.nvim", plugin_name),
            })
        end
    end

    if all_ok then
        return {
            status = "ok",
            message = "All dependencies are installed",
        }
    end

    return results
end

return vault
