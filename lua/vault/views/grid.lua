-- lua/vault/bases/views/grid.lua
-- Grid-backed vault process buffer: thin adapter over vimtable.views.grid.Grid.
--
-- Drop-in sibling to editor.lua. Uses the Grid view for all rendering, conceal,
-- header, cursor, diff signs, and inline validation. Vault-specific logic
-- (frontmatter, rename, move, delete, create, undo, merge, safety checks) lives
-- here as callbacks and keymaps.
--
-- Usage: same as editor.lua — M.open({ notes = ..., base = ..., ... })

local M = {}

local log = require("vault.log").scope("bases.views.grid")
local utils = require("vault.utils")
local shared = require("vault.views.shared")
local state = require("vault.core.state")
local grid_config = require("vault.views.grid_config")

-- ─── Lazy imports (avoid circular requires at module level) ───────────────────

local function get_Grid()
    return require("vimtable.views.grid").Grid
end

-- ─── Constants (delegated to shared) ──────────────────────────────────────────

local READONLY_FILE_COLS = shared.READONLY_FILE_COLS
local uv = vim.uv or vim.loop
local DEFAULT_COLUMNS = { "slug", "title", "status", "tags" }
local SAVE_PROFILE_KEY = "vault.process_save_profile.current"
local pack = table.pack or function(...)
    return { n = select("#", ...), ... }
end
local unpack_values = table.unpack or unpack

local get_empty_cell = shared.get_empty_cell
local get_mtime = shared.get_mtime
local build_records
local build_structural_rename_specs
local fmt_value
local parse_value

---@type table<string, { format: fun(value: any): string, parse: fun(text: string): any }>
local GRID_COLUMN_ADAPTER_CACHE = {}

---@param col string
---@return string
local function grid_column_adapter_key(col)
    -- Formatter/parser behavior currently depends only on column semantics.
    -- Keep cache key as structured payload so adapter-relevant config can widen later.
    return vim.inspect({ col = col })
end

---@param col string
---@return { format: fun(value: any): string, parse: fun(text: string): any }
local function get_grid_column_adapters(col)
    local key = grid_column_adapter_key(col)
    local cached = GRID_COLUMN_ADAPTER_CACHE[key]
    if cached then
        return cached
    end

    local adapters = {
        format = function(value)
            return fmt_value(value, col)
        end,
        parse = function(text)
            return parse_value(text, col)
        end,
    }
    GRID_COLUMN_ADAPTER_CACHE[key] = adapters
    return adapters
end

---@class vault.ProcessStructuralOp
---@field old_slug vault.slug
---@field new_slug vault.slug
---@field source_field string

---@class vault.ProcessMutationDetail
---@field kind "update"|"delete"|"create"|"rename"
---@field slug? vault.slug
---@field new_slug? vault.slug
---@field path? vault.path
---@field new_path? vault.path

---@class vault.ProcessUndoSnapshot
---@field files table<string, string|string[]>
---@field created_paths vault.path[]
---@field deleted_paths table<vault.slug, vault.path>
---@field renames { old_path: vault.path, new_path: vault.path }[]
---@field timestamp integer
---@field description string
---@field mutation_details? vault.ProcessMutationDetail[]

---@class vault.ProcessStructuralContext
---@field watcher_paths table<vault.slug, { path: vault.path }>
---@field watcher_wikilinks table<string, vault.Wikilink>
---@field rename_specs vault.Watcher.RenameSpec[]
---@field candidate_source_paths table<vault.path, true>
---@field source_originals table<vault.path, string>

local SAVE_DEPTH_KEY = "vault.process_save_depth"

---@param detail vault.ProcessMutationDetail
---@return string
local function format_mutation_detail(detail)
    if detail.kind == "rename" then
        return string.format("renamed %s -> %s", detail.slug or "?", detail.new_slug or "?")
    elseif detail.kind == "update" then
        return string.format("updated %s", detail.slug or detail.path or "?")
    elseif detail.kind == "delete" then
        return string.format("trashed %s", detail.slug or detail.path or "?")
    elseif detail.kind == "create" then
        return string.format("created %s", detail.slug or detail.path or "?")
    end
    return detail.kind
end

---@param details vault.ProcessMutationDetail[]
---@param max_items? integer
---@return string
local function format_mutation_details(details, max_items)
    if #details == 0 then
        return ""
    end
    local limit = max_items or 6
    local parts = {}
    for i = 1, math.min(limit, #details) do
        parts[#parts + 1] = format_mutation_detail(details[i])
    end
    if #details > limit then
        parts[#parts + 1] = string.format("... and %d more", #details - limit)
    end
    return table.concat(parts, "; ")
end

local function enter_process_save()
    local depth = tonumber(state.get_global_key(SAVE_DEPTH_KEY) or 0) or 0
    state.set_global_key(SAVE_DEPTH_KEY, depth + 1)
end

local function leave_process_save()
    local depth = tonumber(state.get_global_key(SAVE_DEPTH_KEY) or 0) or 0
    if depth <= 1 then
        state.set_global_key(SAVE_DEPTH_KEY, nil)
        return
    end
    state.set_global_key(SAVE_DEPTH_KEY, depth - 1)
end

---@return vault.ProcessSaveProfile
local function new_save_profile()
    return {
        started_ns = uv.hrtime(),
        phases = {},
        phase_counts = {},
    }
end

---@param profile? vault.ProcessSaveProfile
---@param phase string
---@param elapsed_ms number
local function record_save_phase(profile, phase, elapsed_ms)
    if type(profile) ~= "table" then
        return
    end
    profile.phases[phase] = (profile.phases[phase] or 0) + elapsed_ms
    profile.phase_counts[phase] = (profile.phase_counts[phase] or 0) + 1
end

---@param profile? vault.ProcessSaveProfile
---@param phase string
---@param fn fun(): ...
---@return ...
local function measure_save_phase(profile, phase, fn)
    local t0 = uv.hrtime()
    local ok, packed = pcall(function()
        return pack(fn())
    end)
    record_save_phase(profile, phase, (uv.hrtime() - t0) / 1e6)
    if not ok then
        error(packed)
    end
    return unpack_values(packed, 1, packed.n)
end

---@param st vault.GridEditorState
---@param profile vault.ProcessSaveProfile
local function activate_save_profile(st, profile)
    st.last_save_profile = nil
    state.set_global_key(SAVE_PROFILE_KEY, profile)
end

---@param st vault.GridEditorState
---@param profile? vault.ProcessSaveProfile
---@param err? string
local function finish_save_profile(st, profile, err)
    if type(profile) ~= "table" then
        return
    end
    profile.total_ms = (uv.hrtime() - profile.started_ns) / 1e6
    profile.completed = err == nil
    profile.error = err
    st.last_save_profile = profile
    if state.get_global_key(SAVE_PROFILE_KEY) == profile then
        state.set_global_key(SAVE_PROFILE_KEY, nil)
    end
end

-- ─── Row highlight defaults ───────────────────────────────────────────────────

--- Define default highlight groups for row coloring (linked, user can override).
local function ensure_row_hl_groups()
    ---@type table<string, table>
    local defaults = {
        VaultRowDone = { link = "Comment" },
        VaultRowUntagged = { link = "DiagnosticVirtualTextInfo" },
    }
    for name, def in pairs(defaults) do
        vim.api.nvim_set_hl(
            0,
            name,
            vim.tbl_extend("keep", vim.api.nvim_get_hl(0, { name = name }), def)
        )
    end
end

--- @class vault.RowHlRule
--- @field match table<string, any>  Field conditions: { status = "done" } or { tags = {} }
--- @field hl string                 Highlight group name

--- Build a row_hl callback from config rules or a user function.
--- @return fun(record: table, row_idx: integer): string|nil
local function build_row_hl()
    local cfg = grid_config.get()
    local rules = cfg.row_hl
    if not rules then
        return function()
            return nil
        end
    end

    -- User provided a raw function — use directly
    if type(rules) == "function" then
        ---@diagnostic disable-next-line: return-type-mismatch
        return rules
    end

    -- Rule-based matching: first match wins
    --- @param record table
    --- @param _ integer
    --- @return string|nil
    return function(record, _)
        for _, rule in ipairs(rules) do
            local matched = true
            for field, expected in pairs(rule.match) do
                local val = record[field]
                if type(expected) == "table" and next(expected) == nil then
                    -- Empty table means "field is nil or empty list"
                    if val ~= nil and val ~= "" then
                        if type(val) == "table" then
                            if #val > 0 then
                                matched = false
                                break
                            end
                        else
                            matched = false
                            break
                        end
                    end
                elseif val ~= expected then
                    matched = false
                    break
                end
            end
            if matched then
                return rule.hl
            end
        end
        return nil
    end
end

-- ─── Per-buffer state ─────────────────────────────────────────────────────────

---@class vault.GridEditorState
---@field grid table  Grid instance (vimtable.Grid)
---@field note_paths table<vault.slug, vault.path>  slug → absolute path
---@field note_mtimes table<vault.slug, integer>  slug → mtime at snapshot time
---@field base? vault.Base
---@field filter_desc string
---@field session_key string
---@field columns string[]  ALL internal column names (always includes "slug")
---@field visible_columns string[]
---@field display_names table<string, string>
---@field formula_cols string[]
---@field readonly_columns table<string, boolean>
---@field slug_hidden boolean
---@field saving boolean|string
---@field save_mode? string
---@field taxonomy_field? string
---@field taxonomy_choices? string[]
---@field taxonomy_choices_provider? fun(): string[]
---@field taxonomy_apply_choice? fun(paths: vault.path[], choice: string): integer
---@field taxonomy_create_choice? fun(query: string): string|nil
---@field reload_notes? fun(): vault.Notes
---@field retain_note? fun(note: vault.Note): boolean
---@field statusline_builder? fun(count: integer): string
---@field banner_builder? fun(count: integer): string|string[]
---@field last_save_profile? vault.ProcessSaveProfile

---@class vault.ProcessSaveProfile
---@field started_ns integer
---@field total_ms? number
---@field phases table<string, number>
---@field phase_counts table<string, integer>
---@field completed? boolean
---@field error? string

local buf_states = {} --- @type table<integer, vault.GridEditorState>
local ok_vt_undo, vt_undo = pcall(require, "vimtable.undo")
if not ok_vt_undo then
    local snapshots = {}
    vt_undo = {
        snapshot = function(bufnr, payload)
            snapshots[bufnr] = payload
        end,
        restore = function(bufnr)
            local payload = snapshots[bufnr]
            snapshots[bufnr] = nil
            return payload
        end,
        has = function(bufnr)
            return snapshots[bufnr] ~= nil
        end,
        clear = function(bufnr)
            snapshots[bufnr] = nil
        end,
    }
end
local apply_taxonomy_choice_range
local preview_taxonomy_range
local apply_taxonomy_range
local banner_ns = vim.api.nvim_create_namespace("vault_grid_banner")

local STRUCTURAL_FIELDS = {
    slug = true,
    ["file.slug"] = true,
    ["file.name"] = true,
    ["file.folder"] = true,
    dir = true,
}

---@param dir string
---@return string
local function normalize_dir_prefix(dir)
    local value = vim.trim(dir or "")
    if value == "" or value == "/" or value == "." then
        return ""
    end
    value = value:gsub("^/*", ""):gsub("/*$", "")
    if value == "" then
        return ""
    end
    return value .. "/"
end

---@param slug vault.slug
---@return string, string
local function split_slug(slug)
    local dir_prefix = slug:match("^(.-/)[^/]*$") or ""
    local stem = slug:match("[^/]+$") or slug
    return dir_prefix, stem
end

---@param slug vault.slug
---@param dir_prefix string
---@return vault.slug
local function with_slug_dir(slug, dir_prefix)
    local _, stem = split_slug(slug)
    return dir_prefix .. stem
end

---@param path vault.path
---@return string
local function note_extension(path)
    local ext = vim.fn.fnamemodify(path, ":e")
    if type(ext) == "string" and ext ~= "" then
        return "." .. ext
    end
    local config = require("vault.config")
    return config.options.ext or ".md"
end

---@param source_path vault.path
---@param slug vault.slug
---@return vault.path
local function build_target_path_for_slug(source_path, slug)
    local config = require("vault.config")
    local root = vim.fn.expand(config.options.root or "")
    return vim.fs.normalize(root .. "/" .. slug .. note_extension(source_path))
end

local function invalidate_note_cache()
    local ok, scanner = pcall(require, "vault.scanner")
    if ok and type(scanner.invalidate_notes_cache) == "function" then
        scanner.invalidate_notes_cache()
        return
    end
    pcall(function()
        state.set_global_key("cache.notes.paths", nil)
        state.set_global_key("cache.notes.slugs", nil)
        state.set_global_key("cache.notes.basename_index", nil)
        state.set_global_key("cache.notes.paths_and_wikilinks_cached", nil)
        state.set_global_key("cache.telescope._extensions.vault.pickers", nil)
    end)
end

---@param st vault.GridEditorState
---@param slug vault.slug
---@param path vault.path
---@return boolean
local function is_stale_note(st, slug, path)
    local snap_mtime = st.note_mtimes and st.note_mtimes[slug] or 0
    return snap_mtime > 0 and get_mtime(path) > snap_mtime
end

---@param readonly_columns table<string, boolean>
---@return string[]
local function sorted_true_keys(readonly_columns)
    local keys = {}
    for key, enabled in pairs(readonly_columns) do
        if enabled then
            keys[#keys + 1] = key
        end
    end
    table.sort(keys)
    return keys
end

---@param spec table
---@return string
local function build_session_key(spec)
    return vim.json.encode(spec)
end

---@param diff table
---@return table<vault.slug, vault.ProcessStructuralOp>
local function collect_structural_ops(diff)
    ---@type table<vault.slug, vault.ProcessStructuralOp>
    local by_slug = {}

    for _, custom in ipairs(diff.custom or {}) do
        if
            custom.type == "rename"
            and custom.extra
            and custom.extra.old_slug
            and custom.extra.new_slug
        then
            by_slug[custom.extra.old_slug] = {
                old_slug = custom.extra.old_slug,
                new_slug = custom.extra.new_slug,
                source_field = custom.extra.source_field or "slug",
            }
        end
    end

    for _, upd in ipairs(diff.updates or {}) do
        local folder = upd.fields.dir
        if folder == nil then
            folder = upd.fields["file.folder"]
        end
        if folder ~= nil then
            local op = by_slug[upd.id]
            if not op or (op.source_field ~= "slug" and op.source_field ~= "file.slug") then
                local next_slug =
                    with_slug_dir(op and op.new_slug or upd.id, normalize_dir_prefix(folder))
                if next_slug ~= upd.id then
                    if op then
                        op.new_slug = next_slug
                    else
                        by_slug[upd.id] = {
                            old_slug = upd.id,
                            new_slug = next_slug,
                            source_field = "file.folder",
                        }
                    end
                end
            end
        end
    end

    return by_slug
end

---@param diff table
local function strip_structural_fields(diff)
    ---@type table[]
    local filtered = {}
    for _, upd in ipairs(diff.updates or {}) do
        ---@type table<string, any>
        local kept = {}
        for key, value in pairs(upd.fields or {}) do
            if not STRUCTURAL_FIELDS[key] then
                kept[key] = value
            end
        end
        if next(kept) then
            filtered[#filtered + 1] = { id = upd.id, fields = kept }
        end
    end
    diff.updates = filtered
end

---@param files table<string, string|string[]>
---@param old_path vault.path
---@param old_slug vault.slug
local function snapshot_structural_side_effects(files, old_path, old_slug)
    if old_path and vim.fn.filereadable(old_path) == 1 then
        local f = io.open(old_path, "r")
        if f then
            files[old_path] = f:read("*all")
            f:close()
        end
    end

    local scanner = require("vault.scanner")
    local paths = scanner.paths()
    local old_stem = old_path and vim.fn.fnamemodify(old_path, ":t:r") or nil
    local esc_slug = vim.pesc(old_slug)
    local esc_stem = (old_stem and old_stem ~= "") and vim.pesc(old_stem) or nil
    for _, entry in pairs(paths) do
        local path = entry.path
        if not files[path] and vim.fn.filereadable(path) == 1 then
            local f = io.open(path, "r")
            if f then
                local content = f:read("*all")
                f:close()
                local has_link = content:match("%[%[" .. esc_slug)
                if not has_link and esc_stem then
                    has_link = content:match("%[%[" .. esc_stem)
                end
                if has_link then
                    files[path] = content
                end
            end
        end
    end
end

---@param path vault.path|nil
---@return string|nil
local function read_file_blob(path)
    if not path or vim.fn.filereadable(path) ~= 1 then
        return nil
    end

    local f = io.open(path, "r")
    if not f then
        return nil
    end

    local content = f:read("*all")
    f:close()
    return content
end

---@param st vault.GridEditorState
---@param structural_ops vault.ProcessStructuralOp[]
---@return vault.ProcessStructuralContext|nil
local function build_structural_context(st, structural_ops)
    if #structural_ops == 0 then
        return nil
    end

    ---@type table<vault.slug, { path: vault.path }>
    local watcher_paths = {}
    for slug, path in pairs(st.note_paths or {}) do
        watcher_paths[slug] = { path = path }
    end

    local watcher_wikilinks = require("vault.scanner").wikilinks_no_suggest()
    local Watcher = require("vault.watcher")
    local rename_specs = build_structural_rename_specs(st, structural_ops)
    local candidate_source_paths = Watcher.collect_candidate_paths(
        watcher_paths,
        rename_specs,
        watcher_wikilinks,
        false
    ) or {}

    return {
        watcher_paths = watcher_paths,
        watcher_wikilinks = watcher_wikilinks,
        rename_specs = rename_specs,
        candidate_source_paths = candidate_source_paths,
        source_originals = {},
    }
end

---@param files table<string, string|string[]>
---@param path vault.path|nil
---@return nil
local function snapshot_file_blob(files, path)
    if path and not files[path] then
        local content = read_file_blob(path)
        if content then
            files[path] = content
        end
    end
end

---@param st vault.GridEditorState
---@param structural_ops vault.ProcessStructuralOp[]
---@return vault.Watcher.RenameSpec[]
build_structural_rename_specs = function(st, structural_ops)
    ---@type vault.Watcher.RenameSpec[]
    local renames = {}
    for _, op in ipairs(structural_ops or {}) do
        local old_path = st.note_paths[op.old_slug]
        if old_path then
            renames[#renames + 1] = {
                old_path = old_path,
                new_path = build_target_path_for_slug(old_path, op.new_slug),
                old_slug = op.old_slug,
                new_slug = op.new_slug,
            }
        end
    end

    return renames
end

---@param files table<string, string|string[]>
---@param st vault.GridEditorState
---@param structural_ops vault.ProcessStructuralOp[]
---@param structural_ctx vault.ProcessStructuralContext|nil
---@return nil
local function snapshot_structural_candidates(files, st, structural_ops, structural_ctx)
    if #structural_ops == 0 then
        return
    end

    local renames = structural_ctx and structural_ctx.rename_specs
        or build_structural_rename_specs(st, structural_ops)
    if #renames == 0 then
        return
    end

    if structural_ctx and structural_ctx.candidate_source_paths then
        for path, _ in pairs(structural_ctx.candidate_source_paths) do
            if not files[path] then
                local content = read_file_blob(path)
                if content then
                    files[path] = content
                    structural_ctx.source_originals[path] = content
                end
            end
        end
        for _, rename in ipairs(renames) do
            snapshot_file_blob(files, rename.old_path)
        end
        return
    end

    for _, op in ipairs(structural_ops) do
        snapshot_structural_side_effects(files, st.note_paths[op.old_slug], op.old_slug)
    end
end

---@param bufnr integer
---@param st vault.GridEditorState
---@param count integer
local function update_statusline(bufnr, st, count)
    if type(st.statusline_builder) ~= "function" then
        return
    end
    local ok, line = pcall(st.statusline_builder, count)
    if not ok or type(line) ~= "string" or line == "" then
        return
    end
    pcall(function()
        local win = vim.fn.bufwinid(bufnr)
        if win ~= -1 then
            vim.wo[win].statusline = line
        end
    end)
end

---@param bufnr integer
---@param st vault.GridEditorState
---@param count integer
local function update_banner(bufnr, st, count)
    if type(st.banner_builder) ~= "function" then
        return
    end
    local ok, value = pcall(st.banner_builder, count)
    if not ok or value == nil then
        return
    end
    ---@type string[]
    local lines = type(value) == "table" and value or { value }
    ---@type { [1]: string, [2]: string }[][]
    local virt_lines = {}
    for _, line in ipairs(lines) do
        if type(line) == "string" and line ~= "" then
            table.insert(virt_lines, { { line, "Comment" } })
        end
    end
    vim.api.nvim_buf_clear_namespace(bufnr, banner_ns, 0, -1)
    if #virt_lines == 0 then
        return
    end
    vim.api.nvim_buf_set_extmark(bufnr, banner_ns, 0, 0, {
        virt_lines = virt_lines,
        virt_lines_above = true,
    })
end

local function prepare_current_window_for_attach()
    local cur = vim.api.nvim_get_current_buf()
    if not vim.api.nvim_buf_is_valid(cur) then
        return
    end
    local name = vim.api.nvim_buf_get_name(cur)
    local buftype = vim.bo[cur].buftype
    if buftype == "nofile" or name:match("^vault://") then
        vim.bo[cur].modified = false
    end
end

---@param st vault.GridEditorState
---@param notes_map table<string, vault.Note>
---@return table<string, vault.Note>
local function apply_base_filter(st, notes_map)
    if not st.base or not st.base.has_filters or not st.base:has_filters() then
        return notes_map
    end
    return st.base:match_notes(notes_map)
end

---@param st vault.GridEditorState
---@param note vault.Note
---@return boolean
local function should_keep_note(st, note)
    if type(st.retain_note) == "function" then
        local ok, keep = pcall(st.retain_note, note)
        if ok then
            return keep == true
        end
        log.warn("Retain-note predicate failed for %s; keeping row", note.data.slug or "?")
    end

    if st.base and st.base.has_filters and st.base:has_filters() then
        local matched = st.base:match_notes({ [note.data.slug] = note })
        return matched[note.data.slug] ~= nil
    end

    return true
end

---@param st vault.GridEditorState
---@return table<string, vault.Note>
local function collect_current_notes_map(st)
    local Note = require("vault.notes.note")
    local Scanner = require("vault.scanner")
    local raw_paths = Scanner.paths()
    local notes_map = {}
    local dead_slugs = {}

    for slug, path in pairs(st.note_paths) do
        if vim.fn.filereadable(path) == 1 then
            local current_slug = utils.path_to_slug(path)
            local note_input = raw_paths[current_slug] or path
            local ok, note = pcall(Note, note_input)
            if ok and note and should_keep_note(st, note) then
                notes_map[note.data.slug] = note
            end
        else
            table.insert(dead_slugs, slug)
        end
    end

    for _, slug in ipairs(dead_slugs) do
        st.note_paths[slug] = nil
        if st.note_mtimes then
            st.note_mtimes[slug] = nil
        end
    end

    return apply_base_filter(st, notes_map)
end

---@param st vault.GridEditorState
---@return table<string, vault.Note>
local function collect_full_notes_map(st)
    if type(st.reload_notes) ~= "function" then
        return collect_current_notes_map(st)
    end

    local ok, refreshed = pcall(st.reload_notes)
    if ok and refreshed and refreshed.map then
        return apply_base_filter(st, refreshed.map)
    end

    log.warn("Reload filter refresh failed; keeping current note set")
    return collect_current_notes_map(st)
end

---@param bufnr integer
---@param st vault.GridEditorState
---@param notes_map table<string, vault.Note>
local function reload_grid_from_notes(bufnr, st, notes_map)
    local records = build_records(notes_map, st.columns, st.base)
    st.note_paths = {}
    st.note_mtimes = {}
    for _, rec in ipairs(records) do
        st.note_paths[rec.slug] = rec._path
        st.note_mtimes[rec.slug] = get_mtime(rec._path)
    end

    st.grid:reload(records)
    update_statusline(bufnr, st, #records)
    update_banner(bufnr, st, #records)
end

-- ─── Shared helpers (delegated to shared.lua) ─────────────────────────────────

local normalize_col = shared.normalize_col
local base_key_to_col = shared.base_key_to_col

---@param base vault.Base
---@return string[], table<string,string>, string[], string[]
local function columns_from_base(base)
    ---@type string[]
    local columns = {}
    ---@type table<string, string>
    local display_names = {}
    ---@type string[]
    local formula_cols = {}
    ---@type string[]|nil
    local order = nil
    if base.data.views and base.data.views[1] and base.data.views[1].order then
        order = base.data.views[1].order
    end
    if not order then
        order = (
            type(base.data.properties) == "table" and not vim.tbl_isempty(base.data.properties)
        )
                and vim.tbl_keys(base.data.properties)
            or {}
    end
    if #order == 0 then
        return DEFAULT_COLUMNS, {}, {}, DEFAULT_COLUMNS
    end
    local base_display = base:display_names()
    ---@type table<string, boolean>
    local seen = {}
    local has_slug = false
    for _, key in ipairs(order) do
        local col, is_formula = base_key_to_col(key)
        if col == "slug" then
            has_slug = true
        end
        if not seen[col] then
            seen[col] = true
            table.insert(columns, col)
            display_names[col] = base_display[key] or col
            if is_formula then
                table.insert(formula_cols, col)
            end
        end
    end
    local visible_columns = vim.list_slice(columns, 1)
    if not has_slug then
        table.insert(columns, 1, "slug")
    end
    return columns, display_names, formula_cols, visible_columns
end

---@param base vault.Base
---@return { col: string, dir: "asc"|"desc" }|nil
local function sort_from_base(base)
    if not base.data.views or not base.data.views[1] then
        return nil
    end
    local view = base.data.views[1]
    if not view.sort_by then
        return nil
    end
    local sort = view.sort_by
    local key = sort.key or sort[1]
    if not key then
        return nil
    end
    local col = base_key_to_col(key)
    local dir = sort.direction or sort.dir or "asc"
    return { col = col, dir = dir }
end

--- Extract group_by from base view definition.
--- @param base vault.Base
--- @return string|nil
local function group_by_from_base(base)
    if not base.data.views or not base.data.views[1] then
        return nil
    end
    local view = base.data.views[1]
    return view.group_by
end

local yaml_quote = shared.yaml_quote
local validate_path_in_vault = shared.validate_path_in_vault
local atomic_writefile = shared.atomic_writefile

-- ─── Frontmatter I/O (delegated to shared.lua) ───────────────────────────────

local read_frontmatter_fields = shared.read_frontmatter_fields
local set_frontmatter_fields = shared.set_frontmatter_fields

-- ─── Value formatting (delegated to shared.lua) ──────────────────────────────

fmt_value = shared.fmt_value
parse_value = shared.parse_value

-- ─── Record building ──────────────────────────────────────────────────────────

---@param notes_map table<vault.slug, vault.Note>
---@param columns string[]
---@param base? vault.Base
---@return table[]  flat record per note
build_records = function(notes_map, columns, base)
    ---@type table[]
    local records = {}
    local skipped = 0
    for slug, note in pairs(notes_map) do
        local ok, rec = pcall(function()
            local path = note.data and note.data.path or note.path
            if not path then
                return nil
            end
            local fm = note.data and note.data.frontmatter or nil
            if type(fm) ~= "table" then
                fm = read_frontmatter_fields(path, columns)
            end
            ---@type table<string, any>
            local fields = {}
            ---@type table<string, any>
            local formula_results = {}
            if base and base:has_formulas() then
                formula_results = base:evaluate_formulas(note)
            end
            for _, col in ipairs(columns) do
                if col == "slug" then
                    fields.slug = slug
                elseif col == "file.name" then
                    fields[col] = note.data and note.data.stem or (slug:match("[^/]+$") or slug)
                elseif col == "file.slug" then
                    fields[col] = slug
                elseif col == "file.folder" then
                    local relpath = note.data and note.data.relpath or ""
                    local dir = relpath:match("^(.-/)[^/]*$") or ""
                    fields[col] = dir ~= "" and dir or "/"
                elseif col == "file.path" then
                    fields[col] = note.data and note.data.relpath or ""
                elseif col == "file.ext" then
                    fields[col] = "md"
                elseif col == "file.ctime" then
                    local t = note.data and note.data.ctime
                    fields[col] = t and t > 0 and os.date("%Y-%m-%d %H:%M", t) or ""
                elseif col == "file.mtime" then
                    local t = note.data and note.data.mtime
                    fields[col] = t and t > 0 and os.date("%Y-%m-%d %H:%M", t) or ""
                elseif col == "file.size" then
                    fields[col] = path and vim.fn.getfsize(path) or 0
                elseif col == "file.body" then
                    local body = ""
                    local f = path and io.open(path, "r")
                    if f then
                        local chunk = f:read(4096) or ""
                        f:close()
                        local after_fm = chunk:match("^%-%-%-.-\n%-%-%-\n(.*)") or chunk
                        body = after_fm
                    end
                    fields[col] = body:gsub("\r?\n", " "):gsub("%s+", " "):match("^%s*(.-)%s*$")
                        or ""
                elseif col == "file.inlinks" then
                    local links = note.data and note.data.inlinks
                    if links then
                        local slugs = {}
                        for s in pairs(links) do
                            table.insert(slugs, s)
                        end
                        table.sort(slugs)
                        fields[col] = table.concat(slugs, ", ")
                    else
                        fields[col] = ""
                    end
                elseif col == "file.outlinks" then
                    local links = note.data and note.data.outlinks
                    if links then
                        local slugs = {}
                        for s in pairs(links) do
                            table.insert(slugs, s)
                        end
                        table.sort(slugs)
                        fields[col] = table.concat(slugs, ", ")
                    else
                        fields[col] = ""
                    end
                elseif col == "file.headings" then
                    local hdgs = note.data and note.data.headings
                    fields[col] = hdgs and #hdgs > 0 and (hdgs[1].text or hdgs[1][2] or "") or ""
                elseif col == "title" then
                    local basename = slug:match("[^/]+$") or slug
                    fields.title = fm.title
                        or (note.data and note.data.title)
                        or (note.data and note.data.stem)
                        or basename
                elseif col == "dir" then
                    local relpath = note.data and note.data.relpath or ""
                    local dir = relpath:match("^(.-/)[^/]*$") or ""
                    fields.dir = dir ~= "" and dir or "/"
                elseif col == "tags" then
                    fields.tags = fm.tags
                        or (note.data and note.data.frontmatter and note.data.frontmatter.tags)
                        or nil
                elseif col:match("^formula%.") then
                    local fname = col:match("^formula%.(.+)")
                    fields[col] = formula_results[fname]
                else
                    fields[col] = fm[col]
                end
            end
            -- Grid expects flat records: { slug = "x", title = "y", ... }
            -- Convert from editor.lua's nested { slug, path, fields } format
            ---@type table<string, any>
            local flat = {}
            for k, v in pairs(fields) do
                flat[k] = v
            end
            flat._path = path -- stash path for save handler
            return flat
        end)
        if ok and rec then
            table.insert(records, rec)
        else
            skipped = skipped + 1
        end
    end
    if skipped > 0 then
        log.warn("%d notes skipped due to parse errors", skipped)
    end
    table.sort(records, function(a, b)
        return (a.slug or "") < (b.slug or "")
    end)
    return records
end

-- ─── Build grid.Column[] from vault column spec ──────────────────────────────

---@class vault.GridColumn
---@field name string
---@field header string
---@field readonly boolean
---@field format fun(value: any): string
---@field parse fun(text: string): any

---@param visible_columns string[]
---@param display_names table<string, string>
---@param formula_cols string[]
---@param extra_readonly? table<string, boolean>
---@return vault.GridColumn[]
local function build_grid_columns(visible_columns, display_names, formula_cols, extra_readonly)
    local formula_set = {}
    for _, fc in ipairs(formula_cols) do
        formula_set[fc] = true
    end
    extra_readonly = extra_readonly or {}

    --- @type vault.GridColumn[]
    local grid_cols = {}
    for _, col in ipairs(visible_columns) do
        local is_readonly = formula_set[col]
            or READONLY_FILE_COLS[col]
            or extra_readonly[col]
            or false
        local adapters = get_grid_column_adapters(col)
        --- @type vault.GridColumn
        local gc = {
            name = col,
            header = display_names[col] or col,
            readonly = is_readonly,
            format = adapters.format,
            parse = adapters.parse,
        }
        table.insert(grid_cols, gc)
    end
    return grid_cols
end

-- ─── Classify callback ────────────────────────────────────────────────────────
-- Maps vault column semantics into the Grid's diff classify system.

---@param st vault.GridEditorState
---@return fun(id: string, field: string, old: string, new: string): string, table|nil
local function make_classify(_)
    return function(id, field, _, new)
        -- slug or file.slug edit → rename
        if field == "slug" or field == "file.slug" then
            local new_slug = vim.trim(new)
            if new_slug ~= "" and new_slug ~= id then
                return "rename", { old_slug = id, new_slug = new_slug, source_field = field }
            end
            return "skip"
        end
        -- file.name edit → rename (change filename stem)
        if field == "file.name" then
            local new_stem = vim.trim(new)
            local old_stem = (id:match("[^/]+$") or id)
            if new_stem ~= "" and new_stem ~= old_stem then
                local dir_prefix = id:match("^(.-/)[^/]*$") or ""
                return "rename",
                    { old_slug = id, new_slug = dir_prefix .. new_stem, source_field = field }
            end
            return "skip"
        end
        -- file.folder edit → move (change directory)
        if field == "file.folder" then
            return "update", nil -- treat as normal update; apply_mutations handles dir moves
        end
        return "update", nil
    end
end

-- ─── Undo snapshot ────────────────────────────────────────────────────────────

---@param diff table  vimtable.Diff
---@param st vault.GridEditorState
---@param bufnr integer
---@param structural_ops? vault.ProcessStructuralOp[]
---@param structural_ctx? vault.ProcessStructuralContext
local function snapshot_for_undo(diff, st, bufnr, structural_ops, structural_ctx)
    ---@type table<string, string|string[]>
    local files = {}
    for _, upd in ipairs(diff.updates) do
        snapshot_file_blob(files, st.note_paths[upd.id])
    end
    --- @type table<string, string>  slug → path
    local deleted_paths = {}
    for _, slug in ipairs(diff.deletes) do
        local path = st.note_paths[slug]
        if path and not files[path] then
            local content = read_file_blob(path)
            if content then
                files[path] = content
            end
        end
        if path and files[path] then
            deleted_paths[slug] = path
        end
    end
    snapshot_structural_candidates(files, st, structural_ops or {}, structural_ctx)
    ---@type vault.ProcessUndoSnapshot
    local payload = {
        files = files,
        created_paths = {},
        deleted_paths = deleted_paths,
        renames = {},
        timestamp = os.time(),
        description = string.format(
            "%d updates, %d deletes, %d creates, %d renames",
            #diff.updates,
            #diff.deletes,
            #diff.creates,
            diff.custom and #diff.custom or 0
        ),
        mutation_details = {},
    }
    vt_undo.snapshot(bufnr, payload)
    return payload
end

-- ─── Mutation engine ──────────────────────────────────────────────────────────

---@param diff table
---@param st vault.GridEditorState
---@param undo_payload? vault.ProcessUndoSnapshot  Live undo payload to append created_paths/renames
---@param mutation_details? vault.ProcessMutationDetail[]
---@return integer, integer, integer
local function apply_mutations(diff, st, undo_payload, mutation_details)
    local n_updates, n_deletes, n_creates = 0, 0, 0
    ---@type string
    local empty = get_empty_cell()

    -- Updates
    for _, upd in ipairs(diff.updates) do
        local path = st.note_paths[upd.id]
        if not path then
            goto continue
        end
        local safe_path, path_err = validate_path_in_vault(path)
        if not safe_path then
            log.error("SAFETY: Skipping update — %s", path_err)
            goto continue
        end
        path = safe_path
        if is_stale_note(st, upd.id, path) then
            log.warn("SAFETY: Skipping %s — file modified externally", upd.id)
            goto continue
        end
        -- file.body write
        if upd.fields["file.body"] ~= nil then
            local new_body = upd.fields["file.body"] or ""
            local ok_read, file_lines = pcall(vim.fn.readfile, path)
            if ok_read and file_lines then
                local fm_end = 0
                if file_lines[1] and file_lines[1]:match("^%-%-%-") then
                    for i = 2, #file_lines do
                        if file_lines[i]:match("^%-%-%-") then
                            fm_end = i
                            break
                        end
                    end
                end
                local new_lines = {}
                for i = 1, fm_end do
                    table.insert(new_lines, file_lines[i])
                end
                table.insert(new_lines, new_body)
                table.insert(new_lines, "")
                atomic_writefile(path, new_lines)
            end
        end
        -- Other fields (batched frontmatter write)
        ---@type table<string, any>
        local fm_fields = {}
        for col, new_val in pairs(upd.fields) do
            if col ~= "dir" and col ~= "file.folder" and col ~= "file.body" then
                fm_fields[col] = new_val
            end
        end
        if next(fm_fields) then
            set_frontmatter_fields(path, fm_fields)
        end
        n_updates = n_updates + 1
        if mutation_details then
            mutation_details[#mutation_details + 1] =
                { kind = "update", slug = upd.id, path = path }
        end
        ::continue::
    end

    -- Deletes
    for _, slug in ipairs(diff.deletes) do
        local path = st.note_paths[slug]
        if path then
            local safe_del, del_err = validate_path_in_vault(path)
            if not safe_del then
                log.error("SAFETY: Skipping delete — %s", del_err)
                goto del_continue
            end
            if is_stale_note(st, slug, safe_del) then
                log.warn("SAFETY: Skipping delete for %s — file modified externally", slug)
                goto del_continue
            end
            local del_ok = pcall(function()
                local Note = require("vault.notes.note")
                local note = Note(safe_del)
                note:delete(false, false)
            end)
            if del_ok then
                n_deletes = n_deletes + 1
                if mutation_details then
                    mutation_details[#mutation_details + 1] =
                        { kind = "delete", slug = slug, path = safe_del }
                end
                st.note_paths[slug] = nil
                if st.note_mtimes then
                    st.note_mtimes[slug] = nil
                end
            else
                log.error("Delete failed for: %s", slug)
            end
        end
        ::del_continue::
    end

    -- Creates
    for _, create in ipairs(diff.creates) do
        local raw_slug = create.fields.slug
        local title = create.fields.title
        local source = raw_slug and raw_slug ~= "" and raw_slug ~= empty and raw_slug
            or title and title ~= "" and title ~= empty and title
            or nil
        if not source then
            goto cr_continue
        end
        local slug = source:lower():gsub("%s+", "-"):gsub("[%c%[%]#|^]", "")
        if slug == "" then
            slug = "untitled"
        end
        local config = require("vault.config")
        local dir = create.fields.dir or create.fields["file.folder"] or ""
        if type(dir) ~= "string" then
            dir = ""
        end
        if dir == "/" then
            dir = ""
        end
        if dir:match("%.%.") then
            log.error("SAFETY: Refusing create with '..': %s", dir)
            goto cr_continue
        end
        -- Ensure trailing / on non-empty dir
        if dir ~= "" and not dir:match("/$") then
            dir = dir .. "/"
        end
        local base_slug = slug
        local path = config.options.root .. "/" .. dir .. slug .. config.options.ext
        local counter = 1
        while vim.fn.filereadable(path) == 1 do
            slug = base_slug .. "-" .. counter
            path = config.options.root .. "/" .. dir .. slug .. config.options.ext
            counter = counter + 1
            if counter > 100 then
                log.error("Too many slug collisions for: %s", base_slug)
                goto cr_continue
            end
        end
        local safe_create, create_err = validate_path_in_vault(path)
        if not safe_create then
            log.error("SAFETY: Skipping create — %s", create_err)
            goto cr_continue
        end
        ---@type string[]
        local fm = { "---" }
        if create.fields.title then
            table.insert(fm, "title: " .. yaml_quote(create.fields.title))
        end
        ---@type table<string, boolean>
        local skip_fields =
            { slug = true, title = true, dir = true, tags = true, ["file.folder"] = true }
        for col, val in pairs(create.fields) do
            if not skip_fields[col] and val ~= nil then
                if type(val) == "table" then
                    table.insert(fm, col .. ":")
                    for _, v in ipairs(val) do
                        table.insert(fm, "  - " .. yaml_quote(tostring(v)))
                    end
                else
                    table.insert(fm, col .. ": " .. yaml_quote(tostring(val)))
                end
            end
        end
        if create.fields.tags and type(create.fields.tags) == "table" then
            table.insert(fm, "tags:")
            for _, t in ipairs(create.fields.tags) do
                table.insert(fm, "  - " .. yaml_quote(t))
            end
        end
        table.insert(fm, "---")
        table.insert(fm, "")
        local parent = vim.fn.fnamemodify(safe_create, ":h")
        if vim.fn.isdirectory(parent) == 0 then
            vim.fn.mkdir(parent, "p")
        end
        local write_ok = atomic_writefile(safe_create, fm)
        if write_ok then
            if undo_payload then
                table.insert(undo_payload.created_paths, safe_create)
            end
            -- Register created note so M.reload() can find it.
            -- The slug key is dir + deduped slug (the relative path stem).
            local created_slug = dir .. slug
            st.note_paths[created_slug] = safe_create
            n_creates = n_creates + 1
            if mutation_details then
                mutation_details[#mutation_details + 1] =
                    { kind = "create", slug = created_slug, path = safe_create }
            end
        end
        ::cr_continue::
    end

    return n_updates, n_deletes, n_creates
end

---@param structural_ops vault.ProcessStructuralOp[]
---@param diff table
---@param st vault.GridEditorState
---@param undo_payload? vault.ProcessUndoSnapshot
---@param mutation_details? vault.ProcessMutationDetail[]
---@param structural_ctx? vault.ProcessStructuralContext
---@return integer, integer
local function apply_structural_ops(
    structural_ops,
    diff,
    st,
    undo_payload,
    mutation_details,
    structural_ctx
)
    local n_renamed = 0
    local n_patched = 0
    if #structural_ops == 0 then
        return n_renamed, n_patched
    end

    local Note = require("vault.notes.note")
    local Watcher = require("vault.watcher")
    local watcher_paths = structural_ctx and structural_ctx.watcher_paths or nil
    local watcher_wikilinks = structural_ctx and structural_ctx.watcher_wikilinks or nil
    local source_originals = structural_ctx and structural_ctx.source_originals or nil
    if not watcher_paths then
        watcher_paths = {}
        for slug, path in pairs(st.note_paths or {}) do
            watcher_paths[slug] = { path = path }
        end
    end
    if not watcher_wikilinks then
        watcher_wikilinks = require("vault.scanner").wikilinks_no_suggest()
    end

    ---@type { old_path: vault.path, new_path: vault.path }[]
    local batch_renames = {}
    ---@type vault.Watcher.RenameSpec[]
    local batch_rename_specs = {}

    for _, ren in ipairs(structural_ops) do
        local old_path = st.note_paths[ren.old_slug]
        if old_path then
            local new_path = build_target_path_for_slug(old_path, ren.new_slug)
            if ren.new_slug:match("%.%.") then
                log.error("SAFETY: Refusing rename '%s' — '..'", ren.new_slug)
            else
                local safe_new_path, new_err = validate_path_in_vault(new_path)
                if not safe_new_path then
                    log.error("SAFETY: Refusing rename '%s' — %s", ren.new_slug, new_err)
                elseif is_stale_note(st, ren.old_slug, old_path) then
                    log.warn(
                        "SAFETY: Skipping structural move for %s — file modified externally",
                        ren.old_slug
                    )
                else
                    new_path = safe_new_path
                    if vim.fn.filereadable(new_path) == 1 and old_path ~= new_path then
                        local old_st = uv.fs_stat(old_path)
                        local new_st = uv.fs_stat(new_path)
                        if not (old_st and new_st and old_st.ino == new_st.ino) then
                            log.error("SAFETY: Cannot rename to '%s' — exists", ren.new_slug)
                            goto continue
                        end
                    end
                    local ok, note = pcall(Note, old_path)
                    if ok and note then
                        local move_ok, move_err = pcall(note.move, note, new_path, false, false, {
                            silent = true,
                            update_links = false,
                        })
                        if move_ok then
                            batch_renames[#batch_renames + 1] = {
                                old_path = old_path,
                                new_path = new_path,
                            }
                            batch_rename_specs[#batch_rename_specs + 1] = {
                                old_path = old_path,
                                new_path = new_path,
                                old_slug = ren.old_slug,
                                new_slug = ren.new_slug,
                            }
                            if
                                watcher_paths
                                and watcher_paths[ren.old_slug]
                                and not source_originals
                            then
                                watcher_paths[ren.old_slug].path = new_path
                            end
                            if undo_payload then
                                table.insert(
                                    undo_payload.renames,
                                    { old_path = old_path, new_path = new_path }
                                )
                            end
                            if mutation_details then
                                mutation_details[#mutation_details + 1] = {
                                    kind = "rename",
                                    slug = ren.old_slug,
                                    new_slug = ren.new_slug,
                                    path = old_path,
                                    new_path = new_path,
                                }
                            end
                            st.note_paths[ren.new_slug] = new_path
                            st.note_paths[ren.old_slug] = nil
                            if st.note_mtimes then
                                st.note_mtimes[ren.new_slug] = get_mtime(new_path)
                                st.note_mtimes[ren.old_slug] = nil
                            end
                            for _, upd in ipairs(diff.updates or {}) do
                                if upd.id == ren.old_slug then
                                    upd.id = ren.new_slug
                                end
                            end
                            n_renamed = n_renamed + 1
                        else
                            log.error("Rename '%s' failed: %s", ren.old_slug, tostring(move_err))
                        end
                    end
                end
            end
        end
        ::continue::
    end

    if #batch_renames > 0 then
        local watcher = Watcher()
        watcher:disable_oil_guard()
        local pending_updates = nil
        if source_originals then
            pending_updates = Watcher.prepare_rename_updates(
                watcher_paths,
                batch_rename_specs,
                watcher_wikilinks,
                {
                    use_new_paths = true,
                    original_contents = source_originals,
                }
            ).pending
        end
        n_patched = watcher:handle_renames(
            batch_renames,
            true,
            watcher_paths,
            watcher_wikilinks,
            pending_updates
        ) or 0
    end

    return n_renamed, n_patched
end

-- ─── Save handler (on_save callback for Grid) ────────────────────────────────

---@param st vault.GridEditorState
---@return fun(diff: table, done: fun(err: string|nil))
local function make_on_save(st)
    return function(diff, done)
        local bufnr = st.grid:bufnr()
        st.saving = true

        -- ── Validation warnings ──
        if #diff.errors > 0 then
            log.warn(
                "%d edit(s) ignored: %s",
                #diff.errors,
                diff.errors[1].reason .. " on " .. (diff.errors[1].field or "?")
            )
        end

        -- Extract structural ops from diff.custom and folder updates
        ---@type vault.ProcessStructuralOp[]
        local structural_ops = {}
        ---@type table[]
        local other_custom = {}
        local structural_by_slug = collect_structural_ops(diff)
        for _, op in pairs(structural_by_slug) do
            structural_ops[#structural_ops + 1] = op
        end
        for _, c in ipairs(diff.custom or {}) do
            if c.type ~= "rename" then
                table.insert(other_custom, c)
            end
        end
        diff.custom = other_custom
        strip_structural_fields(diff)

        local total = #diff.updates + #diff.deletes + #diff.creates + #structural_ops
        if total == 0 then
            st.saving = false
            done(nil)
            return
        end

        if st.save_mode == "metadata_only" then
            local blocked = {}
            if #structural_ops > 0 then
                table.insert(blocked, string.format("%d structural edit(s)", #structural_ops))
            end
            if #diff.creates > 0 then
                table.insert(blocked, string.format("%d create(s)", #diff.creates))
            end
            if #diff.deletes > 0 then
                table.insert(blocked, string.format("%d delete(s)", #diff.deletes))
            end
            if #blocked > 0 then
                log.warn(
                    "Metadata-only save ignored structural edits: %s",
                    table.concat(blocked, ", ")
                )
                structural_ops = {}
                diff.creates = {}
                diff.deletes = {}
            end
        end

        total = #diff.updates + #diff.deletes + #diff.creates + #structural_ops
        if total == 0 then
            st.saving = false
            done(nil)
            return
        end

        enter_process_save()
        local save_profile = new_save_profile()
        activate_save_profile(st, save_profile)
        local structural_ctx = nil

        -- ── Snapshot for undo ──
        local undo_payload = measure_save_phase(save_profile, "snapshot_for_undo", function()
            structural_ctx = build_structural_context(st, structural_ops)
            return snapshot_for_undo(diff, st, bufnr, structural_ops, structural_ctx)
        end)

        -- ── Hard cap on creates ──
        local grid_cfg = grid_config.get()
        if #diff.creates > grid_cfg.create_hard_cap then
            log.error(
                "SAFETY: Refusing %d creates (cap %d). Applying updates only.",
                #diff.creates,
                grid_cfg.create_hard_cap
            )
            diff.creates = {}
            diff.deletes = {}
        end

        if #diff.creates > 0 and #diff.deletes > 0 then
            log.warn(
                "SAFETY: Mixed create+delete diff detected (%d creates, %d deletes) — applying updates and structural moves only",
                #diff.creates,
                #diff.deletes
            )
            diff.creates = {}
            diff.deletes = {}
        end

        ---@type vault.ProcessMutationDetail[]
        local mutation_details = {}

        -- ── Process structural moves/renames ──
        local n_renamed, n_patched = measure_save_phase(
            save_profile,
            "apply_structural_ops",
            function()
                return apply_structural_ops(
                    structural_ops,
                    diff,
                    st,
                    undo_payload,
                    mutation_details,
                    structural_ctx
                )
            end
        )

        -- ── Handle deletes ──
        if #diff.deletes > 0 and #diff.deletes > grid_cfg.delete_hard_cap then
            log.error(
                "SAFETY: Refusing %d deletes (cap %d)",
                #diff.deletes,
                grid_cfg.delete_hard_cap
            )
            diff.deletes = {}
        end

        local function finish_save()
            local apply_fn = M._apply_mutations or apply_mutations
            local ok_apply, n_u, n_d, n_c =
                pcall(apply_fn, diff, st, undo_payload, mutation_details)
            if not ok_apply then
                leave_process_save()
                st.saving = false
                finish_save_profile(st, save_profile, tostring(n_u))
                done(tostring(n_u))
                return
            end
            ---@type string[]
            local parts = {}
            if n_renamed > 0 then
                local msg = string.format("%d renamed", n_renamed)
                if n_patched > 0 then
                    msg = msg .. string.format(" (%d patched)", n_patched)
                end
                table.insert(parts, msg)
            end
            if n_u > 0 then
                table.insert(parts, string.format("%d updated", n_u))
            end
            if n_d > 0 then
                table.insert(parts, string.format("%d trashed", n_d))
            end
            if n_c > 0 then
                table.insert(parts, string.format("%d created", n_c))
            end
            if #parts == 0 then
                parts = { "no changes" }
            end
            if undo_payload and undo_payload.mutation_details then
                for _, item in ipairs(mutation_details) do
                    undo_payload.mutation_details[#undo_payload.mutation_details + 1] = item
                end
            end
            local summary = table.concat(parts, ", ")
            local detail_text = format_mutation_details(mutation_details, 8)
            if detail_text ~= "" then
                log.info("Saved: %s — %s", summary, detail_text)
            else
                log.info("Saved: %s", summary)
            end
            invalidate_note_cache()
            leave_process_save()
            st.saving = false
            done(nil)
            -- Reload the grid to rebuild snapshot from current state.
            -- Without this, incremental saves compare against the stale
            -- snapshot and re-detect already-applied changes.
            local refresh_ok, refresh_err = pcall(function()
                measure_save_phase(save_profile, "post_save_refresh", function()
                    M.refresh_current(bufnr)
                end)
            end)
            finish_save_profile(st, save_profile, refresh_ok and nil or tostring(refresh_err))
            if not refresh_ok then
                error(refresh_err)
            end
        end

        if #diff.deletes > 0 then
            -- Confirmation for deletes
            local confirm_ui = require("vault.ui.confirm")
            ---@type string[]
            local preview = {}
            for i = 1, math.min(10, #diff.deletes) do
                table.insert(preview, "  - " .. diff.deletes[i])
            end
            if #diff.deletes > 10 then
                table.insert(preview, string.format("  ... and %d more", #diff.deletes - 10))
            end
            confirm_ui.select({
                message = string.format(
                    "Vault: About to TRASH %d note%s:\n%s\n\n%d updated, %d created.\n\nProceed?",
                    #diff.deletes,
                    #diff.deletes == 1 and "" or "s",
                    table.concat(preview, "\n"),
                    #diff.updates,
                    #diff.creates
                ),
                title = "Vault Process (grid)",
                choices = {
                    { key = "y", label = "Yes, trash them", action = finish_save },
                    {
                        key = "n",
                        label = "No, skip deletes",
                        action = function()
                            diff.deletes = {}
                            finish_save()
                        end,
                    },
                    {
                        key = "c",
                        label = "Cancel",
                        action = function()
                            leave_process_save()
                            st.saving = false
                            finish_save_profile(st, save_profile, "cancelled")
                            done(nil)
                        end,
                    },
                },
                on_cancel = function()
                    leave_process_save()
                    st.saving = false
                    finish_save_profile(st, save_profile, "cancelled")
                    done(nil)
                end,
            })
        else
            finish_save()
        end
    end
end

-- ─── Reload ───────────────────────────────────────────────────────────────────

---@param bufnr integer
function M.reload(bufnr)
    local st = buf_states[bufnr]
    if not st then
        return
    end
    shared.reset_empty_cell()
    get_empty_cell()

    reload_grid_from_notes(bufnr, st, collect_full_notes_map(st))
end

---@param bufnr integer
function M.refresh_current(bufnr)
    local st = buf_states[bufnr]
    if not st then
        return
    end
    shared.reset_empty_cell()
    get_empty_cell()
    reload_grid_from_notes(bufnr, st, collect_current_notes_map(st))
end

-- ─── Undo ─────────────────────────────────────────────────────────────────────

--- Apply an undo snapshot (internal — used by both M.undo and on_undo callback).
---
---@param bufnr integer
---@param snap vault.ProcessUndoSnapshot
function M._apply_undo(bufnr, snap)
    local restored, deleted, renames_reversed = 0, 0, 0
    ---@type string[]
    local detail_parts = {}
    local st = buf_states[bufnr]
    if snap.renames then
        for _, ren in ipairs(snap.renames) do
            if vim.fn.filereadable(ren.new_path) == 1 then
                local ok = uv.fs_rename(ren.new_path, ren.old_path)
                if ok then
                    renames_reversed = renames_reversed + 1
                    detail_parts[#detail_parts + 1] = string.format(
                        "reversed %s -> %s",
                        require("vault.utils").path_to_slug(ren.new_path),
                        require("vault.utils").path_to_slug(ren.old_path)
                    )
                    if st then
                        local old_slug = require("vault.utils").path_to_slug(ren.old_path)
                        local new_slug = require("vault.utils").path_to_slug(ren.new_path)
                        st.note_paths[new_slug] = nil
                        st.note_paths[old_slug] = ren.old_path
                        if st.note_mtimes then
                            st.note_mtimes[new_slug] = nil
                            st.note_mtimes[old_slug] = get_mtime(ren.old_path)
                        end
                    end
                else
                    log.error("Failed to reverse rename %s → %s", ren.new_path, ren.old_path)
                end
            end
        end
    end
    for path, original_content in pairs(snap.files) do
        local ok = false
        if type(original_content) == "string" then
            ok = pcall(utils.safe_write, path, original_content)
        elseif type(original_content) == "table" then
            ok = atomic_writefile(path, original_content)
        end
        if ok then
            restored = restored + 1
            detail_parts[#detail_parts + 1] =
                string.format("restored %s", require("vault.utils").path_to_slug(path))
        else
            log.error("Failed to restore %s", path)
        end
    end
    if snap.created_paths then
        for _, path in ipairs(snap.created_paths) do
            if vim.fn.filereadable(path) == 1 then
                vim.fn.delete(path)
                deleted = deleted + 1
                detail_parts[#detail_parts + 1] =
                    string.format("removed created %s", require("vault.utils").path_to_slug(path))
            end
        end
    end
    -- Re-register deleted note paths so M.reload can find them
    if st and snap.deleted_paths then
        for slug, path in pairs(snap.deleted_paths) do
            if vim.fn.filereadable(path) == 1 then
                st.note_paths[slug] = path
            end
        end
    end
    ---@type string[]
    local parts = {}
    if restored > 0 then
        table.insert(parts, string.format("restored %d", restored))
    end
    if deleted > 0 then
        table.insert(parts, string.format("removed %d created", deleted))
    end
    if renames_reversed > 0 then
        table.insert(parts, string.format("reversed %d rename(s)", renames_reversed))
    end
    local summary = #parts > 0 and table.concat(parts, ", ") or "nothing to undo"
    if #detail_parts > 0 then
        log.info("Undo: %s — %s", summary, table.concat(detail_parts, "; "))
    else
        log.info("Undo: %s", summary)
    end
    invalidate_note_cache()
    M.refresh_current(bufnr)
end

---@param bufnr? integer
function M.undo(bufnr)
    bufnr = bufnr or vim.api.nvim_get_current_buf()
    local snap = vt_undo.restore(bufnr)
    if not snap then
        log.warn("No undo snapshot available")
        return
    end
    M._apply_undo(bufnr, snap)
end

-- ─── Partial save ─────────────────────────────────────────────────────────────

---@param bufnr integer
---@param start_row integer  0-indexed inclusive
---@param end_row integer    0-indexed inclusive
function M.save_range(bufnr, start_row, end_row)
    local st = buf_states[bufnr]
    if not st or st.saving then
        return
    end
    st.saving = true

    local grid = st.grid
    local diff = grid:diff()

    -- Filter updates to only rows in range by checking line identity
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local render = require("vimtable.views.grid.render")
    local vt_id = require("vimtable.identity")
    ---@type { separator: string }
    local id_opts = { separator = render.SEP_CHAR }
    ---@type table<string, boolean>
    local selected_ids = {}
    local header_lines = grid:state().header_lines
    for row = start_row, end_row do
        if row >= header_lines then
            local line = lines[row + 1]
            if line then
                local id = vt_id.parse(line, id_opts)
                if id then
                    selected_ids[id] = true
                end
            end
        end
    end

    ---@type table[]
    local filtered = {}
    for _, upd in ipairs(diff.updates) do
        if selected_ids[upd.id] then
            table.insert(filtered, upd)
        end
    end
    if #filtered == 0 then
        log.info("No changes in selected range")
        st.saving = false
        return
    end

    ---@type table[]
    local filtered_custom = {}
    for _, custom in ipairs(diff.custom or {}) do
        if custom.type == "rename" and custom.extra and selected_ids[custom.extra.old_slug] then
            filtered_custom[#filtered_custom + 1] = custom
        end
    end

    ---@type { updates: table[], deletes: table[], creates: table[], custom: table[], errors: table[] }
    local partial =
        { updates = filtered, deletes = {}, creates = {}, custom = filtered_custom, errors = {} }
    local structural_ops = {}
    for _, op in pairs(collect_structural_ops(partial)) do
        structural_ops[#structural_ops + 1] = op
    end
    strip_structural_fields(partial)
    enter_process_save()
    local structural_ctx = build_structural_context(st, structural_ops)
    local undo_payload = snapshot_for_undo(partial, st, bufnr, structural_ops, structural_ctx)
    local ok_ren, n_r, n_patched =
        pcall(apply_structural_ops, structural_ops, partial, st, undo_payload, nil, structural_ctx)
    if not ok_ren then
        leave_process_save()
        st.saving = false
        log.error("Partial save failed: %s", tostring(n_r))
        return
    end
    local ok_apply, n_u = pcall(apply_mutations, partial, st, undo_payload)
    if not ok_apply then
        leave_process_save()
        st.saving = false
        log.error("Partial save failed: %s", tostring(n_u))
        return
    end
    invalidate_note_cache()
    log.info(
        "Partial save: %d moved, %d updated%s",
        n_r,
        n_u,
        n_patched > 0 and string.format(" (%d patched)", n_patched) or ""
    )
    vim.schedule(function()
        leave_process_save()
        M.refresh_current(bufnr)
        st.saving = false
    end)
end

-- ─── Sort helpers ─────────────────────────────────────────────────────────────

---@param bufnr integer
---@param col_name string
---@param add_secondary? boolean
function M.cycle_sort(bufnr, col_name, add_secondary)
    local st = buf_states[bufnr]
    if not st then
        return
    end
    st.grid:cycle_sort(col_name, add_secondary)
end

---@param bufnr? integer
function M.sort_by_cursor(bufnr)
    bufnr = bufnr or vim.api.nvim_get_current_buf()
    local st = buf_states[bufnr]
    if not st then
        return
    end
    st.grid:sort_by_cursor()
end

---@param bufnr integer
---@param col_name string
---@param delta integer
function M.resize_column(bufnr, col_name, delta)
    local st = buf_states[bufnr]
    if not st then
        return
    end
    st.grid:resize_column(col_name, delta)
end

---@param bufnr? integer
---@param delta integer
function M.resize_cursor_column(bufnr, delta)
    bufnr = bufnr or vim.api.nvim_get_current_buf()
    local st = buf_states[bufnr]
    if not st then
        return
    end
    st.grid:resize_cursor_column(delta)
end

---@param bufnr integer
---@param col_name string
---@param direction integer
function M.move_column(bufnr, col_name, direction)
    local st = buf_states[bufnr]
    if not st then
        return
    end
    st.grid:move_column(col_name, direction)
end

---@param bufnr? integer
---@param direction integer
function M.move_cursor_column(bufnr, direction)
    bufnr = bufnr or vim.api.nvim_get_current_buf()
    local st = buf_states[bufnr]
    if not st then
        return
    end
    st.grid:move_cursor_column(direction)
end

-- ─── Open ─────────────────────────────────────────────────────────────────────

---@param opts? { notes?: vault.Notes, columns?: string[], filter_desc?: string, base?: vault.Base, group_by?: string, readonly_columns?: string[], save_mode?: string, taxonomy_field?: string, taxonomy_choices?: string[], taxonomy_choices_provider?: fun(): string[], taxonomy_apply_choice?: fun(paths: string[], choice: string): integer, taxonomy_create_choice?: fun(query: string): string|nil, reload_notes?: fun(): vault.Notes, retain_note?: fun(note: vault.Note): boolean, statusline_builder?: fun(count: integer): string, banner_builder?: fun(count: integer): string|string[] }
function M.open(opts)
    opts = opts or {}
    get_empty_cell()

    local win = vim.api.nvim_get_current_win()
    if vim.wo[win].winfixbuf then
        vim.wo[win].winfixbuf = false
    end

    local base = opts.base
    ---@type table<string, string>
    local display_names = {}
    ---@type string[]
    local formula_cols = {}
    local filter_desc = opts.filter_desc or "all notes"
    ---@type string[]
    local visible_columns

    ---@type string[]
    local columns
    if base then
        local vis
        columns, display_names, formula_cols, vis = columns_from_base(base)
        visible_columns = opts.columns or vis
        filter_desc = opts.filter_desc or ("base:" .. (base.data.name or "unnamed"))
    else
        local cfg = grid_config.get()
        local cfg_cols = cfg.default_columns
        visible_columns = opts.columns or cfg_cols
        for i, c in ipairs(visible_columns) do
            visible_columns[i] = normalize_col(c)
        end
        for _, c in ipairs(visible_columns) do
            if READONLY_FILE_COLS[c] then
                table.insert(formula_cols, c)
            end
        end
        local has_slug = false
        for _, c in ipairs(visible_columns) do
            if c == "slug" then
                has_slug = true
                break
            end
        end
        columns = vim.list_slice(visible_columns, 1)
        if not has_slug then
            table.insert(columns, 1, "slug")
        end
    end

    -- Get notes
    local notes
    if opts.notes then
        notes = opts.notes
    else
        notes = require("vault.notes")()
    end
    local notes_map = notes.map or {}
    if base and base:has_filters() then
        notes_map = base:match_notes(notes_map)
    end
    if not next(notes_map) then
        log.info("No notes match%s", base and (" base '" .. base.data.name .. "'") or "")
        return
    end

    -- Build records
    local records = build_records(notes_map, columns, base)

    -- Determine slug_hidden
    local slug_hidden = true
    for _, c in ipairs(visible_columns) do
        if c == "slug" then
            slug_hidden = false
            break
        end
    end

    ---@type table<string, boolean>
    local readonly_columns = {}
    for _, col in ipairs(opts.readonly_columns or {}) do
        readonly_columns[normalize_col(col)] = true
    end
    local cfg = grid_config.get()
    local process_identity_mode = cfg.identity_mode or "conceal"
    local grid_identity = slug_hidden and process_identity_mode or "visible"

    local session_key = build_session_key({
        filter_desc = filter_desc,
        base = base and (base.data.path or base.data.name) or nil,
        columns = columns,
        visible_columns = visible_columns,
        readonly_columns = sorted_true_keys(readonly_columns),
        group_by = opts.group_by or (base and group_by_from_base(base)) or nil,
        save_mode = opts.save_mode,
        identity_mode = grid_identity,
        taxonomy_field = opts.taxonomy_field,
        taxonomy_choices = opts.taxonomy_choices,
    })

    -- Prevent duplicates
    for bufnr, s in pairs(buf_states) do
        if vim.api.nvim_buf_is_valid(bufnr) then
            if s.session_key == session_key then
                vim.api.nvim_set_current_buf(bufnr)
                log.info("Switched to existing grid process buffer (%s)", filter_desc)
                return
            end
        else
            buf_states[bufnr] = nil
        end
    end

    -- Build grid.Column[] from visible columns
    local grid_columns =
        build_grid_columns(visible_columns, display_names, formula_cols, readonly_columns)

    -- Prepare state (pre-grid — we need it for make_classify and make_on_save)
    ---@type vault.GridEditorState
    local st = {
        grid = nil, --- set below
        note_paths = {},
        note_mtimes = {},
        base = base,
        filter_desc = filter_desc,
        session_key = session_key,
        columns = columns,
        visible_columns = visible_columns,
        display_names = display_names,
        formula_cols = formula_cols,
        readonly_columns = readonly_columns,
        slug_hidden = slug_hidden,
        saving = false,
        save_mode = opts.save_mode,
        taxonomy_field = opts.taxonomy_field,
        taxonomy_choices = opts.taxonomy_choices,
        taxonomy_choices_provider = opts.taxonomy_choices_provider,
        taxonomy_apply_choice = opts.taxonomy_apply_choice,
        taxonomy_create_choice = opts.taxonomy_create_choice,
        reload_notes = opts.reload_notes,
        retain_note = opts.retain_note,
        statusline_builder = opts.statusline_builder,
        banner_builder = opts.banner_builder,
    }
    for _, rec in ipairs(records) do
        st.note_paths[rec.slug] = rec._path
        st.note_mtimes[rec.slug] = get_mtime(rec._path)
    end

    -- Initial sort from base
    local initial_sort = base and sort_from_base(base) or nil
    ---@type { col: string, dir: "asc"|"desc" }[]|nil
    local sort_keys
    if initial_sort then
        sort_keys = { initial_sort }
    end

    -- Row highlight groups + callback
    ensure_row_hl_groups()
    local row_hl_fn = build_row_hl()

    -- Group-by from base definition or command opts
    local group_by = opts.group_by or (base and group_by_from_base(base)) or nil

    local buf_name = "vault://grid-process/" .. filter_desc:gsub("%s+", "-")

    -- Guard against orphaned buffers with the same name (state map can be stale
    -- after hot-reload). Neovim refuses duplicate buffer names with E95.
    for _, b in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_valid(b) and vim.api.nvim_buf_get_name(b) == buf_name then
            pcall(vim.api.nvim_buf_delete, b, { force = true })
        end
    end

    -- Create Grid
    local Grid = get_Grid()
    local grid = Grid.new({
        columns = grid_columns,
        records = records,
        id_field = "slug",
        header = "inline",
        identity = grid_identity,
        separator = "\x1f",
        empty_cell = get_empty_cell(),
        buf_name = buf_name,
        filetype = "vault_process",
        on_save = make_on_save(st),
        on_undo = function(payload, done)
            -- payload is already popped from vt_undo by Grid's gu handler
            M._apply_undo(st.grid:bufnr(), payload)
            done(nil)
        end,
        on_refresh = function(g)
            M.reload(g:bufnr())
        end,
        on_filter_request = function(g)
            local s = buf_states[g:bufnr()]
            if not s then
                return
            end
            local picker = require("vault.bases.views.filter_picker")
            picker.open(g, s.visible_columns)
        end,
        keymaps = {
            refresh = "gR", -- vault uses gR instead of default <C-r>
        },
        classify = make_classify(st),
        sort_keys = sort_keys,
        row_hl = row_hl_fn,
        group_by = group_by,
        hl = {
            header = "VaultProcessHeader",
            separator = "VaultProcessSep",
            readonly = "VaultProcessFormula",
            validation_error = "VaultProcessValidationErr",
        },
    })
    st.grid = grid
    local bufnr = grid:bufnr()
    buf_states[bufnr] = st

    -- Attach to current window
    prepare_current_window_for_attach()
    local ok_attach, err_attach = pcall(function()
        grid:attach()
    end)
    if not ok_attach and tostring(err_attach):match("E37") then
        vim.cmd("silent! noautocmd enew!")
        prepare_current_window_for_attach()
        grid:attach()
    elseif not ok_attach then
        error(err_attach)
    end
    update_statusline(bufnr, st, #records)
    update_banner(bufnr, st, #records)

    -- Disable auto-formatters for this buffer
    vim.b[bufnr].formatter_skip_buf = true -- formatter.nvim
    vim.b[bufnr].autoformat = false -- conform.nvim

    -- Allow :q without "no write" error when there are no real changes
    vim.api.nvim_create_autocmd("QuitPre", {
        buffer = bufnr,
        callback = function()
            local s = buf_states[bufnr]
            if not s then
                vim.bo[bufnr].modified = false
                return
            end
            local diff = s.grid:diff()
            local total = #diff.updates + #diff.deletes + #diff.creates + #(diff.custom or {})
            if total == 0 then
                vim.bo[bufnr].modified = false
            end
        end,
    })

    -- Cleanup on buffer delete
    vim.api.nvim_create_autocmd("BufDelete", {
        buffer = bufnr,
        callback = function()
            buf_states[bufnr] = nil
            vt_undo.clear(bufnr)
        end,
    })

    -- Buffer-local keymaps (vault-specific only; gs, gS, gR, gf, gF, g>, g<, o, <C-s> handled by Grid)
    local kopts = { buffer = bufnr, silent = true }
    -- Note: `gu` keymap is handled by vimtable Grid via on_undo callback
    vim.keymap.set("n", "u", function()
        local tree = vim.fn.undotree()
        if #tree.entries > 0 then
            vim.cmd("undo")
        elseif vt_undo.has(bufnr) then
            M.undo(bufnr)
        else
            log.info("Nothing to undo")
        end
    end, vim.tbl_extend("force", kopts, { desc = "Vault: smart undo" }))
    vim.keymap.set("n", "J", function()
        local row = vim.api.nvim_win_get_cursor(0)[1] - 1
        local line_count = vim.api.nvim_buf_line_count(bufnr)
        if row + 1 >= line_count then
            log.warn("No next line to merge with")
            return
        end
        local render = require("vimtable.views.grid.render")
        local vt_id = require("vimtable.identity")
        local id_opts = { separator = render.SEP_CHAR }
        local lines = vim.api.nvim_buf_get_lines(bufnr, row, row + 2, false)
        local slug_a = lines[1] and vt_id.parse(lines[1], id_opts)
        local slug_b = lines[2] and vt_id.parse(lines[2], id_opts)
        if not slug_a or not slug_b then
            log.warn("Cannot determine note identity for merge")
            return
        end
        local path_a, path_b = st.note_paths[slug_a], st.note_paths[slug_b]
        if not path_a or not path_b then
            log.warn("Cannot find note paths for merge")
            return
        end
        require("vault.merge").merge(path_a, path_b, {
            bufnr = bufnr,
            on_done = function()
                M.refresh_current(bufnr)
            end,
        })
    end, vim.tbl_extend("force", kopts, { desc = "Vault: merge next note into current" }))
    vim.keymap.set("n", "gJ", function()
        local row = vim.api.nvim_win_get_cursor(0)[1] - 1
        local render = require("vimtable.views.grid.render")
        local vt_id = require("vimtable.identity")
        local id_opts = { separator = render.SEP_CHAR }
        local line = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1]
        local slug_a = line and vt_id.parse(line, id_opts)
        if not slug_a then
            log.warn("Cannot determine note identity")
            return
        end
        local path_a = st.note_paths[slug_a]
        if not path_a then
            log.warn("Cannot find path for current note")
            return
        end
        local scoring = require("vault.scoring")
        local snap = grid:state().snapshot
        local snap_a = snap.data and snap.data[slug_a]
        ---@type string[]
        local tags_a = {}
        if snap_a and snap_a.tags then
            if
                type(snap_a.tags) == "string"
                and snap_a.tags ~= ""
                and snap_a.tags ~= get_empty_cell()
            then
                tags_a = vim.split(snap_a.tags, ",")
                for i, t in ipairs(tags_a) do
                    tags_a[i] = vim.trim(t)
                end
            end
        end
        ---@type { slug: string, path: string, tags: string[] }[]
        local candidates = {}
        for slug, path in pairs(st.note_paths) do
            if slug ~= slug_a then
                local snap_c = snap.data and snap.data[slug]
                ---@type string[]
                local tags = {}
                if snap_c and snap_c.tags then
                    if
                        type(snap_c.tags) == "string"
                        and snap_c.tags ~= ""
                        and snap_c.tags ~= get_empty_cell()
                    then
                        tags = vim.split(snap_c.tags, ",")
                        for i, t in ipairs(tags) do
                            tags[i] = vim.trim(t)
                        end
                    end
                end
                table.insert(candidates, { slug = slug, path = path, tags = tags })
            end
        end
        local scored = scoring.score_merge_candidates(slug_a, tags_a, candidates, { limit = 200 })
        local ok_tele = pcall(function()
            local actions = require("telescope.actions")
            local action_state = require("telescope.actions.state")
            local finders = require("telescope.finders")
            local pickers = require("telescope.pickers")
            local sorters = require("telescope.sorters")
            local conf = require("telescope.config").values
            pickers
                .new({}, {
                    prompt_title = string.format("Merge into: %s <- ?", slug_a),
                    finder = finders.new_table({
                        results = scored,
                        entry_maker = function(e)
                            local pct = math.floor(e.score * 100 + 0.5)
                            return {
                                value = e,
                                display = pct > 0 and string.format("%s (%d%%)", e.slug, pct)
                                    or e.slug,
                                ordinal = e.slug,
                                path = e.path,
                                filename = e.path,
                            }
                        end,
                    }),
                    sorter = sorters.get_fuzzy_file(),
                    previewer = conf.file_previewer({}),
                    attach_mappings = function(prompt_bufnr)
                        actions.select_default:replace(function()
                            actions.close(prompt_bufnr)
                            local sel = action_state.get_selected_entry()
                            if not sel then
                                return
                            end
                            require("vault.merge").merge(path_a, sel.value.path, {
                                bufnr = bufnr,
                                on_done = function()
                                    M.refresh_current(bufnr)
                                end,
                            })
                        end)
                        return true
                    end,
                })
                :find()
        end)
        if not ok_tele then
            log.warn("gJ requires telescope.nvim")
        end
    end, vim.tbl_extend("force", kopts, { desc = "Vault: pick note to merge" }))
    -- gf, gF, g>, g< handled by Grid._setup_shared_keymaps
    vim.keymap.set("n", "g}", function()
        M.move_cursor_column(bufnr, 1)
    end, vim.tbl_extend("force", kopts, { desc = "Vault: move column right" }))
    vim.keymap.set("n", "g{", function()
        M.move_cursor_column(bufnr, -1)
    end, vim.tbl_extend("force", kopts, { desc = "Vault: move column left" }))
    vim.keymap.set("v", "<C-s>", function()
        local sr = vim.fn.line("'<") - 1
        local er = vim.fn.line("'>") - 1
        vim.api.nvim_feedkeys(
            vim.api.nvim_replace_termcodes("<Esc>", true, false, true),
            "n",
            false
        )
        M.save_range(bufnr, sr, er)
    end, vim.tbl_extend("force", kopts, { desc = "Vault: save selected rows only" }))
    vim.keymap.set("n", "gp", function()
        M.toggle_preview(bufnr)
    end, vim.tbl_extend("force", kopts, { desc = "Vault: toggle note preview on hover" }))
    vim.keymap.set("v", "g=", function()
        -- Exit visual mode first so '< '> marks are set
        vim.api.nvim_feedkeys(
            vim.api.nvim_replace_termcodes("<Esc>", true, false, true),
            "n",
            false
        )
        vim.schedule(function()
            local sr = vim.fn.line("'<") - 1
            local er = vim.fn.line("'>") - 1
            vim.ui.input({ prompt = "Set status: " }, function(value)
                if not value or value == "" then
                    return
                end
                M.batch_set_field(bufnr, "status", value, sr, er)
            end)
        end)
    end, vim.tbl_extend("force", kopts, { desc = "Vault: batch set status on selection" }))
    vim.keymap.set("v", "gt", function()
        -- Exit visual mode first so '< '> marks are set
        vim.api.nvim_feedkeys(
            vim.api.nvim_replace_termcodes("<Esc>", true, false, true),
            "n",
            false
        )
        vim.schedule(function()
            local sr = vim.fn.line("'<") - 1
            local er = vim.fn.line("'>") - 1
            vim.ui.input({ prompt = "Add tag: " }, function(tag)
                if not tag or tag == "" then
                    return
                end
                M.batch_append_tag(bufnr, tag, sr, er)
            end)
        end)
    end, vim.tbl_extend("force", kopts, { desc = "Vault: batch add tag to selection" }))
    if st.taxonomy_field and st.taxonomy_choices and #st.taxonomy_choices > 0 then
        vim.keymap.set("n", "gk", function()
            local row = vim.api.nvim_win_get_cursor(0)[1] - 1
            apply_taxonomy_choice_range(bufnr, row, row, false)
        end, vim.tbl_extend("force", kopts, { desc = "Vault: set taxonomy on current row" }))
        vim.keymap.set("v", "gk", function()
            vim.api.nvim_feedkeys(
                vim.api.nvim_replace_termcodes("<Esc>", true, false, true),
                "n",
                false
            )
            vim.schedule(function()
                local sr = vim.fn.line("'<") - 1
                local er = vim.fn.line("'>") - 1
                apply_taxonomy_choice_range(bufnr, sr, er, false)
            end)
        end, vim.tbl_extend("force", kopts, { desc = "Vault: set taxonomy on selection" }))
        vim.keymap.set("n", "gP", function()
            local row = vim.api.nvim_win_get_cursor(0)[1] - 1
            apply_taxonomy_choice_range(bufnr, row, row, true)
        end, vim.tbl_extend(
            "force",
            kopts,
            { desc = "Vault: set taxonomy and open preview" }
        ))
        vim.keymap.set(
            "v",
            "gP",
            function()
                vim.api.nvim_feedkeys(
                    vim.api.nvim_replace_termcodes("<Esc>", true, false, true),
                    "n",
                    false
                )
                vim.schedule(function()
                    local sr = vim.fn.line("'<") - 1
                    local er = vim.fn.line("'>") - 1
                    apply_taxonomy_choice_range(bufnr, sr, er, true)
                end)
            end,
            vim.tbl_extend(
                "force",
                kopts,
                { desc = "Vault: set taxonomy on selection and open preview" }
            )
        )
        vim.keymap.set("n", "gV", function()
            local row = vim.api.nvim_win_get_cursor(0)[1] - 1
            preview_taxonomy_range(bufnr, row, row)
        end, vim.tbl_extend(
            "force",
            kopts,
            { desc = "Vault: preview taxonomy for current row" }
        ))
        vim.keymap.set("v", "gV", function()
            vim.api.nvim_feedkeys(
                vim.api.nvim_replace_termcodes("<Esc>", true, false, true),
                "n",
                false
            )
            vim.schedule(function()
                local sr = vim.fn.line("'<") - 1
                local er = vim.fn.line("'>") - 1
                preview_taxonomy_range(bufnr, sr, er)
            end)
        end, vim.tbl_extend(
            "force",
            kopts,
            { desc = "Vault: preview taxonomy for selection" }
        ))
        vim.keymap.set("n", "gA", function()
            local row = vim.api.nvim_win_get_cursor(0)[1] - 1
            apply_taxonomy_range(bufnr, row, row)
        end, vim.tbl_extend(
            "force",
            kopts,
            { desc = "Vault: apply taxonomy for current row" }
        ))
        vim.keymap.set("v", "gA", function()
            vim.api.nvim_feedkeys(
                vim.api.nvim_replace_termcodes("<Esc>", true, false, true),
                "n",
                false
            )
            vim.schedule(function()
                local sr = vim.fn.line("'<") - 1
                local er = vim.fn.line("'>") - 1
                apply_taxonomy_range(bufnr, sr, er)
            end)
        end, vim.tbl_extend(
            "force",
            kopts,
            { desc = "Vault: apply taxonomy for selection" }
        ))
    end

    -- Help legend
    ---@type { group?: string, lhs?: string, desc: string }[]
    local help_items = {
        { group = "Navigation", lhs = "h / l", desc = "Column left / right" },
        { lhs = "j / k", desc = "Row up / down" },
        { lhs = "g> / g<", desc = "Resize column wider / narrower" },
        { lhs = "g} / g{", desc = "Move column right / left" },
        { group = "Saving", lhs = ":w / <C-s>", desc = "Save all changes" },
        { lhs = "<C-s> (visual)", desc = "Save selected rows only" },
        { group = "Undo", lhs = "u / gu", desc = "Undo (vim / plugin-level)" },
        { group = "Sort", lhs = "gs", desc = "Cycle sort on column" },
        { lhs = "gS", desc = "Add secondary sort key" },
        { group = "Filter", lhs = "gf", desc = "Open filter picker" },
        { lhs = "gF", desc = "Clear all filters" },
        { group = "Merge", lhs = "J", desc = "Merge next note into current" },
        { lhs = "gJ", desc = "Pick note to merge (Telescope)" },
        { group = "Batch ops", lhs = "g= (visual)", desc = "Set status on selection" },
        { lhs = "gt (visual)", desc = "Add tag to selection" },
        { group = "Reload", lhs = "gR", desc = "Reload buffer" },
        { group = "Preview", lhs = "gp", desc = "Toggle note preview on hover" },
        { group = "Detail", lhs = "gd", desc = "Open note detail form" },
        { group = "Help", lhs = "g?", desc = "Toggle this help" },
    }
    if st.taxonomy_field and st.taxonomy_choices and #st.taxonomy_choices > 0 then
        table.insert(help_items, 16, { lhs = "gk", desc = "Set taxonomy on row / selection" })
        table.insert(help_items, 17, { lhs = "gP", desc = "Set taxonomy and open preview" })
        table.insert(help_items, 18, { lhs = "gV", desc = "Preview taxonomy for row / selection" })
        table.insert(help_items, 19, { lhs = "gA", desc = "Apply taxonomy for row / selection" })
    end
    require("vimtable.help").setup_keymap(bufnr, help_items)

    local sort_desc = initial_sort
            and string.format(", sorted by %s %s", initial_sort.col, initial_sort.dir)
        or ""
    log.info(
        "Processing %d notes (%s)%s [grid] — :w to apply, gs/gS to sort, gu to undo, g>/g< to resize",
        #records,
        filter_desc,
        sort_desc
    )
end

-- ─── Inline note preview (CursorHold float) ──────────────────────────────────

local PREVIEW_MAX_LINES = 15
local PREVIEW_MAX_WIDTH = 80

--- Close the preview float if it exists.
---@param st vault.GridEditorState
local function close_preview(st)
    if st._preview_win and vim.api.nvim_win_is_valid(st._preview_win) then
        vim.api.nvim_win_close(st._preview_win, true)
    end
    st._preview_win = nil
    st._preview_slug = nil
end

--- Show a floating preview of the note under the cursor.
---@param bufnr integer
---@param st vault.GridEditorState
local function show_preview(bufnr, st)
    if not st.grid then
        return
    end
    local row = vim.api.nvim_win_get_cursor(0)[1] - 1
    local header_lines = st.grid:state().header_lines
    if row < header_lines then
        close_preview(st)
        return
    end

    local line = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1]
    if not line then
        close_preview(st)
        return
    end

    local render = require("vimtable.views.grid.render")
    local vt_id = require("vimtable.identity")
    local slug = vt_id.parse(line, { separator = render.SEP_CHAR })
    if not slug then
        close_preview(st)
        return
    end

    -- Don't re-open for same slug
    if
        st._preview_slug == slug
        and st._preview_win
        and vim.api.nvim_win_is_valid(st._preview_win)
    then
        return
    end
    close_preview(st)

    local path = st.note_paths[slug]
    if not path then
        return
    end

    local ok, file_lines = pcall(vim.fn.readfile, path, "", PREVIEW_MAX_LINES)
    if not ok or #file_lines == 0 then
        return
    end

    -- Compute float size
    local width = 0
    for _, l in ipairs(file_lines) do
        local len = vim.fn.strdisplaywidth(l) --[[@as integer]]
        if len > width then
            width = len
        end
    end
    width = math.min(width + 2, PREVIEW_MAX_WIDTH)
    width = math.max(width, 20)
    local height = math.min(#file_lines, PREVIEW_MAX_LINES)

    local preview_buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(preview_buf, 0, -1, false, file_lines)
    vim.bo[preview_buf].modifiable = false
    vim.bo[preview_buf].bufhidden = "wipe"
    vim.bo[preview_buf].filetype = "markdown"

    local ui = vim.api.nvim_list_uis()[1] or { width = 120, height = 40 }
    local cursor_row = vim.api.nvim_win_get_cursor(0)[1]
    local anchor_row = cursor_row + 1
    local anchor_col = 2
    -- Flip above if not enough room below
    if anchor_row + height + 2 > ui.height then
        anchor_row = cursor_row - height - 2
        if anchor_row < 0 then
            anchor_row = 0
        end
    end

    st._preview_win = vim.api.nvim_open_win(preview_buf, false, {
        relative = "win",
        win = vim.api.nvim_get_current_win(),
        width = width,
        height = height,
        row = anchor_row - cursor_row,
        col = anchor_col,
        style = "minimal",
        border = "rounded",
        title = " " .. slug .. " ",
        title_pos = "center",
        focusable = false,
        noautocmd = true,
    })
    st._preview_slug = slug
end

--- Toggle preview mode on/off for a grid buffer.
---@param bufnr integer
function M.toggle_preview(bufnr)
    local st = buf_states[bufnr]
    if not st then
        return
    end
    if st._preview_enabled then
        st._preview_enabled = false
        close_preview(st)
        if st._preview_augroup then
            pcall(vim.api.nvim_del_augroup_by_id, st._preview_augroup)
            st._preview_augroup = nil
        end
        log.info("Preview off")
    else
        st._preview_enabled = true
        local group = vim.api.nvim_create_augroup("vault_grid_preview_" .. bufnr, { clear = true })
        st._preview_augroup = group
        vim.api.nvim_create_autocmd("CursorHold", {
            group = group,
            buffer = bufnr,
            callback = function()
                show_preview(bufnr, st)
            end,
        })
        vim.api.nvim_create_autocmd({ "CursorMoved", "InsertEnter", "BufLeave" }, {
            group = group,
            buffer = bufnr,
            callback = function()
                close_preview(st)
            end,
        })
        log.info("Preview on (CursorHold)")
        -- Show immediately for current position
        show_preview(bufnr, st)
    end
end

-- ─── Batch operations (visual selection) ──────────────────────────────────────

--- Collect note slugs and paths for a visual row range.
---@param bufnr integer
---@param start_row integer  0-indexed inclusive
---@param end_row integer    0-indexed inclusive
---@return { slug: string, path: string }[]
local function collect_row_identities(bufnr, start_row, end_row)
    local st = buf_states[bufnr]
    if not st or not st.grid then
        return {}
    end
    local grid = st.grid
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local render = require("vimtable.views.grid.render")
    local vt_id = require("vimtable.identity")
    local id_opts = { separator = render.SEP_CHAR }
    local header_lines = grid:state().header_lines
    local results = {}
    for row = start_row, end_row do
        if row >= header_lines then
            local line = lines[row + 1]
            if line then
                local slug = vt_id.parse(line, id_opts)
                if slug and st.note_paths[slug] then
                    table.insert(results, { slug = slug, path = st.note_paths[slug] })
                end
            end
        end
    end
    return results
end

---@param bufnr integer
---@param start_row integer
---@param end_row integer
---@return string[]
local function collect_row_paths(bufnr, start_row, end_row)
    local paths = {}
    for _, target in ipairs(collect_row_identities(bufnr, start_row, end_row)) do
        table.insert(paths, target.path)
    end
    return paths
end

---@param bufnr integer
---@param start_row integer
---@param end_row integer
preview_taxonomy_range = function(bufnr, start_row, end_row)
    local paths = collect_row_paths(bufnr, start_row, end_row)
    if #paths == 0 then
        log.info("No notes in selection")
        return
    end
    require("vault.taxonomy").preview({ paths = paths })
end

---@param bufnr integer
---@param start_row integer
---@param end_row integer
apply_taxonomy_range = function(bufnr, start_row, end_row)
    local paths = collect_row_paths(bufnr, start_row, end_row)
    if #paths == 0 then
        log.info("No notes in selection")
        return
    end
    local plan = require("vault.taxonomy").preview({ paths = paths, open = false })
    local report = require("vault.taxonomy").apply({ plan = plan })
    if report ~= nil then
        M.refresh_current(bufnr)
    end
end

---@param bufnr integer
---@param start_row integer
---@param end_row integer
---@param open_preview boolean
apply_taxonomy_choice_range = function(bufnr, start_row, end_row, open_preview)
    local st = buf_states[bufnr]
    if not st or not st.taxonomy_field then
        log.warn("No taxonomy choices configured")
        return
    end
    if type(st.taxonomy_choices_provider) == "function" then
        local ok, choices = pcall(st.taxonomy_choices_provider)
        if ok and type(choices) == "table" then
            st.taxonomy_choices = choices
        end
    end
    if not st.taxonomy_choices or #st.taxonomy_choices == 0 then
        log.warn("No taxonomy choices configured")
        return
    end
    local targets = collect_row_identities(bufnr, start_row, end_row)
    if #targets == 0 then
        log.info("No notes in selection")
        return
    end
    ---@type string[]
    local paths = {}
    for _, target in ipairs(targets) do
        table.insert(paths, target.path)
    end
    local prompt = open_preview and "Set taxonomy + preview: " or "Set taxonomy: "
    local ok_telescope, actions = pcall(require, "telescope.actions")
    local ok_state, action_state = pcall(require, "telescope.actions.state")
    local ok_finders, finders = pcall(require, "telescope.finders")
    local ok_pickers, pickers = pcall(require, "telescope.pickers")
    local ok_conf, conf_mod = pcall(require, "telescope.config")
    if ok_telescope and ok_state and ok_finders and ok_pickers and ok_conf then
        local function commit_choice(choice)
            if not choice or choice == "" then
                return
            end
            if type(st.taxonomy_apply_choice) == "function" then
                st.taxonomy_apply_choice(paths, choice)
            else
                M.batch_set_field(bufnr, st.taxonomy_field, choice, start_row, end_row)
            end
            M.refresh_current(bufnr)
            if open_preview then
                require("vault.taxonomy").preview({ paths = paths })
            end
        end

        pickers
            .new({}, {
                prompt_title = prompt .. "(<C-n> create category)",
                finder = finders.new_table({ results = st.taxonomy_choices }),
                sorter = conf_mod.values.generic_sorter({}),
                sorting_strategy = "ascending",
                attach_mappings = function(prompt_bufnr, map)
                    actions.select_default:replace(function()
                        local selection = action_state.get_selected_entry()
                        actions.close(prompt_bufnr)
                        commit_choice(selection and selection[1] or action_state.get_current_line())
                    end)

                    local function create_from_query()
                        if type(st.taxonomy_create_choice) ~= "function" then
                            return
                        end
                        local query = vim.trim(action_state.get_current_line() or "")
                        if query == "" then
                            return
                        end
                        actions.close(prompt_bufnr)
                        local created = st.taxonomy_create_choice(query)
                        if created and type(st.taxonomy_choices_provider) == "function" then
                            local ok, choices = pcall(st.taxonomy_choices_provider)
                            if ok and type(choices) == "table" then
                                st.taxonomy_choices = choices
                            end
                        end
                        commit_choice(created)
                    end

                    map("i", "<C-n>", create_from_query)
                    map("n", "<C-n>", create_from_query)
                    return true
                end,
            })
            :find()
        return
    end

    vim.ui.select(st.taxonomy_choices, { prompt = prompt }, function(choice)
        if not choice or choice == "" then
            return
        end
        if type(st.taxonomy_apply_choice) == "function" then
            st.taxonomy_apply_choice(paths, choice)
        else
            M.batch_set_field(bufnr, st.taxonomy_field, choice, start_row, end_row)
        end
        M.refresh_current(bufnr)
        if open_preview then
            require("vault.taxonomy").preview({ paths = paths })
        end
    end)
end

--- Batch-set a frontmatter field on all notes in a visual selection.
---@param bufnr integer
---@param field string   field name (e.g. "status")
---@param value string   value to set
---@param start_row integer  0-indexed inclusive
---@param end_row integer    0-indexed inclusive
function M.batch_set_field(bufnr, field, value, start_row, end_row)
    local targets = collect_row_identities(bufnr, start_row, end_row)
    if #targets == 0 then
        log.info("No notes in selection")
        return
    end
    for _, t in ipairs(targets) do
        shared.set_frontmatter_fields(t.path, { [field] = value })
    end
    log.info("Set %s=%s on %d notes", field, value, #targets)
    M.refresh_current(bufnr)
end

--- Batch-append a tag to all notes in a visual selection (deduplicates).
---@param bufnr integer
---@param tag string     tag to add (with or without # prefix)
---@param start_row integer  0-indexed inclusive
---@param end_row integer    0-indexed inclusive
function M.batch_append_tag(bufnr, tag, start_row, end_row)
    -- Normalize: strip leading # for storage
    tag = tag:gsub("^#", "")
    if tag == "" then
        log.warn("Empty tag")
        return
    end
    local targets = collect_row_identities(bufnr, start_row, end_row)
    if #targets == 0 then
        log.info("No notes in selection")
        return
    end
    for _, t in ipairs(targets) do
        local existing = shared.read_frontmatter_fields(t.path, { "tags" })
        local tags = existing.tags
        if type(tags) == "string" then
            tags = vim.split(tags, ",")
            for i, v in ipairs(tags) do
                tags[i] = vim.trim(v)
            end
        elseif type(tags) ~= "table" then
            tags = {}
        end
        -- Dedup: check if tag already present (normalize # prefix)
        local found = false
        for _, existing_tag in ipairs(tags) do
            if existing_tag:gsub("^#", "") == tag then
                found = true
                break
            end
        end
        if not found then
            table.insert(tags, tag)
        end
        shared.set_frontmatter_fields(t.path, { tags = tags })
    end
    log.info("Added tag #%s to %d notes", tag, #targets)
    M.refresh_current(bufnr)
end

-- ─── Debug / test exports ─────────────────────────────────────────────────────

M._buf_states = buf_states
M._vt_undo = vt_undo -- for merge.lua and tests

-- Pure-function exports for unit testing (prefixed with _ to signal internal use)
M._normalize_col = shared.normalize_col
M._base_key_to_col = shared.base_key_to_col
M._columns_from_base = columns_from_base
M._yaml_quote = shared.yaml_quote
M._validate_path_in_vault = shared.validate_path_in_vault
M._fmt_value = shared.fmt_value
M._parse_value = shared.parse_value
M._make_classify = make_classify
M._build_records = build_records
M._build_grid_columns = build_grid_columns
M._sort_from_base = sort_from_base
M._atomic_writefile = shared.atomic_writefile
M._read_frontmatter_fields = shared.read_frontmatter_fields
M._set_frontmatter_field = shared.set_frontmatter_field
M._set_frontmatter_fields = shared.set_frontmatter_fields
M._snapshot_for_undo = snapshot_for_undo
M._apply_structural_ops = apply_structural_ops
M._apply_mutations = apply_mutations
M._make_on_save = make_on_save
M._get_mtime = get_mtime

return M
