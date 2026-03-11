local log = require("vault.log").scope("notes.create")
local Note = require("vault.notes.note")
local paths = require("vault.notes.paths")

local M = {}

--- @param slug vault.slug
--- @param opts? { title?: string, content?: string, open?: boolean }
--- @return vault.path
function M.create(slug, opts)
    opts = opts or {}
    local path = paths.for_slug(slug)
    local title = opts.title or vim.fn.fnamemodify(path, ":t:r")
    local content = opts.content or ("# " .. title .. "\n")

    local note = Note({
        path = path,
        content = content,
    })
    note:write(path)

    if opts.open ~= false then
        note:edit()
    end

    log.info("Note created: %s", path)
    return path
end

return M
