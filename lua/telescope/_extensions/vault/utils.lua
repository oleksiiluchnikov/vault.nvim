local utils = {}
local actions_state = require("telescope.actions.state")
local vault_state = require("vault.core.state")


--- @param prompt_bufnr integer
--- @return Picker
--- @return vault.TelescopeEntry
--- @return vault.TelescopeEntry[]
function utils.get_picker_selection(prompt_bufnr)
    --- @type Picker
    local current_picker = vault_state.get_global_key("picker")
        or actions_state.get_current_picker(prompt_bufnr)

    --- @type vault.TelescopeEntry
    local selection = actions_state.get_selected_entry()
    --- @type vault.TelescopeEntry[]
    local selections = current_picker:get_multi_selection()
    if next(selections) == nil then
        selections = { selection }
    end
    return current_picker, selection, selections
end

--- Get wikilinks config options with defaults.
--- @return table
function utils.get_wikilinks_config()
    local ok, config = pcall(require, "vault.config")
    if ok and config.options and config.options.wikilinks then
        return config.options.wikilinks
    end
    return { confirm_rewrite = true, confirm_merge = true, confirm_create = false }
end

--- Confirm a destructive action. Calls `on_yes()` if confirmed or if confirmation is disabled.
--- @param enabled boolean Whether confirmation is enabled
--- @param message string The confirmation prompt
--- @param on_yes function Called when confirmed (or confirmation disabled)
--- @param on_no? function Called when cancelled
function utils.confirm(enabled, message, on_yes, on_no)
    if not enabled then
        on_yes()
        return
    end
    require("vault.ui.confirm").confirm({
        message = message,
        title = "Vault",
        on_yes = on_yes,
        on_no = on_no or function() end,
    })
end

return utils
