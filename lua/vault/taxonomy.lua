local config = require("vault.config")
local log = require("vault.log").scope("taxonomy")
local utils = require("vault.utils")
local shared = require("vault.bases.views.shared")

local M = {}

local uv = vim.uv or vim.loop
local is_list = vim.islist or vim.tbl_islist

---@class vault.Taxonomy.MappingEntry
---@field prefix string
---@field dir? string

---@class vault.Taxonomy.Settings
---@field field string
---@field reference_prefix? string
---@field classify { columns?: string[], readonly_columns?: string[], dirs?: string[]|nil }
---@field rename { require_preview?: boolean, update_links?: boolean, chunk_size?: integer, skip_collisions?: boolean }
---@field mapping table<string, vault.Taxonomy.MappingEntry>

---@class vault.Taxonomy.PlanMove
---@field from string
---@field to string
---@field from_slug string
---@field to_slug string
---@field kind string
---@field prefix string

---@class vault.Taxonomy.PlanSkip
---@field path string
---@field slug string
---@field kind? string
---@field reason string
---@field target? string

---@class vault.Taxonomy.Plan
---@field created_at string
---@field root string
---@field field string
---@field moves vault.Taxonomy.PlanMove[]
---@field skipped vault.Taxonomy.PlanSkip[]
---@field unchanged integer

local function preview_manifest_path()
    return vim.fn.stdpath("cache") .. "/vault-taxonomy-preview.json"
end

local function last_apply_manifest_path()
    return vim.fn.stdpath("cache") .. "/vault-taxonomy-last-apply.json"
end

---@param value any
---@return boolean
local function is_missing_value(value)
    if value == nil or value == vim.NIL then
        return true
    end
    if type(value) == "string" then
        return vim.trim(value) == ""
    end
    if type(value) == "table" then
        return next(value) == nil
    end
    return false
end

---@param settings vault.Taxonomy.Settings
---@param value any
---@return string?
local function normalize_kind(settings, value)
    if value == nil or value == vim.NIL then
        return nil
    end

    if type(value) == "table" then
        if is_list(value) then
            for _, item in ipairs(value) do
                local normalized = normalize_kind(settings, item)
                if normalized then
                    return normalized
                end
            end
        end
        return nil
    end

    if type(value) ~= "string" then
        return nil
    end

    local result = vim.trim(value)
    if result == "" then
        return nil
    end

    local wikilink = result:match("^%[%[([^%]]+)%]%]$")
    if wikilink then
        result = wikilink:match("^[^|#]+") or wikilink
    end

    result = result:match("[^/]+$") or result
    result = result:gsub("%s+", " ")
    result = vim.trim(result)
    local reference_prefix = settings.reference_prefix
    if type(reference_prefix) == "string" and reference_prefix ~= "" then
        local lower_prefix = reference_prefix:lower()
        local lower_result = result:lower()
        if lower_result:sub(1, #lower_prefix) == lower_prefix then
            result = vim.trim(result:sub(#reference_prefix + 1))
        end
    end
    if result == "" then
        return nil
    end

    return result:lower()
end

---@param entry string|table
---@return vault.Taxonomy.MappingEntry?
local function normalize_mapping_entry(entry)
    if type(entry) == "string" then
        return { prefix = entry }
    end
    if type(entry) ~= "table" then
        return nil
    end
    return {
        prefix = type(entry.prefix) == "string" and entry.prefix or "",
        dir = type(entry.dir) == "string" and entry.dir or nil,
    }
end

---@return vault.Taxonomy.Settings
local function get_settings()
    local cfg = config.options.taxonomy or {}
    local mapping = {}
    for kind, entry in pairs(cfg.mapping or {}) do
        local normalized_kind = normalize_kind({ reference_prefix = cfg.reference_prefix }, kind)
        local normalized_entry = normalize_mapping_entry(entry)
        if normalized_kind and normalized_entry and normalized_entry.prefix ~= "" then
            mapping[normalized_kind] = normalized_entry
        end
    end

    local field = type(cfg.field) == "string" and cfg.field or "categories"
    local classify = vim.deepcopy(cfg.classify or {})
    if type(classify.columns) ~= "table" or #classify.columns == 0 then
        classify.columns = { "slug", "title", field, "file.mtime" }
        if field ~= "categories" then
            table.insert(classify.columns, 4, "categories")
        end
    end

    return {
        field = field,
        reference_prefix = type(cfg.reference_prefix) == "string" and cfg.reference_prefix or nil,
        classify = classify,
        rename = cfg.rename or {},
        mapping = mapping,
    }
end

---@param path string
---@return table<string, integer|string>|nil
local function stat_key(path)
    local stat = uv.fs_stat(path)
    if not stat then
        return nil
    end
    return { dev = stat.dev, ino = stat.ino }
end

---@param a string
---@param b string
---@return boolean
local function same_inode(a, b)
    local sa = stat_key(a)
    local sb = stat_key(b)
    return sa ~= nil and sb ~= nil and sa.dev == sb.dev and sa.ino == sb.ino
end

---@param root string
---@param dir string?
---@return string?
local function normalize_dir(root, dir)
    if type(dir) ~= "string" or dir == "" then
        return nil
    end
    local candidate = vim.fs.normalize(vim.fn.expand(dir))
    local normalized_root = vim.fs.normalize(vim.fn.expand(root))
    if candidate:sub(1, #normalized_root + 1) == normalized_root .. "/" then
        return utils.path_to_relpath(candidate)
    end
    return dir:gsub("^/*", ""):gsub("/*$", "")
end

---@param relpath string
---@param dirs string[]|nil
---@return boolean
local function relpath_in_dirs(relpath, dirs)
    if not dirs or #dirs == 0 then
        return true
    end

    for _, dir in ipairs(dirs) do
        if relpath == dir or relpath:find("^" .. vim.pesc(dir) .. "/") then
            return true
        end
    end

    return false
end

---@param note vault.Note
---@param field string
---@return any
local function get_frontmatter_value(note, field)
    local fm = note.data.frontmatter
    if type(fm) ~= "table" then
        return nil
    end
    if fm[field] ~= nil then
        return fm[field]
    end
    local fm_data = fm.data
    if type(fm_data) == "table" then
        return fm_data[field]
    end
    return nil
end

---@param settings vault.Taxonomy.Settings
---@param value any
---@return string?
---@return string
local function extract_kind(settings, value)
    if is_missing_value(value) then
        return nil, "missing-kind"
    end

    if type(value) == "table" and is_list(value) then
        local saw_value = false
        local saw_unmapped = nil
        for _, item in ipairs(value) do
            local normalized = normalize_kind(settings, item)
            if normalized then
                saw_value = true
                if settings.mapping[normalized] then
                    return normalized, "ok"
                end
                saw_unmapped = normalized
            end
        end
        if saw_unmapped then
            return nil, "unmapped-kind"
        end
        if saw_value then
            return nil, "unmapped-kind"
        end
        return nil, "missing-kind"
    end

    local normalized = normalize_kind(settings, value)
    if not normalized then
        return nil, "missing-kind"
    end
    if settings.mapping[normalized] then
        return normalized, "ok"
    end
    return nil, "unmapped-kind"
end

---@param value any
---@return string[]
local function as_list(value)
    if value == nil or value == vim.NIL then
        return {}
    end
    if type(value) == "table" and is_list(value) then
        local items = {}
        for _, item in ipairs(value) do
            if item ~= nil and item ~= vim.NIL then
                table.insert(items, tostring(item))
            end
        end
        return items
    end
    if type(value) == "string" and vim.trim(value) ~= "" then
        return { value }
    end
    return {}
end

---@param choice string
---@param settings vault.Taxonomy.Settings
---@return any
local function format_choice_value(choice, settings)
    if settings.field == "categories" then
        local note_name = (settings.reference_prefix or "") .. choice
        return { string.format("[[%s]]", note_name) }
    end
    return choice
end

---@param note vault.Note
---@param settings vault.Taxonomy.Settings
---@return string
local function stripped_stem(note, settings)
    local stem = note.data.stem or ""
    local lower_stem = stem:lower()

    local prefixes = {}
    for _, entry in pairs(settings.mapping) do
        table.insert(prefixes, entry.prefix)
    end
    table.sort(prefixes, function(a, b)
        return #a > #b
    end)

    for _, prefix in ipairs(prefixes) do
        local lower_prefix = prefix:lower()
        if lower_stem:sub(1, #lower_prefix) == lower_prefix then
            return vim.trim(stem:sub(#prefix + 1))
        end
    end

    return stem
end

---@param root string
---@param rel_dir string?
---@param filename string
---@return string
local function join_under_root(root, rel_dir, filename)
    if rel_dir and rel_dir ~= "" and rel_dir ~= "." then
        return vim.fs.normalize(root .. "/" .. rel_dir .. "/" .. filename)
    end
    return vim.fs.normalize(root .. "/" .. filename)
end

---@param note vault.Note
---@param settings vault.Taxonomy.Settings
---@return table|nil, string?
local function inspect_note(note, settings)
    local kind, reason = extract_kind(settings, get_frontmatter_value(note, settings.field))
    if not kind then
        return nil, reason
    end

    local mapping = settings.mapping[kind]

    local basename = stripped_stem(note, settings)
    if basename == "" then
        return nil, "empty-stem"
    end

    local current_rel_dir = vim.fn.fnamemodify(note.data.relpath, ":h")
    if current_rel_dir == "." then
        current_rel_dir = ""
    end
    local target_rel_dir = normalize_dir(config.options.root, mapping.dir) or current_rel_dir
    local target_name = mapping.prefix .. basename .. (config.options.ext or ".md")
    local target_path = join_under_root(config.options.root, target_rel_dir, target_name)

    return {
        note = note,
        kind = kind,
        prefix = mapping.prefix,
        from = vim.fs.normalize(note.data.path),
        to = target_path,
        from_slug = note.data.slug,
        to_slug = utils.path_to_slug(target_path),
    }, nil
end

---@return string[]|nil
---@param override_dirs? string[]|false
local function classify_dirs(settings, override_dirs)
    if override_dirs == false then
        return nil
    end
    if type(override_dirs) == "table" then
        local normalized_override = {}
        for _, dir in ipairs(override_dirs) do
            local value = normalize_dir(config.options.root, dir)
            if value and value ~= "" then
                table.insert(normalized_override, value)
            end
        end
        return #normalized_override > 0 and normalized_override or nil
    end

    local dirs = settings.classify.dirs
    if type(dirs) ~= "table" then
        local inbox_dir = config.dir("inbox")
        if inbox_dir then
            local inferred = normalize_dir(config.options.root, inbox_dir)
            return inferred and { inferred } or nil
        end
        return nil
    end

    local normalized = {}
    for _, dir in ipairs(dirs) do
        local value = normalize_dir(config.options.root, dir)
        if value and value ~= "" then
            table.insert(normalized, value)
        end
    end

    return #normalized > 0 and normalized or nil
end

---@return string[]
function M.kind_choices()
    local settings = get_settings()
    local choices = vim.tbl_keys(settings.mapping)
    table.sort(choices)
    return choices
end

---@param label string
---@param count integer
---@param field string
---@return string
local function build_classify_statusline(label, count, field)
    local noun = count == 1 and "note" or "notes"
    return table.concat({
        " Vault ",
        label,
        string.format(" | %d %s missing %s ", count, noun, field),
        "| gk set taxonomy ",
        "| gP set + preview ",
        "| :w save ",
    }, "")
end

---@param label string
---@param count integer
---@param field string
---@return string[]
local function build_classify_banner(label, count, field)
    local noun = count == 1 and "note" or "notes"
    return {
        string.format("Taxonomy classify: %s | %d %s missing %s", label, count, noun, field),
        "gk set taxonomy | gP set taxonomy + preview | :w save | :Vault taxonomy preview",
    }
end

---@param field string
---@return string[]
local function build_audit_banner(field)
    return {
        string.format("Taxonomy audit | filenames disagree with %s", field),
        "gk set taxonomy | gP set taxonomy + preview | :Vault taxonomy preview",
    }
end

---@param field string
---@return string
local function build_audit_statusline(field)
    return table.concat({
        " Vault taxonomy audit ",
        string.format("| filenames disagree with %s ", field),
        "| gk set taxonomy ",
        "| gP set + preview ",
    }, "")
end

---@param paths string[]
---@param choice string
function M.apply_choice_to_paths(paths, choice)
    local settings = get_settings()
    if type(choice) ~= "string" or choice == "" then
        return 0
    end

    local written = 0
    for _, path in ipairs(paths) do
        if settings.field == "categories" then
            local existing = shared.read_frontmatter_fields(path, { settings.field })[settings.field]
            local values = as_list(existing)
            local kept = {}
            for _, value in ipairs(values) do
                local normalized = normalize_kind(settings, value)
                if not (normalized and settings.mapping[normalized]) then
                    table.insert(kept, value)
                end
            end
            table.insert(kept, format_choice_value(choice, settings)[1])
            shared.set_frontmatter_fields(path, { [settings.field] = kept })
        else
            shared.set_frontmatter_fields(path, { [settings.field] = format_choice_value(choice, settings) })
        end
        written = written + 1
    end
    return written
end

---@param opts? { dirs?: string[]|false }
---@return vault.Notes
function M.classify_notes(opts)
    opts = opts or {}
    local settings = get_settings()
    local dirs = classify_dirs(settings, opts.dirs)
    local notes = require("vault.notes")()
    local filtered = {}
    for slug, note in pairs(notes.map) do
        local _, reason = extract_kind(settings, get_frontmatter_value(note, settings.field))
        if relpath_in_dirs(note.data.relpath, dirs) and reason ~= "ok" then
            filtered[slug] = note
        end
    end
    notes.map = filtered
    return notes:to_group()
end

---@return vault.Notes
function M.audit_notes()
    local settings = get_settings()
    local notes = require("vault.notes")()
    local filtered = {}
    for slug, note in pairs(notes.map) do
        local info = inspect_note(note, settings)
        if info and info.from ~= info.to then
            filtered[slug] = note
        end
    end
    notes.map = filtered
    return notes:to_group()
end

---@return vault.Taxonomy.Plan
function M.build_plan()
    local settings = get_settings()
    local notes = require("vault.notes")()
    local candidates = {}
    local skipped = {}
    local unchanged = 0

    for _, note in pairs(notes.map) do
        local info, reason = inspect_note(note, settings)
        if not info then
            if reason == "unmapped-kind" then
                local raw_value = get_frontmatter_value(note, settings.field)
                local normalized = normalize_kind(settings, raw_value)
                table.insert(skipped, {
                    path = note.data.path,
                    slug = note.data.slug,
                    kind = normalized,
                    reason = reason,
                })
            end
        elseif info.from == info.to then
            unchanged = unchanged + 1
        else
            table.insert(candidates, info)
        end
    end

    local target_counts = {}
    for _, info in ipairs(candidates) do
        target_counts[info.to] = (target_counts[info.to] or 0) + 1
    end

    local moves = {}
    local skip_collisions = settings.rename.skip_collisions ~= false
    for _, info in ipairs(candidates) do
        local collision_reason = nil
        if target_counts[info.to] > 1 then
            collision_reason = "duplicate-target"
        elseif skip_collisions and vim.fn.filereadable(info.to) == 1 and not same_inode(info.from, info.to) then
            collision_reason = "target-exists"
        end

        if collision_reason then
            table.insert(skipped, {
                path = info.from,
                slug = info.from_slug,
                kind = info.kind,
                reason = collision_reason,
                target = info.to,
            })
        else
            table.insert(moves, {
                from = info.from,
                to = info.to,
                from_slug = info.from_slug,
                to_slug = info.to_slug,
                kind = info.kind,
                prefix = info.prefix,
            })
        end
    end

    table.sort(moves, function(a, b)
        return a.from < b.from
    end)
    table.sort(skipped, function(a, b)
        return a.path < b.path
    end)

    return {
        created_at = os.date("!%Y-%m-%dT%H:%M:%SZ"),
        root = config.options.root,
        field = settings.field,
        moves = moves,
        skipped = skipped,
        unchanged = unchanged,
    }
end

---@param path string
---@param payload table
local function write_manifest(path, payload)
    vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
    local encoded = vim.json.encode(payload)
    local lines = vim.split(encoded, "\n", { plain = true })
    vim.fn.writefile(lines, path)
end

---@param path string
---@return table|nil
local function read_manifest(path)
    if vim.fn.filereadable(path) == 0 then
        return nil
    end
    local lines = vim.fn.readfile(path)
    if not lines or #lines == 0 then
        return nil
    end
    local ok, decoded = pcall(vim.json.decode, table.concat(lines, "\n"))
    if not ok then
        return nil
    end
    return decoded
end

---@param plan vault.Taxonomy.Plan
local function open_preview_buffer(plan)
    local lines = {
        "# Vault taxonomy preview",
        "",
        string.format("field: %s", plan.field),
        string.format("ready: %d", #plan.moves),
        string.format("skipped: %d", #plan.skipped),
        string.format("unchanged: %d", plan.unchanged),
        "",
    }

    if #plan.moves > 0 then
        table.insert(lines, "## Ready")
        table.insert(lines, "")
        for _, move in ipairs(plan.moves) do
            table.insert(lines, string.format("- [%s] %s -> %s", move.kind, move.from_slug, move.to_slug))
        end
        table.insert(lines, "")
    end

    if #plan.skipped > 0 then
        table.insert(lines, "## Skipped")
        table.insert(lines, "")
        for _, item in ipairs(plan.skipped) do
            local target = item.target and (" -> " .. utils.path_to_slug(item.target)) or ""
            table.insert(lines, string.format("- [%s] %s%s", item.reason, item.slug, target))
        end
        table.insert(lines, "")
    end

    vim.cmd("botright new")
    local buf = vim.api.nvim_get_current_buf()
    vim.bo[buf].buftype = "nofile"
    vim.bo[buf].bufhidden = "wipe"
    vim.bo[buf].swapfile = false
    vim.bo[buf].modifiable = true
    vim.bo[buf].filetype = "markdown"
    vim.api.nvim_buf_set_name(buf, "vault://taxonomy-preview")
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].modifiable = false
end

---@param opts? { dirs?: string[]|false, filter_desc?: string }
function M.open_classify(opts)
    opts = opts or {}
    local settings = get_settings()
    local notes = M.classify_notes({ dirs = opts.dirs })
    if notes:count() == 0 then
        log.info("No notes missing taxonomy field '%s'", settings.field)
        return
    end

    local label = opts.filter_desc or ("classify:" .. settings.field)
    require("vault.bases.views.grid").open({
        notes = notes,
        filter_desc = label,
        columns = settings.classify.columns,
        readonly_columns = settings.classify.readonly_columns,
        save_mode = "metadata_only",
        taxonomy_field = settings.field,
        taxonomy_choices = M.kind_choices(),
        taxonomy_apply_choice = function(paths, choice)
            return M.apply_choice_to_paths(paths, choice)
        end,
        reload_notes = function()
            return M.classify_notes({ dirs = opts.dirs })
        end,
        statusline_builder = function(count)
            return build_classify_statusline(label, count, settings.field)
        end,
        banner_builder = function(count)
            return build_classify_banner(label, count, settings.field)
        end,
    })
end

function M.open_audit()
    local settings = get_settings()
    local notes = M.audit_notes()
    if notes:count() == 0 then
        log.info("No taxonomy filename mismatches found")
        return
    end

    require("vault.bases.views.grid").open({
        notes = notes,
        filter_desc = "taxonomy-audit",
        columns = settings.classify.columns,
        readonly_columns = settings.classify.readonly_columns,
        save_mode = "metadata_only",
        taxonomy_field = settings.field,
        taxonomy_choices = M.kind_choices(),
        taxonomy_apply_choice = function(paths, choice)
            return M.apply_choice_to_paths(paths, choice)
        end,
        reload_notes = function()
            return M.audit_notes()
        end,
        statusline_builder = function()
            return build_audit_statusline(settings.field)
        end,
        banner_builder = function()
            return build_audit_banner(settings.field)
        end,
    })
end

---@return vault.Taxonomy.Plan
function M.preview()
    local plan = M.build_plan()
    write_manifest(preview_manifest_path(), plan)
    open_preview_buffer(plan)
    log.info(
        "Taxonomy preview: %d ready, %d skipped, %d unchanged",
        #plan.moves,
        #plan.skipped,
        plan.unchanged
    )
    return plan
end

---@param moves vault.Taxonomy.PlanMove[]
---@param opts { update_links?: boolean, chunk_size?: integer }
---@return table
local function apply_moves(moves, opts)
    local notes = require("vault.notes")()
    local report = {
        moved = 0,
        patched_files = 0,
        skipped = 0,
        renames = {},
    }
    local chunk_size = math.max(1, tonumber(opts.chunk_size) or #moves)
    for idx = 1, #moves, chunk_size do
        local chunk = {}
        for move_idx = idx, math.min(idx + chunk_size - 1, #moves) do
            table.insert(chunk, {
                from = moves[move_idx].from,
                to = moves[move_idx].to,
            })
        end
        local chunk_report = notes:move_many(chunk, {
            update_links = opts.update_links,
            verbose = false,
            silent = true,
        })
        report.moved = report.moved + (chunk_report.moved or 0)
        report.patched_files = report.patched_files + (chunk_report.patched_files or 0)
        report.skipped = report.skipped + (chunk_report.skipped or 0)
        vim.list_extend(report.renames, chunk_report.renames or {})
    end
    return report
end

function M.apply()
    local settings = get_settings()
    local preview_path = preview_manifest_path()
    if settings.rename.require_preview ~= false and vim.fn.filereadable(preview_path) == 0 then
        log.warn("Run :Vault taxonomy preview before apply")
        return nil
    end

    local plan = read_manifest(preview_path)
    if not plan then
        log.error("No taxonomy preview plan found")
        return nil
    end
    if plan.root ~= config.options.root then
        log.error("Preview plan root mismatch; run :Vault taxonomy preview again")
        return nil
    end
    if not plan.moves or #plan.moves == 0 then
        log.info("No taxonomy renames to apply")
        return nil
    end

    local ok, report = pcall(apply_moves, plan.moves, {
        update_links = settings.rename.update_links ~= false,
        chunk_size = settings.rename.chunk_size or 25,
    })
    if not ok then
        log.error("Taxonomy apply failed: %s", tostring(report))
        return nil
    end

    local applied = {
        applied_at = os.date("!%Y-%m-%dT%H:%M:%SZ"),
        root = config.options.root,
        field = settings.field,
        renames = report.renames,
        patched_files = report.patched_files,
    }
    write_manifest(last_apply_manifest_path(), applied)
    log.info("Taxonomy apply: %d renamed, %d files patched", report.moved or 0, report.patched_files or 0)
    return report
end

function M.undo_last()
    local settings = get_settings()
    local applied = read_manifest(last_apply_manifest_path())
    if not applied or not applied.renames or #applied.renames == 0 then
        log.warn("No taxonomy apply manifest to undo")
        return nil
    end
    if applied.root ~= config.options.root then
        log.error("Last taxonomy apply root mismatch")
        return nil
    end

    local reversed = {}
    for idx = #applied.renames, 1, -1 do
        local rename = applied.renames[idx]
        table.insert(reversed, {
            from = rename.new_path,
            to = rename.old_path,
        })
    end

    local ok, report = pcall(apply_moves, reversed, {
        update_links = settings.rename.update_links ~= false,
        chunk_size = settings.rename.chunk_size or 25,
    })
    if not ok then
        log.error("Taxonomy undo failed: %s", tostring(report))
        return nil
    end

    log.info("Taxonomy undo: %d renamed, %d files patched", report.moved or 0, report.patched_files or 0)
    return report
end

M._get_settings = get_settings
M._normalize_kind = normalize_kind
M._inspect_note = inspect_note
M._preview_manifest_path = preview_manifest_path
M._last_apply_manifest_path = last_apply_manifest_path

return M
