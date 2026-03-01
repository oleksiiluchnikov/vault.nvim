-- lua/vault/watcher/init.lua
-- File watcher + rename handler for updating wikilinks across the vault.

local uv = vim.uv or vim.loop

local config = require("vault.config")
local utils = require("vault.utils")
local state = require("vault.core.state")
local log = require("vault.log").scope("watcher")

--- @class vault.Watcher: vault.Object
local Watcher = require("vault.core.object")("VaultWatcher")

function Watcher:init()
    --- @type uv_fs_event_t|nil
    self.handle = nil

    --- Debounce timer for bursty FS events (optional use)
    --- @type uv_timer_t|nil
    self.debouncer = uv.new_timer()

    --- Track deletes to detect renames (most FS APIs report rename as delete+create)
    --- @type table<string, number>
    self.deleted_paths = {}

    self.is_watching = false

    --- Window in which delete+create is interpreted as a rename
    self.rename_window_sec = 2

    --- Flag to control whether to guard against oil.nvim conflicts
    self.oil_guard_enabled = true

    --- Suppression flag: when true, on_event ignores fs events.
    --- Set during wikilink patching to avoid the watcher reacting to its own writes.
    self._writing = false
end

--- Normalize filename reported by fs_event into an absolute path
--- Some platforms give relative filenames, some absolute, some nil.
local function normalize_event_path(root, filename)
    if not filename or filename == "" then
        return nil
    end
    -- If it's already absolute, keep it
    if filename:sub(1, 1) == "/" then
        return filename
    end
    return root .. "/" .. filename
end

--- Start recursive watching of the configured vault root
function Watcher:start()
    if self.is_watching then
        return
    end

    local root = config.options.root
    if type(root) ~= "string" or root == "" then
        error("vault.watcher: config.options.root is not set")
    end

    if vim.fn.isdirectory(root) == 0 then
        error("vault.watcher: root directory does not exist: " .. tostring(root))
    end

    self.handle = uv.new_fs_event()

    local ok, err = pcall(function()
        self.handle:start(
            root,
            { recursive = true },
            vim.schedule_wrap(function(fs_err, filename, events)
                if fs_err then
                    return
                end
                self:on_event(filename, events)
            end)
        )
    end)

    if not ok then
        self.handle = nil
        error("vault.watcher: failed to start: " .. tostring(err))
    end

    self.is_watching = true
end

function Watcher:stop()
    if not self.is_watching then
        return
    end

    if self.handle then
        pcall(function()
            self.handle:stop()
        end)
        pcall(function()
            if not self.handle:is_closing() then
                self.handle:close()
            end
        end)
        self.handle = nil
    end

    if self.debouncer then
        pcall(function()
            self.debouncer:stop()
        end)
    end

    self.deleted_paths = {}
    self.is_watching = false
end

function Watcher:cleanup()
    self:stop()
end

--- Handle a filesystem event inside the vault root.
--- We interpret rename as:
---     file disappeared -> (within rename_window_sec) new file appeared
function Watcher:on_event(filename, events)
    -- Ignore events triggered by our own wikilink patching writes
    if self._writing then
        return
    end

    local root = config.options.root
    local full_path = normalize_event_path(root, filename)
    if not full_path then
        return
    end

    -- Check if this is a .base file change
    local base_ext = (config.options.bases and config.options.bases.ext) or ".base"
    if full_path:match(vim.pesc(base_ext) .. "$") then
        self:handle_base_change(full_path)
        return
    end

    -- Only care about markdown notes
    if not full_path:match(vim.pesc(config.options.ext) .. "$") then
        return
    end

    local now = os.time()
    local exists = vim.fn.filereadable(full_path) == 1

    -- Cleanup old deletion markers
    for path, ts in pairs(self.deleted_paths) do
        if now - ts > self.rename_window_sec then
            self.deleted_paths[path] = nil
        end
    end

    if not exists then
        -- Mark as deleted; if something appears shortly, treat as rename
        self.deleted_paths[full_path] = now
        return
    end

    -- A file appeared/changed; if we have a recent deletion, treat as rename.
    -- Pick the best match: prefer a deletion whose stem matches the new file's
    -- stem (handles renames within the same directory). Fall back to the most
    -- recent deletion within the time window.
    local new_stem = vim.fn.fnamemodify(full_path, ":t:r")
    local best_path = nil
    local best_ts = nil
    local best_stem_match = false
    for path, ts in pairs(self.deleted_paths) do
        if (now - ts) <= self.rename_window_sec then
            local stem = vim.fn.fnamemodify(path, ":t:r")
            local stem_match = (stem == new_stem)
            -- Prefer: stem match > most recent timestamp
            if best_path == nil
                or (stem_match and not best_stem_match)
                or (stem_match == best_stem_match and ts > best_ts) then
                best_path = path
                best_ts = ts
                best_stem_match = stem_match
            end
        end
    end

    if best_path then
        self.deleted_paths[best_path] = nil
        self:handle_rename(best_path, full_path)
    end
end

--- Internal: perform the actual rename link updates
--- @param old_path string
--- @param new_path string
--- @param old_slug string
--- @param new_slug string
--- @param silent? boolean  suppress notifications (default: honor config.watcher.notify_on_rename)
--- @return integer
function Watcher:_do_rename_update(old_path, new_path, old_slug, new_slug, silent)
    local scanner = require("vault.scanner")
    local paths = scanner.paths()

    -- Obsidian wikilinks typically use the stem (filename without extension
    -- or directory), e.g. [[My Note]].  Some vaults use the full relative
    -- path form [[Notes/My Note]].  We must handle both, but be careful:
    -- stems can collide across directories (e.g. Notes/Foo and Clippings/Foo
    -- both have stem "Foo").  Only match on the bare stem when it is unique
    -- across the entire vault; otherwise restrict to the full-slug form to
    -- avoid patching links that point to a *different* note with the same name.
    local old_stem = vim.fn.fnamemodify(old_path, ":t:r")
    local new_stem = vim.fn.fnamemodify(new_path, ":t:r")

    -- Check stem uniqueness: count how many notes share the old stem.
    local stem_count = 0
    for slug, _ in pairs(paths) do
        local s = slug:match("[^/]+$") -- last path component = stem
        if s == old_stem then
            stem_count = stem_count + 1
            if stem_count > 1 then break end -- no need to keep counting
        end
    end
    local stem_is_unique = (stem_count <= 1)

    -- Build match patterns.  Full-slug form is always safe.
    -- Stem-only form is only safe when the stem is unique across the vault.
    local patterns = {}
    local escaped_slug = vim.pesc(old_slug)
    local escaped_stem = vim.pesc(old_stem)

    -- Full-slug form: [[Notes/My Note]] or [[Notes/My Note|alias]]
    table.insert(patterns, {
        match = "%[%[" .. escaped_slug,
        gsub_pat = "%[%[" .. escaped_slug .. "([^%]]*)%]%]",
        replacement = "[[" .. new_stem .. "%1]]",
    })
    -- Stem-only form: [[My Note]] or [[My Note|alias]]
    -- Only when stem is unique AND differs from slug (note is in a subdir)
    if stem_is_unique and old_stem ~= old_slug then
        table.insert(patterns, {
            match = "%[%[" .. escaped_stem,
            gsub_pat = "%[%[" .. escaped_stem .. "([^%]]*)%]%]",
            replacement = "[[" .. new_stem .. "%1]]",
        })
    end

    -- First pass: collect pending changes without writing files so we can prompt
    local pending = {}

    for _, entry in pairs(paths) do
        local note_path = entry.path
        local f = io.open(note_path, "r")
        if f then
            local content = f:read("*all")
            f:close()

            local total_n = 0
            local cur = content
            for _, pat in ipairs(patterns) do
                if cur:match(pat.match) then
                    local replaced, n = cur:gsub(pat.gsub_pat, pat.replacement)
                    if n and n > 0 then
                        cur = replaced
                        total_n = total_n + n
                    end
                end
            end
            if total_n > 0 then
                pending[note_path] = { new_content = cur, count = total_n }
            end
        end
    end

    -- Total replacements
    local total = 0
    for _, v in pairs(pending) do
        total = total + (v.count or 0)
    end

    local watcher_conf = (config.options and config.options.watcher) or {}
    local prompt = watcher_conf.prompt_on_rename
    if prompt == nil then
        prompt = true
    end

    --- Apply the pending wikilink patches, update frontmatter, buffers, and state.
    --- Extracted so it can be called synchronously or from an async confirm callback.
    --- @return integer updated  number of files patched
    local function apply_rename()
        -- Apply pending changes — suppress watcher during writes to avoid self-triggered events
        self._writing = true
        local updated = 0
        local updated_paths = {}
        for path, info in pairs(pending) do
            local ok_sw, sw_err = pcall(utils.safe_write, path, info.new_content)
            if ok_sw then
                updated = updated + 1
                updated_paths[path] = true
            else
                vim.schedule(function()
                    log.warn("safe_write failed: %s", tostring(sw_err))
                end)
            end
        end

        -- Update frontmatter on the renamed file if configured
        local fm_key = watcher_conf.frontmatter_key
        if fm_key and fm_key ~= "" then
            local f = io.open(new_path, "r")
            if f then
                local content = f:read("*all")
                f:close()

                -- find YAML frontmatter (---\n ... ---\n)
                local fm_start, fm_end = content:find("^%-%-%-\n.-\n%-%-%-\n")
                if fm_start then
                    local fm_block = content:sub(fm_start, fm_end)
                    local pattern_fm = "(" .. fm_key .. "%s*:%s*)(.-)(\n)"
                    if fm_block:match(fm_key .. "%s*:") then
                        fm_block = fm_block:gsub(pattern_fm, "%1" .. new_slug .. "%3")
                    else
                        -- insert key right after opening ---\n
                        fm_block =
                            fm_block:gsub("^(%-%-%-\n)", "%1" .. fm_key .. ": " .. new_slug .. "\n")
                    end
                    local new_content = content:sub(1, fm_start - 1)
                        .. fm_block
                        .. content:sub(fm_end + 1)
                    utils.safe_write(new_path, new_content)
                else
                    -- no frontmatter: add one with key and relpath
                    local rel = utils.path_to_relpath(new_path)
                    local fm = "---\n"
                        .. fm_key
                        .. ": "
                        .. new_slug
                        .. "\nrelpath: "
                        .. rel
                        .. "\n---\n\n"
                    utils.safe_write(new_path, fm .. content)
                end
            end
        end

        self._writing = false

        -- Update open buffers: rename any buffer that pointed to the old path
        for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
            if vim.api.nvim_buf_is_loaded(bufnr) then
                local name = vim.api.nvim_buf_get_name(bufnr)
                if name == old_path then
                    local modified = vim.bo[bufnr].modified
                    pcall(vim.api.nvim_buf_set_name, bufnr, new_path)
                    vim.bo[bufnr].modified = modified
                    -- Re-attach LSP clients so they track the new URI
                    for _, client in pairs(vim.lsp.get_clients({ bufnr = bufnr })) do
                        pcall(vim.lsp.buf_detach_client, bufnr, client.id)
                        pcall(vim.lsp.buf_attach_client, bufnr, client.id)
                    end
                end
            end
        end

        -- Reload open buffers whose files were patched (wikilinks changed on disk)
        for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
            if vim.api.nvim_buf_is_loaded(bufnr) and updated_paths[vim.api.nvim_buf_get_name(bufnr)] then
                vim.api.nvim_buf_call(bufnr, function()
                    pcall(vim.cmd, "checktime")
                end)
            end
        end

        -- Record rename in global state for other subsystems to pick up
        pcall(function()
            state.set_global_key(
                "vault.last_rename",
                { old = old_path, new = new_path, old_slug = old_slug, new_slug = new_slug }
            )
        end)

        if not silent then
            vim.schedule(function()
                log.info("renamed %s → %s • %d files patched", old_slug, new_slug, updated)
            end)
        end

        return updated
    end

    -- Fast path: no prompt needed (disabled or no files to patch)
    if not prompt or total == 0 then
        return apply_rename()
    end

    -- Async path: show non-blocking confirm popup, apply on "yes"
    require("vault.ui.confirm").confirm({
        message = string.format(
            "Rename %s → %s will patch %d file(s). Apply?",
            old_slug, new_slug, total
        ),
        title = "Vault Rename",
        on_yes = function() apply_rename() end,
        on_no = function()
            if not silent then
                log.info("Rename patch cancelled")
            end
        end,
    })
    return 0
end

--- Handle a .base file change (created, modified, or deleted).
--- Invalidates the bases cache so the next access rescans.
--- @param full_path string absolute path to the changed .base file
function Watcher:handle_base_change(full_path)
    -- Invalidate the scanner cache for base files
    pcall(function()
        state.set_global_key("cache.bases.raw", nil)
    end)

    -- Invalidate the Bases collection instance
    pcall(function()
        state.set_global_key("bases", nil)
    end)
end


--- Resolve all wiki-links that point to `old_path` by scanning all notes
--- and replacing occurrences of [[old_slug...]] with [[new_slug...]].
--- Returns number of files patched.
--- @param old_path string absolute
--- @param new_path string absolute
--- @param silent? boolean  suppress notifications (default: honor config.watcher.notify_on_rename)
--- @return integer
function Watcher:handle_rename(old_path, new_path, silent)
    if old_path == new_path or not old_path or not new_path then
        return 0
    end

    -- `utils.path_to_slug` depends on config.options.root/ext. Guard it.
    local ok_old, old_slug = pcall(utils.path_to_slug, old_path)
    local ok_new, new_slug = pcall(utils.path_to_slug, new_path)
    if not ok_old or not ok_new then
        return 0
    end

    -- Resolve silent: explicit param > config.watcher.notify_on_rename > default (show)
    if silent == nil then
        local watcher_conf = (config.options and config.options.watcher) or {}
        if watcher_conf.notify_on_rename == false then
            silent = true
        else
            silent = false
        end
    end

    -- Defer processing if oil is active to let it complete its operations
    if self.oil_guard_enabled and package.loaded["oil"] then
        vim.defer_fn(function()
            self:_do_rename_update(old_path, new_path, old_slug, new_slug, silent)
        end, 1000)
        return 0
    end

    return self:_do_rename_update(old_path, new_path, old_slug, new_slug, silent)
end

--- Disable the oil guard to allow renames even when oil is loaded
--- @return nil
function Watcher:disable_oil_guard()
    self.oil_guard_enabled = false
end

--- Enable the oil guard
--- @return nil
function Watcher:enable_oil_guard()
    self.oil_guard_enabled = true
end

---@alias vault.Watcher.constructor fun(): vault.Watcher
local VaultWatcher = Watcher
state.set_global_key("class.vault.Watcher", VaultWatcher)
return VaultWatcher
