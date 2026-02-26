local state = require("vault.core.state")
local M = {}

--- @param name string @Name of hl group
--- @param highlights vim.api.keyset.highlight[]
--- @return table<string, vim.api.keyset.highlight>
function M.attach(name, highlights)
    --- @type vim.api.keyset.highlight[]
    local hl_groups = {}
    for i, highlight in ipairs(highlights) do
        vim.api.nvim_set_hl(0, name, highlight)
        hl_groups[name] = highlight
    end
    state.set_global_key("highlights", hl_groups)
    return hl_groups
end

function M.detach()
    --- @type vim.api.keyset.highlight[]
    local hl_groups = state.get_global_key("highlights")
    if not hl_groups then
        return
    end
    for name, hl_group in pairs(hl_groups) do
        vim.api.nvim_set_hl(0, name, hl_group)
    end
end

return M
