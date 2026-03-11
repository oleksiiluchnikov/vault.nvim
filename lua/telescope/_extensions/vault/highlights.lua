--- Shared gradient highlight helpers for vault telescope pickers.
local M = {}

local log = require("vault.log").scope("telescope.highlights")
local list_unpack = table.unpack or unpack

---@param value unknown
---@return boolean
local function is_hex_color(value)
    return type(value) == "string" and value:match("^#%x%x%x%x%x%x$") ~= nil
end

--- Setup gradient highlight groups.
--- @param hl_prefix string  e.g. "VaultTag"
--- @param steps number      number of gradient steps
--- @param stops string[]    highlight group stops (e.g. {"Comment", "Normal", "String"})
--- @return table|nil colors  array of hex colors, or nil if gradient unavailable
function M.setup(hl_prefix, steps, stops)
    if type(hl_prefix) ~= "string" or hl_prefix == "" then
        log.warn("Skipping gradient setup: invalid highlight prefix")
        return nil
    end

    steps = math.max(1, tonumber(steps) or 0)
    if type(stops) ~= "table" or vim.tbl_isempty(stops) then
        log.warn("Skipping gradient setup for %s: no stops provided", hl_prefix)
        return nil
    end

    local ok, Gradient = pcall(require, "gradient")
    if not ok then
        log.debug("Gradient provider unavailable for %s: %s", hl_prefix, tostring(Gradient))
        return nil
    end

    local ok_colors, maybe_colors = pcall(Gradient.from_stops, steps, list_unpack(stops))
    if not ok_colors or type(maybe_colors) ~= "table" or vim.tbl_isempty(maybe_colors) then
        log.warn("Failed to build gradient for %s", hl_prefix)
        return nil
    end

    local colors = {}
    for i, color in ipairs(maybe_colors) do
        if is_hex_color(color) then
            local group = hl_prefix .. tostring(i)
            vim.api.nvim_set_hl(0, group, { fg = color })
            colors[#colors + 1] = color
        else
            log.warn("Skipping invalid gradient color for %s[%d]: %s", hl_prefix, i, tostring(color))
        end
    end

    if #colors > 0 then
        return colors
    end

    log.warn("No valid gradient colors generated for %s", hl_prefix)
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
