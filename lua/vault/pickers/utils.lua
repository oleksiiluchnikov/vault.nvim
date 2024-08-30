local utils = {}
local action_state = require("telescope.actions.state")
utils.get_selected_files = function(prompt_bufnr)
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

return utils
