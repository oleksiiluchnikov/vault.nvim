local vault = {}

--- @class vault.WatcherLike
--- @field start fun(self: vault.WatcherLike): nil
--- @field cleanup fun(self: vault.WatcherLike): nil

--- @alias vault.HealthReport vault.HealthSummary|vault.HealthIssue[]

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

    -- Initialize file watcher if enabled
    if config.options.features.watcher == true then
        local Watcher = require("vault.watcher")
        --- @type vault.WatcherLike
        local watcher = Watcher()

        -- Start watching on VimEnter to avoid startup delays
        vim.api.nvim_create_autocmd("VimEnter", {
            callback = function()
                vim.defer_fn(function()
                    watcher:start()
                end, 1000) -- Delay 1s to avoid startup impact
            end,
            once = true,
        })

        -- Cleanup on exit
        vim.api.nvim_create_autocmd("VimLeavePre", {
            callback = function()
                watcher:cleanup()
            end,
        })

        -- Store globally for manual control
        require("vault.core.state").set_global_key("watcher", watcher)
    end
end

--- Check the health of the vault plugin.
--- This function is used by the `:checkhealth` command.
--- @return vault.HealthReport
function vault.checkhealth()
    --- @type string[]
    local dependencies = {
        "telescope",
        -- "cmp",
    }

    --- @type vault.HealthIssue[]
    local results = {}
    local all_ok = true

    for _, plugin_name in ipairs(dependencies) do
        local has_plugin = pcall(require, plugin_name)
        if not has_plugin then
            all_ok = false
            --- @type vault.HealthIssue
            table.insert(results, {
                status = "error",
                message = string.format("`%s` is required to run vault.nvim", plugin_name),
            })
        end
    end

    if all_ok then
        --- @type vault.HealthSummary
        return {
            status = "ok",
            message = "All dependencies are installed",
        }
    end

    return results
end

return vault
