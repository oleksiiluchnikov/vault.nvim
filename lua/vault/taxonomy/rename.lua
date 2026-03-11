local internal = require("vault.taxonomy.internal")

local M = {}

M.preview = internal.preview
M.apply = internal.apply
M.undo_last = internal.undo_last

return M
