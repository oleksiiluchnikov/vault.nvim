--- @type table<string, vault.Picker.actions>
return {
    enter = function(bufnr)
        local utils = require("telescope._extensions.vault.utils")
        local vault_actions = require("telescope._extensions.vault.actions")
        local vault_utils = require("vault.utils")

        local _, selection, _ = utils.get_picker_selection(bufnr)
        vault_actions.close(bufnr)
        --- @type vault.Task
        local task = selection.value
        local sources = task.data.sources
        if not sources or next(sources) == nil then
            vim.notify("[vault] No sources found for task", vim.log.levels.WARN)
            return
        end
        -- Open the first source note at the task line
        local first_slug = next(sources)
        local path = vault_utils.slug_to_path(first_slug)
        local lnums = sources[first_slug]
        local line = 1
        if type(lnums) == "table" then
            line = next(lnums) or 1
        end
        vim.cmd(string.format("edit +%d %s", line, vim.fn.fnameescape(path)))
    end,
}
