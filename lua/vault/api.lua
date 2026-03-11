--- @module "telescope"
local pickers = require("telescope._extensions.vault.pickers")
local log = require("vault.log").scope("api")
local M = {}

---@class vault.ApiOccurrence
---@field lnum integer

---@alias vault.ApiOccurrenceList vault.ApiOccurrence[]

---@class vault.ApiResolveResult
---@field action? "skip"|"create"|string
---@field slug? vault.slug
---@field prompt? string

---@alias vault.ApiPromoteOpts { keep_frontmatter_tags?: boolean }
---@alias vault.ApiMergeOpts { body_strategy?: string, on_done?: fun() }

---@param keys string[]
local function clear_state_keys(keys)
    local state = require("vault.core.state")
    for _, key in ipairs(keys) do
        state.set_global_key(key, nil)
    end
end

---@param tag_name string
---@return string
local function canonical_tag(tag_name)
    local trimmed = vim.trim(tag_name or "")
    return trimmed:gsub("^#", "")
end

---@param tag_name string
---@return string
local function hashtag_literal(tag_name)
    return "#" .. canonical_tag(tag_name)
end

---@param tag_name string
---@param note_slug string
---@return string
local function make_wikilink(tag_name, note_slug)
    local canonical = canonical_tag(tag_name)
    if canonical == note_slug then
        return string.format("[[%s]]", note_slug)
    end
    return string.format("[[%s|%s]]", note_slug, canonical)
end

---@param path vault.path
---@param lnum integer
---@return boolean
local function line_is_in_frontmatter(path, lnum)
    if type(lnum) ~= "number" or lnum < 1 then
        return false
    end
    local lines = vim.fn.readfile(path)
    if #lines == 0 or lines[1] ~= "---" then
        return false
    end
    for index = 2, #lines do
        if lines[index] == "---" then
            return lnum < index
        end
    end
    return false
end

---@param path vault.path
---@param occurrences vault.ApiOccurrenceList|nil
---@param keep_frontmatter_tags boolean
---@return vault.ApiOccurrenceList
local function filtered_occurrences(path, occurrences, keep_frontmatter_tags)
    if not keep_frontmatter_tags then
        return occurrences
    end

    ---@type vault.ApiOccurrenceList
    local filtered = {}
    for _, occurrence in pairs(occurrences or {}) do
        local lnum = occurrence.lnum
        if not line_is_in_frontmatter(path, lnum) then
            filtered[#filtered + 1] = occurrence
        end
    end
    return filtered
end

---@param note_slug vault.slug
---@return vault.path path
---@return boolean created
local function ensure_note_for_slug(note_slug)
    local path = require("vault.notes.paths").for_slug(note_slug)
    if vim.fn.filereadable(path) == 1 then
        return path, false
    end

    require("vault.notes.create").create(note_slug, { open = false })
    return path, true
end

---@param slug vault.slug|string
---@return vault.slug|string
local function canonical_target_slug(slug)
    local utils = require("vault.utils")
    slug = vim.trim(slug or "")
    if slug == "" then
        return slug
    end

    local direct_path = utils.slug_to_path(slug)
    if vim.fn.filereadable(direct_path) == 1 then
        return slug
    end

    local wanted_stem = vim.fn.fnamemodify(slug, ":t")
    ---@type vault.slug[]
    local matches = {}
    for _, entry in pairs(require("vault.scanner").paths()) do
        if
            type(entry) == "table"
            and type(entry.path) == "string"
            and type(entry.slug) == "string"
        then
            local stem = vim.fn.fnamemodify(entry.path, ":t:r")
            if stem == wanted_stem then
                matches[#matches + 1] = entry.slug
            end
        end
    end

    if #matches == 1 then
        return matches[1]
    end

    return slug
end

---@param source string|nil
---@return vault.path|nil path
local function resolve_note_path(source)
    local utils = require("vault.utils")
    if type(source) == "string" and source ~= "" then
        if source:match("%.md$") and vim.fn.filereadable(source) == 1 then
            return vim.fn.fnamemodify(source, ":p")
        end
        local path = utils.slug_to_path(source)
        if vim.fn.filereadable(path) == 1 then
            return path
        end
        return nil
    end

    local current = vim.fn.expand("%:p")
    if
        type(current) == "string"
        and current ~= ""
        and current:match("%.md$")
        and vim.fn.filereadable(current) == 1
    then
        return current
    end
    return nil
end

--- Safe picker launch — handles nil return from empty results.
--- @param picker { find: fun(self: table): nil }|nil
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

--- Promote a hashtag into a canonical note wikilink.
--- Rewrites inline `#tag` occurrences to `[[note]]` and creates the note if needed.
--- Frontmatter tags are preserved by default.
---@param tag_name string
---@param note_slug? string
---@param opts? vault.ApiPromoteOpts
---@return vault.path|nil note_path
function M.promote_tag(tag_name, note_slug, opts)
    local canonical = canonical_tag(tag_name)
    if canonical == "" then
        error("No tag name provided")
    end

    note_slug = canonical_target_slug(note_slug or canonical)
    if note_slug == "" then
        error("No note slug provided")
    end

    opts = opts or {}
    local keep_frontmatter_tags = opts.keep_frontmatter_tags ~= false
    local note_path, created = ensure_note_for_slug(note_slug)

    local tag = require("vault.tags")():filter("name", canonical, "exact"):get_random()
    if not tag then
        if created then
            log.info("Created %s (no occurrences found for #%s)", note_slug, canonical)
        else
            log.info("No occurrences found for #%s", canonical)
        end
        return note_path
    end

    local old_name = hashtag_literal(canonical)
    local new_link = make_wikilink(canonical, note_slug)
    local Note = require("vault.notes.note")
    local updated_notes = 0
    local updated_occurrences = 0
    for slug, occurrences in pairs(tag.data.sources or {}) do
        local path = require("vault.utils").slug_to_path(slug)
        local filtered = filtered_occurrences(path, occurrences, keep_frontmatter_tags)
        if filtered and #filtered > 0 then
            local note = Note(path)
            note:update_content(old_name, new_link, filtered)
            updated_notes = updated_notes + 1
            updated_occurrences = updated_occurrences + #filtered
        end
    end

    clear_state_keys({
        "cache.notes.paths",
        "cache.notes.slugs",
        "cache.notes.basename_index",
        "notes",
        "tags",
        "wikilinks",
    })

    if updated_notes == 0 then
        log.info(
            "Prepared %s for #%s (kept frontmatter tags unchanged; no inline occurrences rewritten)",
            note_slug,
            canonical
        )
    else
        log.info(
            "Promoted #%s -> %s across %d notes (%d occurrences)%s",
            canonical,
            new_link,
            updated_notes,
            updated_occurrences,
            created and "; created canonical note" or ""
        )
    end

    return note_path
end

--- Open the wikilinks picker to choose a canonical note target for a tag promotion.
---@param tag_name string
---@param opts? vault.ApiPromoteOpts
function M.open_picker_promote_tag(tag_name, opts)
    local canonical = canonical_tag(tag_name)
    if canonical == "" then
        error("No tag name provided")
    end

    require("vault.ui.resolve_picker").open({
        wikilink = {
            data = {
                slug = canonical,
                suggestions = {},
            },
        },
        wikilinks = require("vault.wikilinks")().map,
        on_resolve = function(result)
            ---@cast result vault.ApiResolveResult|nil
            if not result or result.action == "skip" then
                return
            end
            local note_slug = result.slug or canonical
            if not note_slug or note_slug == "" then
                log.warn("Selected target has no usable slug")
                return
            end
            M.promote_tag(canonical, note_slug, opts)
        end,
        on_cancel = function() end,
    })
end

--- Merge one note into another note target.
--- If the target note does not exist yet, it is created first.
---@param source_note string slug or path of the note being absorbed
---@param target_slug string slug of the surviving note
---@param opts? vault.ApiMergeOpts
function M.merge_note(source_note, target_slug, opts)
    local source_path = resolve_note_path(source_note)
    if not source_path then
        error("Source note not found")
    end
    if not target_slug or vim.trim(target_slug) == "" then
        error("No target note slug provided")
    end

    local utils = require("vault.utils")
    local source_slug = utils.path_to_slug(source_path)
    target_slug = canonical_target_slug(target_slug)
    if target_slug == source_slug then
        log.warn("Source and target note are the same: %s", source_slug)
        return
    end

    local target_path = ensure_note_for_slug(target_slug)
    require("vault.merge").merge(target_path, source_path, opts or {})
end

--- Open the combined target picker to merge a source note into another note or wikilink target.
---@param source_note string|nil slug or path of the note being absorbed; defaults to current note
---@param opts? vault.ApiMergeOpts
function M.open_picker_merge_note(source_note, opts)
    local source_path = resolve_note_path(source_note)
    if not source_path then
        error("Source note not found")
    end

    local source_slug = require("vault.utils").path_to_slug(source_path)
    require("vault.ui.resolve_picker").open({
        wikilink = {
            data = {
                slug = source_slug,
                suggestions = {},
            },
        },
        prompt_slug = source_slug,
        include_create = false,
        wikilinks = require("vault.wikilinks")().map,
        on_resolve = function(result)
            ---@cast result vault.ApiResolveResult|nil
            if not result or result.action == "skip" then
                return
            end
            local target_slug = result.slug
            if not target_slug or target_slug == "" then
                log.warn("Selected target has no usable slug")
                return
            end
            M.merge_note(source_path, canonical_target_slug(target_slug), opts)
        end,
        on_cancel = function() end,
    })
end

--- Smart retarget flow for a source note.
--- Selecting an existing target merges into it; selecting create renames the source to the current query.
---@param source_note string|nil slug or path of the source note; defaults to current note
---@param opts? vault.ApiMergeOpts
function M.open_picker_retarget_note(source_note, opts)
    local source_path = resolve_note_path(source_note)
    if not source_path then
        error("Source note not found")
    end

    local utils = require("vault.utils")
    local source_slug = utils.path_to_slug(source_path)
    local Note = require("vault.notes.note")
    require("vault.ui.resolve_picker").open({
        wikilink = {
            data = {
                slug = source_slug,
                suggestions = {},
            },
        },
        prompt_slug = source_slug,
        include_create = true,
        wikilinks = require("vault.wikilinks")().map,
        on_resolve = function(result)
            ---@cast result vault.ApiResolveResult|nil
            if not result or result.action == "skip" then
                return
            end

            if result.action == "create" then
                local target_slug = vim.trim(result.prompt or "")
                if target_slug == "" then
                    target_slug = source_slug
                end
                if target_slug == source_slug then
                    return
                end
                Note(source_path):rename(target_slug)
                if opts and opts.on_done then
                    opts.on_done()
                end
                return
            end

            local target_slug = result.slug
            if not target_slug or target_slug == "" then
                log.warn("Selected target has no usable slug")
                return
            end
            M.merge_note(source_path, canonical_target_slug(target_slug), opts)
        end,
        on_cancel = function() end,
    })
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
        local values = properties.map[property_name].data.values
        if value_name then
            sources = values[value_name].data.sources
        else
            sources = add_sources(sources, values)
        end
    else
        for _, property in pairs(properties.map) do
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
