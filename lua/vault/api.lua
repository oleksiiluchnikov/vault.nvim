local M = {}

--- Open the picker with the given tag name
--- @param tag_name vault.Tag.Data.name
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
--- @param tag_name vault.Tag.Data.name
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
--- @param from_tag_name vault.Tag.Data.name
--- @param to_tag_name vault.Tag.Data.name
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

function M.open_picker_property_values(property_name)
    local properties = require("vault.properties")()
    local values = properties.map[property_name].data.values
    -- pick_value(opts, property_name, values, on_value_selected)
    require("vault.pickers").property_values({
        prompt_title = property_name,
        values = values,
    })
end

function M.open_picker_notes_with_property_value(property_name, value_name)
    local properties = require("vault.properties")()
    local values = properties.map[property_name].data.values
    local value = values[value_name]
    local sources = value.data.sources
    local slugs = vim.tbl_keys(sources)

    local notes = require("vault.notes")()

    notes.map = {}
    for _, slug in ipairs(slugs) do
        local path = require("vault.utils").slug_to_path(slug)
        local note = require("vault.notes.note")(path)
        notes:add_note(note)
    end
    -- vault_pickers.notes(opts)
    require("vault.pickers").notes({
        notes = notes,
    })
end

function M.open_picker_notes_in_directory(directory)
    require("vault.pickers").notes({
        notes = require("vault.notes")():with_relpath(directory, "startswith", false),
    })
end

--- Open the picker with the given property name
--- if property_name is not provided, it will open collect notes with empty property values
--- @param property_name? vault.Property.Data.name
--- @param value_name? vault.Property.Value.Data.name
function M.open_picker_notes_with_empty_property_value(property_name, value_name)
    local properties = require("vault.properties")()
    local values = {}
    local empty_values = {
        "",
        ".nan",
        "unknown",
        "not applicable",
        "n/a",
        "none",
    }
    local function add_sources(sources, property)
        for k, value in pairs(property.data.values) do
            if vim.tbl_contains(empty_values, k) then
                if value.data.sources then
                    for slug, occurences in pairs(value.data.sources) do
                        if sources[slug] == nil then
                            sources[slug] = occurences
                        else
                            sources[slug] = vim.tbl_extend("force", sources[slug], occurences)
                        end
                    end
                end
            end
        end
        return sources
    end
    local sources = {}
    if property_name then
        values = properties.map[property_name].data.values
        if value_name then
            sources = values[value_name].data.sources
        else
            sources = add_sources(sources, values)
        end
    else
        for _, property in pairs(properties.map) do
            values = property.data.values
            sources = add_sources(sources, property)
        end
    end
    local slugs = vim.tbl_keys(sources)

    local notes = require("vault.notes")()

    notes.map = {}
    for _, slug in ipairs(slugs) do
        local path = require("vault.utils").slug_to_path(slug)
        local note = require("vault.notes.note")(path)
        notes:add_note(note)
    end
    -- vault_pickers.notes(opts)
    require("vault.pickers").notes({
        notes = notes,
    })
end

--- Open the picker with note with empty content
function M.open_picker_notes_with_empty_content()
    local empty_vim_regex_patterns = {
        -- No any character
        [[^\(\s*|\n*\})$]],
        -- TODO: Has heading, but no further content
    }

    local pattern = empty_vim_regex_patterns[1]
    if vim.tbl_count(empty_vim_regex_patterns) > 1 then
        pattern = table.concat(empty_vim_regex_patterns, "|")
        pattern = [[(]] .. pattern .. [[)]]
    end
    print(pattern)
    -- error("Pattern: " .. pattern)
    -- error("Pattern: " .. pattern)

    require("vault.pickers").notes({
        notes = require("vault.notes")():with_content(pattern, "regex", false),
    })
end

--- Open the picker with note without frontmatter(not starting with ---)
function M.open_picker_notes_without_frontmatter()
    require("vault.pickers").notes({
        notes = require("vault.notes")():without_frontmatter(),
    })
end

return M
