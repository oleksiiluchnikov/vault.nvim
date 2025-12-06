--- @type table<string, vault.Picker.actions>
return {
    enter = function(bufnr)
        -- local utils = require("telescope._extensions.vault.utils")
        local vault_actions = require("telescope._extensions.vault.actions")
        local actions_state = require("telescope.actions.state")

        -- local _, selection, _ = utils.get_picker_selection(bufnr)
        local selection = actions_state.get_selected_entry()
        vault_actions.close(bufnr)
        --- @type vault.Dir
        local dir = selection.value
        local relpath = dir.data.relpath
        local notes = require("vault.notes")():filter("relpath", relpath, "startswith", true)

        -- P(notes)
        require("telescope._extensions.vault.pickers")
            .notes({
                notes = notes,
            })
            :find()
    end,
    rename = function(bufnr)
        local utils = require("telescope._extensions.vault.utils")
        local vault_actions = require("telescope._extensions.vault.actions")

        local _, selection, _ = utils.get_picker_selection(bufnr)
        vault_actions.close(bufnr)
        --- @type vault.Dir
        local dir = selection.value
        local path = dir.data.path

        vim.notify("TODO: Rename " .. path)
    end,
}
