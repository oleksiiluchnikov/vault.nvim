-- lua/vault/watcher/init.lua
-- File watcher + rename handler for updating wikilinks across the vault.

local uv = vim.uv or vim.loop

local config = require("vault.config")
local utils = require("vault.utils")
local state = require("vault.core.state")

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

    -- A file appeared/changed; if we have a recent deletion, treat as rename
    local old_path = nil
    local old_ts = nil
    for path, ts in pairs(self.deleted_paths) do
        old_path = path
        old_ts = ts
        break
    end

    if old_path and old_ts and (now - old_ts) <= self.rename_window_sec then
        self.deleted_paths[old_path] = nil
        self:handle_rename(old_path, full_path)
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
        ::continue_file::
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

    if prompt and total > 0 then
        -- Ask the user to confirm before applying changes
        local ok = vim.fn.confirm(
            string.format(
                "[vault] Rename %s → %s will patch %d files. Apply?",
                old_slug,
                new_slug,
                total
            ),
            "&Yes\n&No",
            2
        )
        if ok ~= 1 then
            return 0
        end
    end

    -- Apply pending changes
    local updated = 0
    local updated_paths = {}
    for path, info in pairs(pending) do
        local ok_sw, sw_err = pcall(utils.safe_write, path, info.new_content)
        if ok_sw then
            updated = updated + 1
            updated_paths[path] = true
        else
            vim.schedule(function()
                vim.notify("[vault] safe_write failed: " .. tostring(sw_err), vim.log.levels.WARN)
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
                local pattern = "(" .. fm_key .. "%s*:%s*)(.-)(\n)"
                if fm_block:match(fm_key .. "%s*:") then
                    fm_block = fm_block:gsub(pattern, "%1" .. new_slug .. "%3")
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

    -- Update open buffers: rename any buffer that pointed to the old path
    for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_loaded(bufnr) then
            local name = vim.api.nvim_buf_get_name(bufnr)
            if name == old_path then
                local modified = vim.bo[bufnr].modified
                pcall(vim.api.nvim_buf_set_name, bufnr, new_path)
                vim.bo[bufnr].modified = modified
            end
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
    end

    return updated
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

-- Buffer-level watcher: detect when a note's contents were saved and the user
-- changed a wikilink to point to an existing note. In that case, offer to
-- rename the current file to match the linked note and reuse the existing
-- `handle_rename` logic to patch links across the vault.
function Watcher:on_buf_write(bufnr)
    bufnr = bufnr or vim.api.nvim_get_current_buf()
    local name = vim.api.nvim_buf_get_name(bufnr)
    if name == "" then
        return
    end

    local root = config.options.root
    if type(root) ~= "string" or root == "" then
        return
    end

    -- Only operate on files inside the vault
    local abs_name = vim.fn.fnamemodify(name, ":p")
    local abs_root = vim.fn.fnamemodify(root, ":p")
    if abs_name:sub(1, #abs_root) ~= abs_root then
        return
    end

    -- Read buffer content
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local content = table.concat(lines, "\n")

    -- Search wikilinks and try to find the first link that resolves to an
    -- existing note file distinct from the current file.
    local ext = config.options.ext or ".md"
    for link in content:gmatch("%[%[([^%]]+)%]%]") do
        local target = link:match("([^#|]+)")
        if target then
            target = vim.trim(target)
            if target ~= "" then
                local candidate = target
                if not candidate:match(vim.pesc(ext) .. "$") then
                    -- ensure extension starts with a dot
                    if ext:sub(1, 1) ~= "." then
                        candidate = candidate .. "." .. ext
                    else
                        candidate = candidate .. ext
                    end
                end
                local candidate_path = vim.fn.fnamemodify(abs_root .. "/" .. candidate, ":p")
                if vim.fn.filereadable(candidate_path) == 1 and candidate_path ~= abs_name then
                    -- Found an existing note that the user linked to. Prompt before renaming.
                    local prompt = string.format(
                        "[vault] Rename current note '%s' → '%s'?",
                        vim.fn.fnamemodify(abs_name, ":t"),
                        vim.fn.fnamemodify(candidate_path, ":t")
                    )
                    local ok = vim.fn.confirm(prompt, "&Yes\n&No", 2)
                    if ok == 1 then
                        -- Attempt filesystem rename. If it fails, abort.
                        local ok_mv, mv_err = pcall(function()
                            assert(uv.fs_rename(abs_name, candidate_path))
                        end)
                        if not ok_mv then
                            vim.schedule(function()
                                vim.notify(
                                    "[vault] rename failed: " .. tostring(mv_err),
                                    vim.log.levels.ERROR
                                )
                            end)
                            return
                        end

                        -- Reuse existing handler to patch links and update buffers/state
                        pcall(function()
                            self:handle_rename(abs_name, candidate_path)
                        end)
                    end

                    -- Stop after the first actionable link to avoid multiple prompts
                    return
                end
            end
        end
    end
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
