local actions = require("telescope.actions")
local vault_actions = require("vault.pickers.actions")
local M = {}

--- @param map Picker.map
M.notes = function(_, map)
    map("i", "<C-c>", vault_actions.close)
    map("n", "<C-c>", vault_actions.close)

    map("i", "<C-r>", vault_actions.note.rename)
    map("n", "<C-r>", vault_actions.note.rename)

    map("i", "<C-h>", vault_actions.invert)
    map("n", "<C-h>", vault_actions.invert)

    map("i", "<CR>", vault_actions.note.edit)
    map("n", "<CR>", vault_actions.note.edit)

    return true
end

--- @param map Picker.map
M.tags = function(_, map)
    map("i", "<C-c>", vault_actions.close)
    map("n", "<C-c>", vault_actions.close)

    map("i", "<CR>", vault_actions.tag.enter)
    map("n", "<CR>", vault_actions.tag.enter)

    map("i", "<C-h>", vault_actions.invert)
    map("n", "<C-h>", vault_actions.invert)

    map("i", "<C-r>", vault_actions.tag.rename)
    map("n", "<C-r>", vault_actions.tag.rename)

    map("i", "<C-m>", vault_actions.tag.merge)
    map("n", "<C-m>", vault_actions.tag.merge)

    map("i", "<C-e>", vault_actions.tag.edit_documentation)
    map("n", "<C-e>", vault_actions.tag.edit_documentation)
    return true
end
return M
