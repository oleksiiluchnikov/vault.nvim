--- Bulk lowercase the first word of filenames matching "^[A-Z][a-z]+ - ".
---
--- Usage from Neovim (vault must be loaded):
---   :lua require("vault.scripts.bulk_lowercase").run()         -- dry run
---   :lua require("vault.scripts.bulk_lowercase").run(true)     -- apply
---
--- On macOS (case-insensitive FS), case-only renames go through a temporary
--- name to avoid ENOENT from fs_rename when old and new differ only by case.

local utils = require("vault.utils")
local log = require("vault.log").scope("bulk-lowercase")

local M = {}

--- Pattern: filename starts with a capitalized word followed by " - "
--- e.g. "Category - tasks.md", "Person - John.md", "Status - Done.md"
local MATCH_PATTERN = "^[A-Z][a-z]+ %- "

--- Check if a basename matches the pattern.
---@param basename string
---@return boolean
local function matches(basename)
    return basename:match(MATCH_PATTERN) ~= nil
end

--- Lowercase just the first word of a basename.
--- "Category - tasks.md" -> "category - tasks.md"
---@param basename string
---@return string
local function lowercase_first_word(basename)
    return basename:gsub("^(%u%l+)( %- )", function(word, sep)
        return word:lower() .. sep
    end)
end

--- Scan the vault and return a list of { old_path, new_path } rename specs.
---@return { old_path: string, new_path: string }[]
function M.plan()
    local scanner = require("vault.scanner")
    local paths = scanner.paths()

    ---@type { old_path: string, new_path: string }[]
    local moves = {}

    for _, entry in pairs(paths) do
        local path = entry.path
        local basename = vim.fn.fnamemodify(path, ":t")
        if matches(basename) then
            local new_basename = lowercase_first_word(basename)
            if new_basename ~= basename then
                local dir = vim.fn.fnamemodify(path, ":h")
                local new_path = dir .. "/" .. new_basename
                table.insert(moves, { old_path = path, new_path = new_path })
            end
        end
    end

    table.sort(moves, function(a, b) return a.old_path < b.old_path end)
    return moves
end

--- Execute the bulk rename.
--- On macOS case-insensitive FS, case-only renames need a two-step rename
--- (old -> tmp -> new) because fs_rename("Foo.md", "foo.md") is a no-op
--- on some FS drivers.
---
---@param apply? boolean If true, actually rename. Default: false (dry run).
function M.run(apply)
    apply = apply == true

    local moves = M.plan()
    if #moves == 0 then
        log.info("No files match the pattern — nothing to do")
        return
    end

    -- Print plan
    log.info("%s: %d files", apply and "APPLY" or "DRY RUN", #moves)
    for i, move in ipairs(moves) do
        local old_slug = utils.path_to_slug(move.old_path)
        local new_slug = utils.path_to_slug(move.new_path)
        log.info("  [%d] %s -> %s", i, old_slug, new_slug)
    end

    if not apply then
        log.info("Pass true to apply: require('vault.scripts.bulk_lowercase').run(true)")
        return
    end

    -- Phase 1: filesystem renames (two-step for case-insensitive FS)
    local uv = vim.uv or vim.loop
    local renamed = 0
    ---@type { old_path: string, new_path: string }[]
    local completed = {}

    for _, move in ipairs(moves) do
        local tmp_path = move.old_path .. ".__vault_rename_tmp__"
        local ok1, err1 = uv.fs_rename(move.old_path, tmp_path)
        if not ok1 then
            log.error("fs_rename to tmp failed: %s -> %s: %s",
                move.old_path, tmp_path, tostring(err1))
            goto continue
        end
        local ok2, err2 = uv.fs_rename(tmp_path, move.new_path)
        if not ok2 then
            -- Roll back
            uv.fs_rename(tmp_path, move.old_path)
            log.error("fs_rename from tmp failed: %s -> %s: %s",
                tmp_path, move.new_path, tostring(err2))
            goto continue
        end
        renamed = renamed + 1
        table.insert(completed, move)
        ::continue::
    end

    log.info("Renamed %d/%d files on disk", renamed, #moves)

    -- Phase 2: batch wikilink patching (single vault-wide scan)
    if #completed > 0 then
        local Watcher = require("vault.watcher")
        local watcher = Watcher()
        watcher:disable_oil_guard()

        ---@type { old_path: string, new_path: string }[]
        local rename_specs = {}
        for _, move in ipairs(completed) do
            table.insert(rename_specs, {
                old_path = move.old_path,
                new_path = move.new_path,
            })
        end

        local patched = watcher:handle_renames(rename_specs, false) or 0
        log.info("Patched wikilinks in %d files", patched)
    end

    -- Phase 3: invalidate caches
    local state = require("vault.core.state")
    pcall(function()
        state.set_global_key("cache.notes.paths", nil)
        state.set_global_key("cache.notes.slugs", nil)
        state.set_global_key("cache.notes.basename_index", nil)
        state.set_global_key("notes", nil)
    end)

    log.info("Done. %d files renamed, wikilinks patched.", renamed)
end

return M
