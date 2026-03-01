--- Shared gradient highlight helpers for vault telescope pickers.
local M = {}

--- Setup gradient highlight groups.
--- @param hl_prefix string  e.g. "VaultTag"
--- @param steps number      number of gradient steps
--- @param stops string[]    highlight group stops (e.g. {"Comment", "Normal", "String"})
--- @return table|nil colors  array of hex colors, or nil if gradient unavailable
function M.setup(hl_prefix, steps, stops)
    local ok, maybe_colors = pcall(function()
        local Gradient = require("gradient")
        return Gradient.from_stops(steps, unpack(stops))
    end)
    if ok and type(maybe_colors) == "table" then
        for i, color in ipairs(maybe_colors) do
            pcall(vim.api.nvim_set_hl, 0, hl_prefix .. tostring(i), { fg = color })
        end
        return maybe_colors
    end
    return nil
end

--- Clear gradient highlight groups.
--- @param hl_prefix string
--- @param count number
function M.cleanup(hl_prefix, count)
    for i = 1, count do
        pcall(vim.api.nvim_set_hl, 0, hl_prefix .. tostring(i), {})
    end
end

--- Build an attach_mappings function that applies a mapping set and cleans up gradients on close.
--- @param mapping_fn? function  The shared mapping function (e.g. vault_mappings.notes)
--- @param hl_prefix string      Gradient hl prefix
--- @param colors table|nil      Colors array from setup()
--- @return function attach_mappings
function M.make_attach_mappings(mapping_fn, hl_prefix, colors)
    return function(prompt_bufnr, map)
        if type(mapping_fn) == "function" then
            pcall(mapping_fn, prompt_bufnr, map)
        end

        if colors then
            pcall(vim.api.nvim_create_autocmd, "BufWipeout", {
                buffer = prompt_bufnr,
                once = true,
                callback = function()
                    M.cleanup(hl_prefix, #colors)
                end,
            })
        end

        return true
    end
end

return M
