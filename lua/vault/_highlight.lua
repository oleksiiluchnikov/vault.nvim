local Object = require("vault.core.object")

--- @class vault.Highlights: vault.Object
--- @field ns_id integer
--- @field hl_groups table<string, table>
--- @field colors Gradient
local Highlights = Object("VaultHighlights")

--- Attach hl groups to vim
--- @param name string @Name of hl group
--- @param colors Gradient -- Array of colors
--- @return table @ns_id and hl_groups
local function attach_hl_groups(name, colors)
    local hl_group_prefix = "Vault" .. name .. "Level"
    local hl_groups = {}
    for i, color in ipairs(colors) do
        local i_str = tostring(i)
        vim.api.nvim_set_hl(0, hl_group_prefix .. i_str, {
            fg = color,
        })
        table.insert(hl_groups, hl_group_prefix .. i_str)
    end
    return hl_groups
end

function Highlights:init(bufnr)
    self.bufnr = bufnr
    self.ns_id = vim.api.nvim_create_namespace("vault")
    self.hl_groups = {
        tags = {},
        levels = {},
    }
    self.colors = {
        tags = {},
        levels = {},
    }
end

function Highlights:attach(name, colors)
    local hl_groups = {}
    for i, color in ipairs(colors) do
        local i_str = tostring(i)
        vim.api.nvim_set_hl(self.ns_id, "Vault" .. name .. "Level" .. i_str, {
            fg = color,
        })
        table.insert(hl_groups, "Vault" .. name .. "Level" .. i_str)
    end

    self.ns_id = vim.api.nvim_create_namespace("vault")
    self.hl_groups = {
        tags = attach_hl_groups("Tag", self.colors.tags),
        levels = attach_hl_groups("Level", self.colors.levels),
    }
end

function Highlights:detach()
    for _, hl_group in pairs(self.hl_groups) do
        for _, hl in pairs(hl_group) do
            vim.api.nvim_del_hl_ns(hl, self.ns_id)
        end
    end
    vim.api.nvim_del_namespace(self.ns_id)
end

return Highlights
