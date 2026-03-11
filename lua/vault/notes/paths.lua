local config = require("vault.config")

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
    return M.root() .. "/" .. slug .. M.ext()
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
    local daily_dir = config.dir("journal.daily")
    if not daily_dir then
        return nil
    end
    return string.format("%s/%s%s", daily_dir, date_string, M.ext())
end

return M
