local pickers = require("telescope._extensions.vault.pickers")
local log = require("vault.log").scope("bases.actions")

local M = {}

local function safe_find(picker, empty_msg)
    if picker then
        picker:find()
    else
        log.info(empty_msg or "No results found")
    end
end

function M.open_picker_base_notes(base_name)
    safe_find(pickers.base_notes({ base_name = base_name }), "No notes found in base: " .. tostring(base_name))
end

return M
