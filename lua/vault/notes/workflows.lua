local log = require("vault.log").scope("notes.workflows")

local M = {}

local function canonical_target_slug(slug)
    local value = vim.trim(tostring(slug or ""))
    value = value:gsub("^%[%[(.-)%]%]$", "%1")
    if value ~= "" then
        local notes = require("vault.notes")()
        if notes.map[value] then
            return value
        end
        local matches = {}
        for slug_key, _ in pairs(notes.map) do
            local stem = slug_key:match("([^/]+)$") or slug_key
            if stem == value then
                matches[#matches + 1] = slug_key
            end
        end
        if #matches == 1 then
            return matches[1]
        end
    end
    return value
end

local function resolve_note_path(note_ref)
    if type(note_ref) == "string" and note_ref ~= "" then
        if note_ref:match("^/") or note_ref:match("%.md$") then
            return note_ref
        end
        local utils = require("vault.utils")
        return utils.slug_to_path(note_ref)
    end
    local current = vim.fn.expand("%:p")
    if type(current) == "string" and current ~= "" and current:match("%.md$") then
        return current
    end
    return nil
end

local function ensure_note_for_slug(note_slug)
    local path = require("vault.notes.paths").for_slug(note_slug)
    if vim.fn.filereadable(path) == 1 then
        return path, false
    end
    require("vault.notes.create").create(note_slug, { open = false })
    return path, true
end

function M.merge(source_note, target_slug, opts)
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

function M.open_merge_picker(source_note, opts)
    local source_path = resolve_note_path(source_note)
    if not source_path then
        error("Source note not found")
    end
    local source_slug = require("vault.utils").path_to_slug(source_path)
    require("vault.ui.resolve_picker").open({
        wikilink = { data = { slug = source_slug, suggestions = {} } },
        prompt_slug = source_slug,
        include_create = false,
        wikilinks = require("vault.wikilinks")().map,
        on_resolve = function(result)
            if not result or result.action == "skip" then return end
            local target_slug = result.slug
            if not target_slug or target_slug == "" then
                log.warn("Selected target has no usable slug")
                return
            end
            M.merge(source_path, canonical_target_slug(target_slug), opts)
        end,
        on_cancel = function() end,
    })
end

function M.open_retarget_picker(source_note, opts)
    local source_path = resolve_note_path(source_note)
    if not source_path then
        error("Source note not found")
    end

    local utils = require("vault.utils")
    local source_slug = utils.path_to_slug(source_path)
    local Note = require("vault.notes.note")
    require("vault.ui.resolve_picker").open({
        wikilink = { data = { slug = source_slug, suggestions = {} } },
        prompt_slug = source_slug,
        include_create = true,
        wikilinks = require("vault.wikilinks")().map,
        on_resolve = function(result)
            if not result or result.action == "skip" then return end
            if result.action == "create" then
                local target_slug = vim.trim(result.prompt or "")
                if target_slug == "" then target_slug = source_slug end
                if target_slug == source_slug then return end
                Note(source_path):rename(target_slug)
                if opts and opts.on_done then opts.on_done() end
                return
            end
            local target_slug = result.slug
            if not target_slug or target_slug == "" then
                log.warn("Selected target has no usable slug")
                return
            end
            M.merge(source_path, canonical_target_slug(target_slug), opts)
        end,
        on_cancel = function() end,
    })
end

return M
