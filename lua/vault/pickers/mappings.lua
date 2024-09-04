local vault_actions = require("vault.pickers.actions")
local M = {}

--- @param map vault.Picker.map
M.notes = function(_, map)
    map("i", "<C-c>", vault_actions.close)
    map("n", "<C-c>", vault_actions.close)

    map("i", "<C-r>", vault_actions.note.rename)
    map("n", "<C-r>", vault_actions.note.rename)

    map("i", "<C-s>", vault_actions.resort)
    map("n", "<C-s>", vault_actions.resort)

    map("i", "<CR>", vault_actions.note.edit)
    map("n", "<CR>", vault_actions.note.edit)
    -- select all entries in the picker
    map("i", "<C-a>", require("telescope.actions").select_all)
    map("n", "<C-a>", require("telescope.actions").select_all)

    map("i", "<C-d>", require("telescope.actions").drop_all)
    map("n", "<C-d>", require("telescope.actions").drop_all)

    return true
end

--- @param map vault.Picker.map
M.tags = function(_, map)
    map("i", "<C-c>", vault_actions.close)
    map("n", "<C-c>", vault_actions.close)

    map("i", "<CR>", vault_actions.tag.enter)
    map("n", "<CR>", vault_actions.tag.enter)

    map("i", "<C-s>", vault_actions.resort)
    map("n", "<C-s>", vault_actions.resort)

    map("i", "<C-r>", vault_actions.tag.rename)
    map("n", "<C-r>", vault_actions.tag.rename)

    map("i", "<C-m>", vault_actions.tag.merge)
    map("n", "<C-m>", vault_actions.tag.merge)

    map("i", "<C-e>", vault_actions.tag.edit_documentation)
    map("n", "<C-e>", vault_actions.tag.edit_documentation)

    -- select all entries in the picker
    map("i", "<C-a>", require("telescope.actions").select_all)
    map("n", "<C-a>", require("telescope.actions").select_all)

    map("i", "<C-d>", require("telescope.actions").drop_all)
    map("n", "<C-d>", require("telescope.actions").drop_all)

    return true
end

M.properties = function(_, map)
    map("i", "<C-c>", vault_actions.close)
    map("n", "<C-c>", vault_actions.close)

    map("i", "<CR>", vault_actions.property.enter)
    map("n", "<CR>", vault_actions.property.enter)

    map("i", "<C-s>", vault_actions.resort)
    map("n", "<C-s>", vault_actions.resort)

    map("i", "<C-r>", vault_actions.property.rename)
    map("n", "<C-r>", vault_actions.property.rename)

    -- select all entries in the picker
    map("i", "<C-a>", require("telescope.actions").select_all)
    map("n", "<C-a>", require("telescope.actions").select_all)

    map("i", "<C-d>", require("telescope.actions").drop_all)
    map("n", "<C-d>", require("telescope.actions").drop_all)
    return true
end

M.property_values = function(_, map)
    map("i", "<C-c>", vault_actions.close)
    map("n", "<C-c>", vault_actions.close)

    map("i", "<CR>", vault_actions.property_value.enter)
    map("n", "<CR>", vault_actions.property_value.enter)

    map("i", "<C-s>", vault_actions.resort)
    map("n", "<C-s>", vault_actions.resort)

    map("i", "<C-r>", vault_actions.property_value.rename)
    map("n", "<C-r>", vault_actions.property_value.rename)

    -- select all entries in the picker
    map("i", "<C-a>", require("telescope.actions").select_all)
    map("n", "<C-a>", require("telescope.actions").select_all)

    map("i", "<C-d>", require("telescope.actions").drop_all)
    map("n", "<C-d>", require("telescope.actions").drop_all)
    return true
end

M.directories = function(_, map)
    map("i", "<C-c>", vault_actions.close)
    map("n", "<C-c>", vault_actions.close)

    map("i", "<CR>", vault_actions.directory.enter)
    map("n", "<CR>", vault_actions.directory.enter)

    map("i", "<C-s>", vault_actions.resort)
    map("n", "<C-s>", vault_actions.resort)

    map("i", "<C-r>", vault_actions.directory.rename)
    map("n", "<C-r>", vault_actions.directory.rename)
    -- select all entries in the picker
    map("i", "<C-a>", require("telescope.actions").select_all)
    map("n", "<C-a>", require("telescope.actions").select_all)

    map("i", "<C-d>", require("telescope.actions").drop_all)
    map("n", "<C-d>", require("telescope.actions").drop_all)

    return true
end
return M
