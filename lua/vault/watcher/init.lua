--- Vault file watcher for automatic link resolution on renames
--- @module vault.watcher

local uv = vim.uv
local config = require("vault.config")
local utils = require("vault.utils")
local state = require("vault.core.state")
local Note = require("vault.notes.note")
local Wikilinks = require("vault.wikilinks")

--- @class vault.Watcher: vault.Object
local Watcher = require("vault.core.object")("VaultWatcher")

function Watcher:init()
    self.handle = nil
    self.timer = uv.new_timer()
    self.deleted_paths = {}
    self.is_watching = false
    self.debouncer = vim.uv.new_timer()
end

function Watcher:start()
    if self.is_watching then
        return
    end
    local root = config.options.root

    self.handle = uv.new_fs_event()
    local ok = pcall(function()
        self.handle:start(
            root,
            { recursive = true },
            vim.schedule_wrap(function(err, filename, events)
                if err then
                    return
                end
                self:on_event(filename, events)
            end)
        )
    end)

    if ok then
        self.is_watching = true
        vim.notify("Vault watcher started", vim.log.levels.INFO, { title = "Vault" })
    end
end

function Watcher:stop()
    if not self.is_watching then
        return
    end
    if self.handle then
        self.handle:stop()
        if not self.handle:is_closing() then
            self.handle:close()
        end
    end
    if self.timer then
        self.timer:stop()
        if not self.timer:is_closing() then
            self.timer:close()
        end
    end
    self.is_watching = false
    self.deleted_paths = {}
end

function Watcher:on_event(filename, events)
    if not filename or not filename:match("%.md$") then
        return
    end
    local slug = filename:gsub(config.options.ext, "")
    local full_path = utils.slug_to_path(slug)
    local exists = vim.fn.filereadable(full_path) == 1
    local now = os.time()

    if not exists then
        self.deleted_paths[full_path] = now
        -- Cleanup old deletions
        for path, ts in pairs(self.deleted_paths) do
            if now - ts > 2 then
                self.deleted_paths[path] = nil
            end
        end
    else
        for old_path, ts in pairs(self.deleted_paths) do
            if now - ts < 2 then
                self.deleted_paths[old_path] = nil
                self:on_rename(old_path, full_path)
                return
            end
        end
    end
end

--- Execute the rename logic
function Watcher:on_rename(old_path, new_path)
    local old_slug = utils.path_to_slug(old_path)
    local new_slug = utils.path_to_slug(new_path)

    local count = 0
    local wikilinks = require("vault.wikilinks")():by_target(old_slug)
    local source_paths = {}
    for source_slug, wikilink in pairs(wikilinks) do
        local source_path = wikilink.data.source.path
        vim.notify(string.format("Found %s -> %s", old_slug, new_slug))
        vim.notify(string.format("Updating link in %s", source_path))
        -- local note = Note(source_path)
        -- note:update_content(old_slug, new_slug,
        -- count = count + 1
    end

    return count
end

function Watcher:cleanup()
    self:stop()
end

-- lua/vault/watcher/init.lua
---------------------------------------------------------------
--- Resolve all wiki-links that point to `old_path`
---@param old_path string absolute
---@param new_path string absolute
---@return integer updated_files  number of files touched
function Watcher:handle_rename(old_path, new_path)
    -- fast-exit ────────────────────────────────────────────────
    if old_path == new_path or not old_path or not new_path then
        return 0
    end

    local old_slug = utils.path_to_slug(old_path)
    local new_slug = utils.path_to_slug(new_path)

    -- collect every wikilink that still points to the *old* slug
    local wl_source_map = Wikilinks():by_target(old_slug, "exact", false)

    local updated = 0
    for _, wl in pairs(wl_source_map) do
        for source_slug, occ in pairs(wl.data.sources) do
            local note_path = utils.slug_to_path(source_slug)
            local note = Note(note_path)
            note:update_content(old_slug, new_slug, occ) -- *non-blocking* text replace
            updated = updated + 1
        end
    end

    vim.schedule(function()
        vim.notify(
            string.format(
                "[vault] renamed %s → %s • %d files patched",
                old_slug,
                new_slug,
                updated
            ),
            vim.log.levels.INFO
        )
    end)

    return updated
end

--- @alias vault.Watcher.constructor fun(): vault.Watcher
local VaultWatcher = Watcher
state.set_global_key("class.vault.Watcher", VaultWatcher)
return VaultWatcher
