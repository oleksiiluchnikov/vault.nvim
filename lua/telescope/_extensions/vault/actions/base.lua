local utils = require("telescope._extensions.vault.utils")
local common = require("telescope._extensions.vault.actions.common")

--- @type table<string, fun(bufnr?: number, selections?: table<vault.TelescopeEntry>): nil>
local base_actions = {}

--- Open the bases editor for the selected base.
---@param bufnr? number
function base_actions.enter(bufnr)
    local _, selection, _ = utils.get_picker_selection(bufnr)
    common.close(bufnr)
    --- @type vault.Base
    local base = selection.value
    require("vault.views.grid").open({ base = base })
end

--- Open Telescope notes picker for notes matched by a specific base.
---@param bufnr? number
function base_actions.notes(bufnr)
    local _, selection, _ = utils.get_picker_selection(bufnr)
    common.close(bufnr)
    --- @type vault.Base
    local base = selection.value
    require("vault.bases.actions").open_picker_base_notes(base.data.name)
end

--- Open the .base file for editing.
---@param bufnr? number
function base_actions.edit(bufnr)
    local _, selection, _ = utils.get_picker_selection(bufnr)
    common.close(bufnr)
    --- @type vault.Base
    local base = selection.value
    if base.data.path and base.data.path ~= "" then
        vim.cmd("edit " .. vim.fn.fnameescape(base.data.path))
    end
end

return base_actions
