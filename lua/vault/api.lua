local M = {}

--- Open the picker with the given tag name
--- @param tag_name vault.Tag.data.name
--- @return nil
function M.open_picker_notes_with_tag(tag_name)
    if not tag_name then
        error("No tag name provided")
    end
    require("vault.pickers").notes({
        notes = require("vault.notes")():filter({
            search_term = "tags",
            include = { tag_name },
            exclude = {},
            match_opt = "exact",
            mode = "all",
            case_sensitive = false,
        }),
    })
end

--- Open the tag documentation with the given tag name
--- @param tag_name vault.Tag.data.name
--- @return nil
function M.edit_tag_documentation(tag_name)
    if not tag_name then
        error("No tag name provided")
    end
    local tag = require("vault.tags")():by("name", tag_name, "exact"):get_random_tag()
    if not tag then
        error("Tag not found")
    end
    if tag.data.documentation then
        tag.data.documentation:open()
    end
end

--- Rename the tag
--- @param from_tag_name vault.Tag.data.name
--- @param to_tag_name vault.Tag.data.name
function M.rename_tag(from_tag_name, to_tag_name)
    if not from_tag_name then
        error("No from tag name provided")
    end
    if not to_tag_name then
        error("No to tag name provided")
    end
    local tag = require("vault.tags")():by("name", from_tag_name, "exact"):get_random_tag()
    if not tag then
        error("Tag not found")
    end
    tag:rename(to_tag_name)
end

--- Move note
--- @param from_note_slug vault.slug
--- @param to_note_slug vault.slug
--- @return nil
function M.move_note(from_note_slug, to_note_slug)
    if not from_note_slug then
        error("No from note slug provided")
    end
    if not to_note_slug then
        error("No to note slug provided")
    end
    local note = require("vault.notes")().map[from_note_slug]
    if not note then
        vim.notify("Note not found")
    end
    require("vault.utils").slug_to_path(to_note_slug)
    note:move(to_note_slug)
end

return M
