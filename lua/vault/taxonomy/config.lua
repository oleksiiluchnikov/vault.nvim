local M = {}

--- @return vault.Taxonomy.Settings
function M.get()
    return require("vault.config").options.taxonomy or {}
end

return M
