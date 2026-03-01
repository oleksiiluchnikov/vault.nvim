--- @module "telescope"
local pickers = require("telescope._extensions.vault.pickers")
local log = require("vault.log").scope("api")
local M = {}

--- Safe picker launch — handles nil return from empty results.
--- @param picker any
--- @param empty_msg? string
local function safe_find(picker, empty_msg)
    if picker then
        picker:find()
    else
        log.info(empty_msg or "No results found")
    end
end

--- Open the picker with the given tag name
--- @param tag_name vault.Tag.Data.name
--- @return nil
function M.open_picker_notes_with_tag(tag_name)
    if not tag_name then
        error("No tag name provided")
    end
    safe_find(
        pickers.notes({
            notes = require("vault.notes")():filter({
                search_term = "tags",
                include = { tag_name },
                exclude = {},
                match_opt = "exact",
                mode = "all",
                case_sensitive = false,
            }),
        }),
        "No notes found with tag: " .. tag_name
    )
end

--- Open the tag documentation with the given tag name
--- @param tag_name vault.Tag.Data.name
--- @return nil
function M.edit_tag_documentation(tag_name)
    if not tag_name then
        error("No tag name provided")
    end
    --- @type vault.Tag
    local tag = require("vault.tags")():filter("name", tag_name, "exact"):get_random()
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
    --- @type vault.Tag
    local tag = require("vault.tags")():filter("name", from_tag_name, "exact"):get_random()
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
        log.warn("Note not found: %s", tostring(from_note_slug))
        return
    end
    require("vault.utils").slug_to_path(to_note_slug)
    note:move(to_note_slug)
end

function M.open_picker_property_values(property_name)
    local properties = require("vault.properties")()
    local prop = properties.map[property_name]
    if not prop then
        log.warn("Property not found: %s", tostring(property_name))
        return
    end
    local values = prop.data.values
    -- pick_value(opts, property_name, values, on_value_selected)
    safe_find(
        pickers.property_values({
            prompt_title = property_name,
            values = values,
        }),
        "No values found for property: " .. property_name
    )
end

function M.open_picker_notes_with_property_value(property_name, value_name)
    local properties = require("vault.properties")()
    local prop = properties.map[property_name]
    if not prop then
        log.warn("Property not found: %s", tostring(property_name))
        return
    end
    local values = prop.data.values
    local value = values[value_name]
    if not value then
        log.warn("Value not found: %s[%s]", tostring(property_name), tostring(value_name))
        return
    end
    local sources = value.data.sources
    local slugs = vim.tbl_keys(sources)

    local notes = require("vault.notes")()

    notes.map = {}
    for _, slug in ipairs(slugs) do
        local path = require("vault.utils").slug_to_path(slug)
        local note = require("vault.notes.note")(path)
        notes:push(note)
    end
    safe_find(pickers.notes({ notes = notes }), "No notes found for property value")
end

function M.open_picker_notes_in_directory(directory)
    safe_find(
        pickers.notes({
            notes = require("vault.notes")():filter("relpath", directory, "startswith", false),
        }),
        "No notes found in directory: " .. tostring(directory)
    )
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
        notes:push(note)
    end
    safe_find(pickers.notes({ notes = notes }), "No notes with empty property values")
end

--- Open the picker with note with empty content
function M.open_picker_notes_with_empty_content()
    local empty_vim_regex_patterns = {
        -- Match content that is only whitespace/newlines
        [[^\s*$]],
        -- TODO: Has heading, but no further content
    }

    local pattern = empty_vim_regex_patterns[1]
    if vim.tbl_count(empty_vim_regex_patterns) > 1 then
        pattern = table.concat(empty_vim_regex_patterns, "|")
        pattern = [[(]] .. pattern .. [[)]]
    end

    safe_find(
        pickers.notes({
            notes = require("vault.notes")():filter("content", pattern, "regex", false),
        }),
        "No notes with empty content"
    )
end

--- Open the picker with note without frontmatter(not starting with ---)
function M.open_picker_notes_without_frontmatter()
    safe_find(
        pickers.notes({
            -- notes = require("vault.notes")():without_frontmatter(),
            notes = require("vault.notes")():filter("content", [=[^\(---\)\@!.*$]=], "regex", true),
        }),
        "No notes without frontmatter"
    )
end

-- lua require('telescope._extensions.vault.pickers.lines')({lines = require('vault.lines')():filter("content", "^- [A-Za-z]", "regex", false)}):find()
--- Open the picker with lines that starts with "- "
function M.open_picker_lines_starting_with_dash()
    safe_find(
        pickers.lines({
            lines = require("vault.lines")()
                :filter_by_source("journal", "startswith", false)
                :filter("content", "^- [A-Za-z0-9]", "regex", false),
        }),
        "No lines starting with dash"
    )
end

--- Open the picker with all bases (Level 1)
--- @return nil
function M.open_picker_bases()
    safe_find(pickers.bases(), "No bases found")
end

--- Open the picker with matched notes for a specific base (Level 2)
--- @param base_name string
--- @return nil
function M.open_picker_base_notes(base_name)
    if not base_name then
        error("No base name provided")
    end
    local bases = require("vault.bases")()
    local base = bases:get(base_name)
    if not base then
        log.error("Base not found: %s", tostring(base_name))
        return
    end
    local base_notes_picker = require("telescope._extensions.vault.pickers.bases.notes")
    local picker = base_notes_picker({ base = base })
    if picker then
        picker:find()
    end
end

return M
