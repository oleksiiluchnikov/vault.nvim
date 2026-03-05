--- vault.bases.views.filter_picker — Interactive filter builder for vault views.
---
--- Thin wrapper around vimtable.pickers.filter.
--- No vault-specific hooks needed — uses the shared flow as-is.
---
--- @module vault.bases.views.filter_picker

local M = {}

--- Open the interactive filter picker.
---
--- @param view table  Grid, List, or Board instance
--- @param fields string[]  Field names available for filtering
function M.open(view, fields)
    local vt_filter = require("vimtable.pickers.filter")
    vt_filter.open(view, {
        fields = fields,
        show_actions = true,
    })
end

return M
