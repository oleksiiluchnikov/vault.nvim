--- @type table<string, vault.Picker.actions>
return {
    enter = function(bufnr)
        local utils = require("telescope._extensions.vault.utils")
        local vault_actions = require("telescope._extensions.vault.actions")

        local _, selection, _ = utils.get_picker_selection(bufnr)
        vault_actions.close(bufnr)
        --- @type vault.Task
        local task = selection.value
        local sources = task.data.sources
        if next(sources) == nil then
            vim.notify("No sources found for task", vim.log.levels.WARN)
            return
        end
        vim.notify(vim.inspect(sources))
    end,
}
