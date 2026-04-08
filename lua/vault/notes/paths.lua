local config = require("vault.config")
local journal = require("vault.journal")
local obsidian = require("vault.obsidian")

local M = {}

--- @return string
function M.root()
    return config.options.root
end

--- @return string
function M.ext()
    return config.options.ext
end

--- @param slug vault.slug
--- @return vault.path
function M.for_slug(slug)
    local derived = obsidian.read(M.root())
    config.options.obsidian = derived
    local current = vim.api.nvim_buf_get_name(0)
    return obsidian.new_note_path(M.root(), M.ext(), slug, derived, current)
end

--- @param relpath string
--- @return vault.path
function M.for_relpath(relpath)
    if relpath:sub(1, 1) == "/" then
        return M.root() .. relpath
    end
    return M.root() .. "/" .. relpath
end

--- @param date_string string
--- @return vault.path|nil
function M.daily(date_string)
    return journal.path(date_string)
end

return M
