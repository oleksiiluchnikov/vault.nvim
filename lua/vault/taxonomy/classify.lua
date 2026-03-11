local internal = require("vault.taxonomy.internal")

local M = {}

M.classify_notes = internal.classify_notes
M.open = internal.open_classify

return M
