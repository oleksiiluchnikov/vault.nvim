--- vault.bases.views.filter_picker — Interactive filter builder for vault views.
---
--- Thin wrapper around vimtable.pickers.filter.
--- No vault-specific hooks needed — uses the shared flow as-is.
---
--- @module vault.bases.views.filter_picker

local M = {}

---@alias vault.bases.views.FilterableView table

---@class vault.bases.views.FilterPickerOpts
---@field fields string[]
---@field show_actions boolean

--- Open the interactive filter picker.
---
--- @param view vault.bases.views.FilterableView Grid, List, or Board instance
--- @param fields string[]  Field names available for filtering
function M.open(view, fields)
    local vt_filter = require("vimtable.pickers.filter")
    ---@type vault.bases.views.FilterPickerOpts
    vt_filter.open(view, {
        fields = fields,
        show_actions = true,
    })
end

return M
