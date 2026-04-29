return {
    find = function(bufnr)
        local utils = require("telescope._extensions.vault.utils")
        local vault_actions = require("telescope._extensions.vault.actions")
        local log = require("vault.log").scope("telescope")
        local _, _, selections = utils.get_picker_selection(bufnr)
        vault_actions.close(bufnr)

        if not selections or next(selections) == nil then
            log.warn("No selection made")
            return
        end

        local entry = selections[1]

        --- @type fun(): Picker
        local picker_fn =
            require("telescope._extensions.vault.pickers.registry").resolve(entry.value.name)
        if not picker_fn then
            log.error("No picker found for '%s'", entry.value.name)
            return
        end

        picker_fn():find()
    end,
}
