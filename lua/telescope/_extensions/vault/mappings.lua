local vault_actions = require("telescope._extensions.vault.actions")
local telescope_actions = require("telescope.actions")
local M = {}

--- Map the common keybindings shared by all vault pickers:
--- `<C-c>` close, `<C-s>` resort, `<C-a>` select all, `<C-d>` drop all.
--- @param map vault.Picker.map
local function common(map)
    map("i", "<C-c>", vault_actions.close)
    map("n", "<C-c>", vault_actions.close)

    map("i", "<C-s>", vault_actions.resort)
    map("n", "<C-s>", vault_actions.resort)

    map("i", "<C-a>", telescope_actions.select_all)
    map("n", "<C-a>", telescope_actions.select_all)

    map("i", "<C-d>", telescope_actions.drop_all)
    map("n", "<C-d>", telescope_actions.drop_all)
end

--- @param map vault.Picker.map
M.notes = function(_, map)
    common(map)

    map("i", "<C-r>", vault_actions.note.rename)
    map("n", "<C-r>", vault_actions.note.rename)

    map("i", "<C-j>", vault_actions.note.merge)
    map("n", "<C-j>", vault_actions.note.merge)

    map("i", "<CR>", vault_actions.note.edit)
    map("n", "<CR>", vault_actions.note.edit)

    return true
end

--- @param map vault.Picker.map
M.tags = function(_, map)
    common(map)

    map("i", "<CR>", vault_actions.tag.enter)
    map("n", "<CR>", vault_actions.tag.enter)

    map("i", "<C-r>", vault_actions.tag.rename)
    map("n", "<C-r>", vault_actions.tag.rename)

    map("i", "<C-m>", vault_actions.tag.merge)
    map("n", "<C-m>", vault_actions.tag.merge)

    map("i", "<C-e>", vault_actions.tag.edit_documentation)
    map("n", "<C-e>", vault_actions.tag.edit_documentation)

    map("i", "<C-p>", vault_actions.tag.promote)
    map("n", "<C-p>", vault_actions.tag.promote)

    return true
end

M.properties = function(_, map)
    common(map)

    map("i", "<CR>", vault_actions.property.enter)
    map("n", "<CR>", vault_actions.property.enter)

    map("i", "<C-r>", vault_actions.property.rename)
    map("n", "<C-r>", vault_actions.property.rename)

    return true
end

M.property_values = function(_, map)
    common(map)

    map("i", "<CR>", vault_actions.property_value.enter)
    map("n", "<CR>", vault_actions.property_value.enter)

    map("i", "<C-r>", vault_actions.property_value.rename)
    map("n", "<C-r>", vault_actions.property_value.rename)

    return true
end

M.directories = function(_, map)
    common(map)

    map("i", "<CR>", vault_actions.directory.enter)
    map("n", "<CR>", vault_actions.directory.enter)

    map("i", "<C-r>", vault_actions.directory.rename)
    map("n", "<C-r>", vault_actions.directory.rename)

    return true
end

--- @param map vault.Picker.map
M.tasks = function(_, map)
    common(map)

    local task_actions = require("telescope._extensions.vault.pickers.tasks.actions")
    map("i", "<CR>", task_actions.enter)
    map("n", "<CR>", task_actions.enter)

    return true
end

--- @param map vault.Picker.map
M.lines = function(_, map)
    common(map)
    return true
end

--- @param map vault.Picker.map
M.bases = function(_, map)
    common(map)

    map("i", "<CR>", vault_actions.base.enter)
    map("n", "<CR>", vault_actions.base.enter)

    map("i", "<C-n>", vault_actions.base.notes)
    map("n", "<C-n>", vault_actions.base.notes)

    map("i", "<C-e>", vault_actions.base.edit)
    map("n", "<C-e>", vault_actions.base.edit)

    return true
end

--- @param map vault.Picker.map
M.vault = function(_, map)
    common(map)

    local vault_picker_actions = require("telescope._extensions.vault.pickers.vault.actions")
    map("i", "<CR>", vault_picker_actions.find)
    map("n", "<CR>", vault_picker_actions.find)

    return true
end

return M
