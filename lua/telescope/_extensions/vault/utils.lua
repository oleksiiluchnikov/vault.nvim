local utils = {}
local action_state = require("telescope.actions.state")
local actions_state = require("telescope.actions.state")
local vault_state = require("vault.core.state")

function utils.get_selected_files(prompt_bufnr, smart)
    local selected = {}
    local current_picker = action_state.get_current_picker(prompt_bufnr)
    local selections = current_picker:get_multi_selection()
    P(selections)
    -- if smart and vim.tbl_isempty(selections) then
    --     table.insert(selected, action_state.get_selected_entry())
    -- else
    -- for _, selection in ipairs(selections) do
    --     table.insert(selected, selection.Path)
    -- end
    -- end
    -- selected = vim.tbl_map(function(entry)
    --     return Path:new(entry)
    -- end, selected)
    -- return selected
end

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

return utils
