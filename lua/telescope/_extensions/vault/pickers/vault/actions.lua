return {
    find = function(bufnr)
        local utils = require("telescope._extensions.vault.utils")
        local vault_actions = require("telescope._extensions.vault.actions")
        local _, _, selections = utils.get_picker_selection(bufnr)
        vault_actions.close(bufnr)

        if not selections or next(selections) == nil then
            vim.notify("No selection made", vim.log.levels.WARN)
            return
        end

        local entry = selections[1]

        --- @type fun(): Picker
        local picker_fn = require("telescope._extensions.vault.pickers")[entry.value.name]
        if not picker_fn then
            vim.notify("No picker found for '" .. entry.value.name .. "'", vim.log.levels.ERROR)
            return
        end

        picker_fn():find()
    end,
}
