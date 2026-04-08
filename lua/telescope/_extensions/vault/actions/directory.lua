local utils = require("telescope._extensions.vault.utils")
local common = require("telescope._extensions.vault.actions.common")

local directory_actions = {}

---@param bufnr? number
function directory_actions.enter(bufnr)
    local _, selection, _ = utils.get_picker_selection(bufnr)
    common.close(bufnr)
    --- @type vault.Dir
    local dir = selection.value
    common.safe_find(
        require("telescope._extensions.vault.pickers").notes({
            notes = require("vault.notes")():filter("relpath", dir, "startswith", false),
        }),
        "No notes found in directory: " .. tostring(dir)
    )
end

---@param bufnr? number
function directory_actions.rename(bufnr)
    local _, selection, _ = utils.get_picker_selection(bufnr)
    --- @type vault.Dir
    local dir = selection.value
    local new_name = vim.fn.input("Rename directory: ", dir.data.relpath)
    if not new_name or new_name == "" or new_name == dir.data.relpath then
        return
    end
    common.close(bufnr)
    dir:rename(new_name)
end

return directory_actions
