-- lua/vault/bases/views/calendar.lua
-- Calendar view adapter for vault.nvim backed by vimtable.views.calendar.Calendar.
--
-- Renders vault notes on a month-grid calendar, placed by a configurable date
-- field (frontmatter key like "due", "date", "created", or file.ctime/mtime).
--
-- Usage:
--   require("vault.bases.views.calendar").open({ date_field = "due" })
--   require("vault.bases.views.calendar").open({ base = base_obj })

local M = {}

local log = require("vault.log").scope("bases.views.calendar")
local shared = require("vault.bases.views.shared")

-- ─── Lazy imports ─────────────────────────────────────────────────────────────

---@return Calendar
local function get_Calendar()
    return require("vimtable.views.calendar")
end

-- ─── Config ───────────────────────────────────────────────────────────────────

---@return table
local function cal_cfg()
    local ok, cfg = pcall(require, "vault.config")
    return ok and cfg.options and cfg.options.calendar or {}
end

-- ─── Per-calendar state ───────────────────────────────────────────────────────

---@class vault.CalendarState
---@field cal Calendar              Calendar instance
---@field note_paths table<string, string>  slug → absolute path
---@field note_mtimes table<string, integer>  slug → mtime at snapshot time
---@field base? vault.Base
---@field date_field string          Frontmatter key used for date placement
---@field primary_field string       Primary display field (title)
---@field display_fields string[]    All fields used
---@field filter_desc string
---@field notes_map table            Original notes map for refresh
---@field saving boolean

---@type table<integer, vault.CalendarState>
local cal_states = {}

-- ─── Flatten notes to records ─────────────────────────────────────────────────

--- Build flat records from notes map for the calendar view.
---@param notes_map table<string, table>
---@param date_field string
---@param primary_field string
---@param base? vault.Base
---@return table[]  flat records
---@return table<string, string>  slug → path map
---@return table<string, integer>  slug → mtime map
local function flatten_notes(notes_map, date_field, primary_field, base)
    local records = {}
    local paths = {}
    local mtimes = {}

    local all_fields = { date_field, primary_field }
    local skipped = 0

    for slug, note in pairs(notes_map) do
        local ok, rec = pcall(function()
            local path = note.data and note.data.path or note.path
            if not path then return nil end

            local fm = shared.read_frontmatter_fields(path, all_fields)
            local flat = { slug = slug, _path = path }

            -- Title / primary field
            if primary_field == "title" then
                flat.title = fm.title
                    or (note.data and note.data.title)
                    or (slug:match("[^/]+$") or slug)
            else
                flat[primary_field] = fm[primary_field]
            end

            -- Date field
            if date_field == "file.ctime" then
                local t = note.data and note.data.ctime
                flat[date_field] = t and t > 0 and os.date("%Y-%m-%d", t) or nil
            elseif date_field == "file.mtime" then
                local t = note.data and note.data.mtime
                flat[date_field] = t and t > 0 and os.date("%Y-%m-%d", t) or nil
            else
                local v = fm[date_field]
                if v == vim.NIL or type(v) == "userdata" then v = nil end
                -- Normalize date format: extract YYYY-MM-DD from various formats
                if type(v) == "string" then
                    local y, m, d = v:match("^(%d%d%d%d)-(%d%d)-(%d%d)")
                    if y then
                        flat[date_field] = string.format("%s-%s-%s", y, m, d)
                    else
                        -- Try YYYYMMDD format
                        y, m, d = v:match("^(%d%d%d%d)(%d%d)(%d%d)")
                        if y then
                            flat[date_field] = string.format("%s-%s-%s", y, m, d)
                        else
                            flat[date_field] = nil
                        end
                    end
                elseif type(v) == "table" and v._type == "date" then
                    flat[date_field] = os.date("%Y-%m-%d", v.epoch)
                else
                    flat[date_field] = nil
                end
            end

            paths[slug] = path
            mtimes[slug] = shared.get_mtime(path)
            return flat
        end)

        if ok and rec then
            table.insert(records, rec)
        else
            skipped = skipped + 1
        end
    end

    if skipped > 0 then log.warn("%d notes skipped due to parse errors", skipped) end
    table.sort(records, function(a, b) return (a.slug or "") < (b.slug or "") end)
    return records, paths, mtimes
end

-- ─── Build vimtable.Column[] ──────────────────────────────────────────────────

---@param primary_field string
---@param date_field string
---@return vimtable.Column[]
local function build_columns(primary_field, date_field)
    return {
        { name = "slug", readonly = true },
        {
            name = primary_field,
            format = function(value)
                return shared.fmt_value(value, primary_field)
            end,
            parse = function(text)
                return shared.parse_value(text, primary_field)
            end,
        },
        { name = date_field, readonly = true },
    }
end

-- ─── Callback builders ────────────────────────────────────────────────────────

---@param st vault.CalendarState
---@return fun(diff: calendar.Diff, done: fun(err: string|nil))
local function make_on_save(st)
    return function(diff, done)
        st.saving = true
        local n_upd = 0

        -- Process updates (field edits — primary_field changes)
        for _, upd in ipairs(diff.updates) do
            local path = st.note_paths[upd.id]
            if not path then goto upd_continue end
            local safe_path, path_err = shared.validate_path_in_vault(path)
            if not safe_path then
                log.error("SAFETY: Skipping update — %s", path_err)
                goto upd_continue
            end
            -- Mtime check
            local snap_mtime = st.note_mtimes and st.note_mtimes[upd.id] or 0
            if snap_mtime > 0 and shared.get_mtime(safe_path) > snap_mtime then
                log.warn("SAFETY: Skipping %s — file modified externally", upd.id)
                goto upd_continue
            end
            -- Filter internal fields
            local fm_fields = {}
            for col, val in pairs(upd.fields) do
                if not col:match("^_") then
                    fm_fields[col] = val
                end
            end
            if next(fm_fields) then
                shared.set_frontmatter_fields(safe_path, fm_fields)
            end
            n_upd = n_upd + 1
            ::upd_continue::
        end

        local parts = {}
        if n_upd > 0 then table.insert(parts, string.format("%d updated", n_upd)) end
        if #parts == 0 then parts = { "no changes" } end
        log.info("Calendar saved: %s", table.concat(parts, ", "))

        st.saving = false
        done(nil)

        -- Refresh after save
        M.reload(st.cal:bufnr())
    end
end

---@param st vault.CalendarState
---@return fun(record: table, old_date: string, new_date: string, done: fun(err: string|nil))
local function make_on_date_move(st)
    return function(record, old_date, new_date, done)
        local slug = record.slug
        local path = st.note_paths[slug]
        if not path then
            done("Cannot find path for note: " .. tostring(slug))
            return
        end

        local safe_path, path_err = shared.validate_path_in_vault(path)
        if not safe_path then
            done("SAFETY: " .. (path_err or "unknown error"))
            return
        end

        -- Don't allow moving file.ctime/file.mtime
        if st.date_field:match("^file%.") then
            done("Cannot move records with file-level date fields")
            return
        end

        shared.set_frontmatter_field(safe_path, st.date_field, new_date)
        log.info("Calendar date move: %s %s → %s", slug, old_date, new_date)
        done(nil)
    end
end

-- ─── Reload ───────────────────────────────────────────────────────────────────

---@param bufnr integer
function M.reload(bufnr)
    local st = cal_states[bufnr]
    if not st then return end

    -- Rescan notes
    local Note = require("vault.notes.note")
    local notes_map = {}
    local dead_slugs = {}
    for slug, path in pairs(st.note_paths) do
        if vim.fn.filereadable(path) == 1 then
            local ok, note = pcall(Note, path)
            if ok and note then notes_map[slug] = note end
        else
            table.insert(dead_slugs, slug)
        end
    end
    for _, slug in ipairs(dead_slugs) do
        st.note_paths[slug] = nil
        if st.note_mtimes then st.note_mtimes[slug] = nil end
    end

    local records, note_paths, note_mtimes = flatten_notes(
        notes_map, st.date_field, st.primary_field, st.base)
    st.note_paths = note_paths
    st.note_mtimes = note_mtimes
    st.notes_map = notes_map

    st.cal:reload(records)
end

-- ─── Base calendar view parsing ───────────────────────────────────────────────

--- Find the first calendar view in a base's views array.
---@param base vault.Base
---@return table|nil  The calendar view definition or nil
local function find_calendar_view(base)
    if not base.data.views then return nil end
    for _, view in ipairs(base.data.views) do
        if view.type == "calendar" then
            return view
        end
    end
    return nil
end

-- ─── Open ─────────────────────────────────────────────────────────────────────

---@class vault.CalendarOpenOpts
---@field notes? vault.Notes        Pre-filtered notes (if nil, scans all)
---@field base? vault.Base           Base definition (for filters + calendar config)
---@field date_field? string         Frontmatter key for calendar placement (default "due")
---@field primary_field? string      Main display field (default "title")
---@field filter_desc? string        Description for logging

---@param opts? vault.CalendarOpenOpts
function M.open(opts)
    opts = opts or {}

    local base = opts.base
    local filter_desc = opts.filter_desc or "all notes"

    -- Merge: command opts > base view > user config > defaults
    local cfg = cal_cfg()
    local base_view = base and find_calendar_view(base) or nil
    local date_field = opts.date_field
        or (base_view and base_view.date_field)
        or cfg.date_field
        or "due"
    local primary_field = opts.primary_field
        or (base_view and base_view.primary_field)
        or cfg.primary_field
        or "title"
    local display_fields = cfg.display_fields
    local first_day = cfg.first_day or 1
    local max_cards = cfg.max_cards_per_cell or 3
    local empty_cell_override = cfg.empty_cell
    local keymap_overrides = cfg.keymaps or {}

    if base then
        filter_desc = opts.filter_desc or ("base:" .. (base.data.name or "unnamed"))
    end

    -- Prevent duplicates
    for bufnr, s in pairs(cal_states) do
        if vim.api.nvim_buf_is_valid(bufnr) then
            if s.filter_desc == filter_desc then
                vim.api.nvim_set_current_buf(bufnr)
                log.info("Switched to existing calendar buffer (%s)", filter_desc)
                return
            end
        else
            cal_states[bufnr] = nil
        end
    end

    -- Get notes
    local notes_map
    if opts.notes then
        notes_map = opts.notes.map or {}
    else
        notes_map = require("vault.notes")().map or {}
    end
    if base and base:has_filters() then
        notes_map = base:match_notes(notes_map)
    end
    if not next(notes_map) then
        log.info("No notes match%s", base and (" base '" .. base.data.name .. "'") or "")
        return
    end

    -- Flatten notes to records
    local records, note_paths, note_mtimes = flatten_notes(
        notes_map, date_field, primary_field, base)

    if #records == 0 then
        log.info("No records after flattening")
        return
    end

    -- Build columns
    local columns = build_columns(primary_field, date_field)

    -- Prepare state
    ---@type vault.CalendarState
    local st = {
        cal = nil, ---@diagnostic disable-line: assign-type-mismatch
        note_paths = note_paths,
        note_mtimes = note_mtimes,
        base = base,
        date_field = date_field,
        primary_field = primary_field,
        display_fields = { primary_field },
        filter_desc = filter_desc,
        notes_map = notes_map,
        saving = false,
    }

    -- Wipe orphan buffer with same name (from previous crash or stale state)
    local buf_name = "vault://calendar/" .. filter_desc:gsub("%s+", "-")
    local existing_bufnr = vim.fn.bufnr(buf_name)
    if existing_bufnr ~= -1 and vim.api.nvim_buf_is_valid(existing_bufnr) then
        pcall(vim.api.nvim_buf_delete, existing_bufnr, { force = true })
        cal_states[existing_bufnr] = nil
    end

    -- Create Calendar
    local Calendar = get_Calendar()
    local cal = Calendar.new({
        columns = columns,
        records = records,
        id_field = "slug",
        date_field = date_field,
        primary_field = primary_field,
        display_fields = display_fields,
        empty_cell = empty_cell_override or shared.get_empty_cell(),
        first_day = first_day,
        max_cards_per_cell = max_cards,
        keymaps = keymap_overrides,
        buf_name = buf_name,
        filetype = "vault_calendar",
        on_save = make_on_save(st),
        on_date_move = make_on_date_move(st),
        on_refresh = function(_cal)
            M.reload(_cal:bufnr())
        end,
        on_filter_request = function(_cal)
            local s = cal_states[_cal:bufnr()]
            if not s then return end
            local picker = require("vault.bases.views.filter_picker")
            picker.open(_cal, s.display_fields)
        end,
        on_record_entry = function(record, _cal)
            local slug = record.slug
            local path = st.note_paths[slug]
            if path then
                _cal:close()
                vim.cmd("edit " .. vim.fn.fnameescape(path))
            else
                log.warn("Cannot find path for note: %s", slug)
            end
        end,
        on_add_row = function(_cal, date_str)
            local config = require("vault.config")
            local timestamp = os.date("%Y%m%d%H%M%S")
            local slug = "note-" .. timestamp
            local path = config.options.root .. "/" .. slug .. config.options.ext

            local fm = { "---" }
            table.insert(fm, "title: " .. shared.yaml_quote(slug))
            if date_str and not date_field:match("^file%.") then
                table.insert(fm, date_field .. ": " .. date_str)
            end
            table.insert(fm, "---")
            table.insert(fm, "")

            local parent = vim.fn.fnamemodify(path, ":h")
            if vim.fn.isdirectory(parent) == 0 then vim.fn.mkdir(parent, "p") end
            local write_ok = shared.atomic_writefile(path, fm)
            if write_ok then
                st.note_paths[slug] = path
                st.note_mtimes[slug] = shared.get_mtime(path)
                log.info("Created note: %s (date: %s)", slug, date_str or "none")
                M.reload(_cal:bufnr())
            else
                log.error("Failed to create note: %s", path)
            end
        end,
        hl = {
            header = "Comment",
            border = "NonText",
            today = "Title",
            weekend = "Special",
            overflow = "WarningMsg",
            out_of_month = "NonText",
        },
    })

    st.cal = cal
    local bufnr = cal:bufnr()
    cal_states[bufnr] = st

    -- Attach to current window
    cal:attach()

    -- Disable auto-formatters
    vim.b[bufnr].formatter_skip_buf = true
    vim.b[bufnr].autoformat = false

    log.info(
        "Calendar: %d notes, date_field='%s', primary='%s' — ]m/[m navigate, H/L move date, <C-s> save",
        #records, date_field, primary_field
    )
end

-- ─── Close all ────────────────────────────────────────────────────────────────

function M.close_all()
    for bufnr, st in pairs(cal_states) do
        if st.cal then
            pcall(st.cal.close, st.cal)
        end
        cal_states[bufnr] = nil
    end
end

-- ─── Debug / test exports ─────────────────────────────────────────────────────

M._cal_states = cal_states
M._flatten_notes = flatten_notes

return M
