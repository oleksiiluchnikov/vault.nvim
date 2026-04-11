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

    require("vault.prewarm").schedule_notes()

    if config.options.features.commands == true then
        -- Lazy-load: register a lightweight :Vault stub that loads the real
        -- commands module on first invocation, then re-dispatches.
        local loaded = false
        vim.api.nvim_create_user_command("Vault", function(args)
            if not loaded then
                loaded = true
                -- Load the real command module, which may already be cached in
                -- long-lived test/editor sessions.
                require("vault.commands")
            end
            require("vault.commands").api(args)
        end, {
            desc = "Vault (loading...)",
            nargs = "*",
            range = true,
            complete = function(arg_lead, cmd_line, cursor_pos)
                if not loaded then
                    loaded = true
                    require("vault.commands")
                end
                -- Delegate to the real completer
                local info = vim.api.nvim_get_commands({})["Vault"]
                if info and info.complete then
                    -- After reload, completions module handles it
                    return require("vault.commands.completions").api(arg_lead, cmd_line, cursor_pos)
                end
                return {}
            end,
        })
    end

    -- Initialize file watcher if enabled (lazy-loaded on VimEnter)
    if config.options.features.watcher == true then
        vim.api.nvim_create_autocmd("VimEnter", {
            callback = function()
                vim.defer_fn(function()
                    local Watcher = require("vault.watcher")
                    --- @type vault.WatcherLike
                    local watcher = Watcher()
                    watcher:start()

                    -- Store globally for manual control
                    require("vault.core.state").set_global_key("watcher", watcher)

                    -- Cleanup on exit
                    vim.api.nvim_create_autocmd("VimLeavePre", {
                        callback = function()
                            watcher:cleanup()
                        end,
                    })
                end, 1000) -- Delay 1s to avoid startup impact
            end,
            once = true,
        })
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
