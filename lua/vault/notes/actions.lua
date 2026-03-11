local pickers = require("telescope._extensions.vault.pickers")
local log = require("vault.log").scope("notes.actions")

local M = {}

local function safe_find(picker, empty_msg)
    if picker then
        picker:find()
    else
        log.info(empty_msg or "No results found")
    end
end

function M.open_picker_notes_with_empty_content()
    safe_find(
        pickers.notes({ notes = require("vault.notes")():filter("content", [[^\s*$]], "regex", false) }),
        "No empty notes found"
    )
end

function M.open_picker_notes_without_frontmatter()
    safe_find(
        pickers.notes({
            notes = require("vault.notes")():filter("content", [=[^\(---\)\@!.*$]=], "regex", true),
        }),
        "No notes without frontmatter found"
    )
end

return M
