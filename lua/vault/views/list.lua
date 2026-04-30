local M = {}

local log = require("vault.log").scope("bases.views.list")
local shared = require("vault.views.shared")

---@class vault.ListRecord
---@field slug vault.slug
---@field _path vault.path

---@class vault.ListOpenOpts
---@field notes? vault.Notes
---@field columns? string[]
---@field filter_desc? string
---@field base? vault.Base
---@field reload_notes? fun(): table

---@class vault.ListEditorState
---@field list table
---@field note_paths table<vault.slug, vault.path>
---@field base? vault.Base
---@field reload_notes? fun(): table
---@field filter_desc string
---@field columns string[]
---@field visible_columns string[]
---@field display_names table<string, string>
---@field formula_cols string[]

---@type table<integer, vault.ListEditorState>
local buf_states = {}

local function get_List()
    return require("vimtable.views.list").List
end

---@param st vault.ListEditorState
---@param rec vault.ListRecord
---@param new_status vault.bases.views.FrontmatterValue|nil
---@param done fun(err: string|nil)
local function on_toggle(st, rec, new_status, done)
    local path = st.note_paths[rec.slug]
    if not path then
        done("missing path for slug " .. tostring(rec.slug))
        return
    end
    if new_status == nil then
        shared.set_frontmatter_fields(path, { status = "" })
    else
        shared.set_frontmatter_fields(path, { status = new_status })
    end
    done(nil)
end

---@param st vault.ListEditorState
---@return fun(diff: vimtable.Diff, done: fun(err: string|nil))
local function make_on_save(st)
    return function(diff, done)
        if #diff.creates > 0 or #diff.deletes > 0 then
            log.warn("List save ignores creates/deletes for safety (updates only)")
        end

        for _, upd in ipairs(diff.updates) do
            local path = st.note_paths[upd.id]
            if path then
                local fields = {}
                for k, v in pairs(upd.fields) do
                    if k ~= "slug" and not k:match("^file%.") and not k:match("^formula%.") then
                        fields[k] = v
                    end
                end
                if next(fields) then
                    shared.set_frontmatter_fields(path, fields)
                end
            end
        end

        done(nil)
        M.reload(st.list:bufnr())
    end
end

---@param bufnr integer
function M.reload(bufnr)
    local st = buf_states[bufnr]
    if not st or not st.list then
        return
    end
    local notes_map = {}
    if type(st.reload_notes) == "function" then
        local ok, refreshed = pcall(st.reload_notes)
        if ok and refreshed and refreshed.map then
            notes_map = refreshed.map
            if st.base and st.base.has_filters and st.base:has_filters() then
                notes_map = st.base:match_notes(notes_map)
            end
        else
            log.warn("List reload filter refresh failed; keeping current note set")
        end
    end

    if not next(notes_map) then
        local Note = require("vault.notes.note")
        local dead = {}
        for slug, path in pairs(st.note_paths) do
            if vim.fn.filereadable(path) == 1 then
                local ok, note = pcall(Note, path)
                if ok and note then
                    notes_map[slug] = note
                end
            else
                dead[#dead + 1] = slug
            end
        end
        for _, slug in ipairs(dead) do
            st.note_paths[slug] = nil
        end
    end

    local grid = require("vault.views.grid")
    local records = grid._build_records(notes_map, st.columns, st.base)
    st.note_paths = {}
    for _, rec in ipairs(records) do
        st.note_paths[rec.slug] = rec._path
    end
    st.list:reload(records)
end

---@param opts? vault.ListOpenOpts
function M.open(opts)
    opts = opts or {}
    local grid = require("vault.views.grid")
    local base = opts.base

    local columns, display_names, formula_cols, visible_columns
    local filter_desc = opts.filter_desc or "all notes"
    if base then
        local vis
        columns, display_names, formula_cols, vis = grid._columns_from_base(base)
        visible_columns = opts.columns or vis
        filter_desc = opts.filter_desc or ("base:" .. (base.data.name or "unnamed"))
    else
        local cfg = require("vault.config")
        visible_columns = opts.columns
            or (cfg.options and cfg.options.process and cfg.options.process.columns)
            or { "slug", "title", "status", "tags" }
        for i, c in ipairs(visible_columns) do
            visible_columns[i] = grid._normalize_col(c)
        end
        columns = vim.list_slice(visible_columns, 1)
        if not vim.tbl_contains(columns, "slug") then
            table.insert(columns, 1, "slug")
        end
        display_names = {}
        formula_cols = {}
    end

    for bufnr, s in pairs(buf_states) do
        if vim.api.nvim_buf_is_valid(bufnr) then
            if s.filter_desc == filter_desc then
                vim.api.nvim_set_current_buf(bufnr)
                log.info("Switched to existing list process buffer (%s)", filter_desc)
                return
            end
        else
            buf_states[bufnr] = nil
        end
    end

    local notes = opts.notes or require("vault.notes")()
    local notes_map = notes.map or {}
    if base and base:has_filters() then
        notes_map = base:match_notes(notes_map)
    end
    if not next(notes_map) then
        log.info("No notes match filter")
        return
    end

    local records = grid._build_records(notes_map, columns, base)
    local list_columns = grid._build_grid_columns(visible_columns, display_names, formula_cols)
    for _, col in ipairs(list_columns) do
        if col.name == "status" then
            col.format = function(value)
                return tostring(value) == "done" and "☑" or "☐"
            end
            col.parse = function(text)
                local t = vim.trim(text)
                if t == "☑" then
                    return "done"
                end
                if t == "☐" or t == "" then
                    return nil
                end
                return shared.parse_value(t, "status")
            end
            break
        end
    end
    ---@type vault.ListEditorState
    local st = {
        list = nil,
        note_paths = {},
        base = base,
        filter_desc = filter_desc,
        columns = columns,
        visible_columns = visible_columns,
        display_names = display_names,
        formula_cols = formula_cols,
        reload_notes = opts.reload_notes,
    }
    for _, rec in ipairs(records) do
        st.note_paths[rec.slug] = rec._path
    end

    local buf_name = "vault://list-process/" .. filter_desc:gsub("%s+", "-")

    -- Guard against orphaned buffers with the same name (state map can be stale
    -- after hot-reload). Neovim refuses duplicate buffer names with E95.
    for _, b in ipairs(vim.api.nvim_list_bufs()) do
        if vim.api.nvim_buf_is_valid(b) and vim.api.nvim_buf_get_name(b) == buf_name then
            pcall(vim.api.nvim_buf_delete, b, { force = true })
        end
    end

    local List = get_List()
    local list = List.new({
        columns = list_columns,
        records = records,
        id_field = "slug",
        primary_field = vim.tbl_contains(visible_columns, "title") and "title"
            or visible_columns[1],
        status_field = vim.tbl_contains(visible_columns, "status") and "status" or nil,
        status_done_value = "done",
        identity = "conceal",
        empty_cell = shared.get_empty_cell(),
        buf_name = buf_name,
        filetype = "vault_process",
        on_save = make_on_save(st),
        classify = grid._make_classify({
            note_paths = st.note_paths,
            visible_columns = st.visible_columns,
            slug_hidden = true,
        }),
        on_toggle = function(rec, new_status, done)
            on_toggle(st, rec, new_status, done)
        end,
        on_refresh = function(l)
            M.reload(l:bufnr())
        end,
        on_filter_request = function(l)
            local s = buf_states[l:bufnr()]
            if not s then
                return
            end
            require("vault.bases.views.filter_picker").open(l, s.visible_columns)
        end,
        hl = {
            group_header = "VaultProcessHeader",
            status_done = "Comment",
        },
    })
    st.list = list

    local bufnr = list:bufnr()
    buf_states[bufnr] = st
    list:attach()

    vim.b[bufnr].formatter_skip_buf = true
    vim.b[bufnr].autoformat = false

    -- x, <C-s>, <C-r>, gs, gf, gF handled by List._setup_shared_keymaps

    -- Help legend
    require("vimtable.help").setup_keymap(bufnr, {
        { group = "Toggle", lhs = "x", desc = "Toggle status (done / undone)" },
        { group = "Save", lhs = "<C-s>", desc = "Save all edits" },
        { group = "Refresh", lhs = "<C-r>", desc = "Reload notes from disk" },
        { group = "Sort", lhs = "gs", desc = "Cycle sort" },
        { group = "Filter", lhs = "gf", desc = "Open filter picker" },
        { lhs = "gF", desc = "Clear all filters" },
        { group = "Help", lhs = "g?", desc = "Toggle this help" },
    })

    vim.api.nvim_create_autocmd("BufWipeout", {
        buffer = bufnr,
        once = true,
        callback = function()
            buf_states[bufnr] = nil
        end,
    })

    log.info("Processing %d notes (%s) [list]", #records, filter_desc)
end

M._buf_states = buf_states

return M
