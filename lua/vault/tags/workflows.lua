local log = require("vault.log").scope("tags.workflows")

local M = {}

local function canonical_tag(tag_name)
    local tag = vim.trim(tostring(tag_name or ""))
    tag = tag:gsub("^#+", "")
    return tag
end

local function canonical_target_slug(slug)
    local value = vim.trim(tostring(slug or ""))
    value = value:gsub("^%[%[(.-)%]%]$", "%1")
    value = value:gsub("^#+", "")
    return value
end

local function hashtag_literal(tag_name)
    return "#" .. tag_name
end

local function make_wikilink(tag_name, note_slug)
    if note_slug == tag_name then
        return string.format("[[%s]]", note_slug)
    end
    return string.format("[[%s|%s]]", note_slug, tag_name)
end

local function filtered_occurrences(path, occurrences, keep_frontmatter_tags)
    if keep_frontmatter_tags then
        return occurrences
    end
    local note = require("vault.notes.note")(path)
    local frontmatter_end = note.data.frontmatter and note.data.frontmatter.end_line or 0
    local filtered = {}
    for _, occ in ipairs(occurrences or {}) do
        if occ.line > frontmatter_end then
            filtered[#filtered + 1] = occ
        end
    end
    return filtered
end

local function ensure_note_for_slug(note_slug)
    local path = require("vault.notes.paths").for_slug(note_slug)
    if vim.fn.filereadable(path) == 1 then
        return path, false
    end
    require("vault.notes.create").create(note_slug, { open = false })
    return path, true
end

local function clear_state_keys(keys)
    local state = require("vault.core.state")
    for _, key in ipairs(keys) do
        state.set_global_key(key, nil)
    end
end

function M.promote(tag_name, note_slug, opts)
    local canonical = canonical_tag(tag_name)
    if canonical == "" then error("No tag name provided") end
    note_slug = canonical_target_slug(note_slug or canonical)
    if note_slug == "" then error("No note slug provided") end
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
    local updated_notes, updated_occurrences = 0, 0
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
    clear_state_keys({ "cache.notes.paths", "cache.notes.slugs", "cache.notes.basename_index", "notes", "tags", "wikilinks" })
    if updated_notes == 0 then
        log.info("Prepared %s for #%s (kept frontmatter tags unchanged; no inline occurrences rewritten)", note_slug, canonical)
    else
        log.info("Promoted #%s -> %s across %d notes (%d occurrences)%s", canonical, new_link, updated_notes, updated_occurrences, created and "; created canonical note" or "")
    end
    return note_path
end

function M.open_promote_picker(tag_name, opts)
    local canonical = canonical_tag(tag_name)
    if canonical == "" then error("No tag name provided") end
    require("vault.ui.resolve_picker").open({
        wikilink = { data = { slug = canonical, suggestions = {} } },
        wikilinks = require("vault.wikilinks")().map,
        on_resolve = function(result)
            if not result or result.action == "skip" then return end
            local note_slug = result.slug or canonical
            if not note_slug or note_slug == "" then
                log.warn("Selected target has no usable slug")
                return
            end
            M.promote(canonical, note_slug, opts)
        end,
        on_cancel = function() end,
    })
end

return M
