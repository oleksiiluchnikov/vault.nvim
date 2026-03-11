local M = {}

function M.spec()
    return {
        notes = {
            empty = {
                run = function()
                    require("vault.notes.actions").open_picker_notes_with_empty_content()
                end,
            },
            ["no-frontmatter"] = {
                run = function()
                    require("vault.notes.actions").open_picker_notes_without_frontmatter()
                end,
            },
        },
    }
end

return M
