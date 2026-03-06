--- Neovim reporter for vault frontmatter type checking.
--- Wires infer + validate + resolve together.
--- This is the ONLY module with vim.* dependencies.

local infer = require("vault.typecheck.infer")
local validate = require("vault.typecheck.validate")
local resolve = require("vault.typecheck.resolve")
local fm = require("vault.typecheck.frontmatter")

local M = {}

local DIAG_SOURCE = "vault-typecheck"
local ns_id ---@type integer|nil

---@return integer
local function get_ns()
    if not ns_id then
        ns_id = vim.api.nvim_create_namespace(DIAG_SOURCE)
    end
    return ns_id
end

---@return string
local function vault_root()
    return vim.fn.resolve(vim.fn.expand(require("vault.config").options.root))
end

-- ── Schema cache ─────────────────────────────────────────────────────

---@type table<string, vault.typecheck.Schema>
local schema_cache = {}

--- Load or return cached schema for a template path.
---@param template_path string
---@return vault.typecheck.Schema
local function get_schema(template_path)
    if not schema_cache[template_path] then
        schema_cache[template_path] = infer.load_schema(template_path, fm.read_raw_frontmatter)
    end
    return schema_cache[template_path]
end

--- Clear the schema cache. Call after template edits.
function M.clear_cache()
    schema_cache = {}
end

-- ── Wikilink target checker ──────────────────────────────────────────

--- Check if a wikilink target exists in the vault.
---@param wikilink string -- e.g. "[[Status - Backlog]]"
---@return string|nil -- error message if target not found
function M.check_wikilink_target(wikilink)
    local inner = wikilink:match("^%[%[(.-)%]%]$")
    if not inner then return "invalid wikilink syntax" end

    local root = vault_root()
    local search_paths = {
        root .. "/" .. inner .. ".md",
        root .. "/References/" .. inner .. ".md",
        root .. "/Categories/" .. inner .. ".md",
        root .. "/Tasks/" .. inner .. ".md",
        root .. "/Templates/" .. inner .. ".md",
        root .. "/Clippings/" .. inner .. ".md",
    }

    for _, p in ipairs(search_paths) do
        if vim.fn.filereadable(p) == 1 then return nil end
    end

    -- Glob fallback for notes in any subfolder
    local glob = vim.fn.glob(root .. "/**/" .. vim.fn.fnameescape(inner) .. ".md", false, true)
    if #glob > 0 then return nil end

    return "dangling wikilink: [[" .. inner .. "]] (target not found)"
end

-- ── Single-file validation ───────────────────────────────────────────

--- Validate a single note file against its template-derived schema.
---@param path string -- absolute path to the .md file
---@return vault.typecheck.Error[] errors
---@return string|nil resolve_error -- non-nil if note is untyped
function M.validate_file(path)
    local raw = fm.read_raw_frontmatter(path)
    local cats = raw.categories
    if type(cats) == "string" then cats = { cats } end

    local root = vault_root()
    local template_path, resolve_err = resolve.resolve(cats, root)
    if not template_path then
        return {}, resolve_err
    end

    local schema = get_schema(template_path)
    local line_map = fm.build_line_map(path)

    local errors = validate.validate({
        schema = schema,
        raw_fields = raw,
        line_map = line_map,
        check_wikilink = M.check_wikilink_target,
    })

    return errors, nil
end

-- ── Buffer diagnostics ───────────────────────────────────────────────

--- Validate a buffer and set Neovim diagnostics.
---@param bufnr integer
function M.diagnose_buffer(bufnr)
    local path = vim.api.nvim_buf_get_name(bufnr)
    if not path:match("%.md$") then return end

    local errors, resolve_err = M.validate_file(path)
    ---@type vim.Diagnostic[]
    local diagnostics = {}

    if resolve_err then
        table.insert(diagnostics, {
            lnum = 0,
            col = 0,
            end_col = 0,
            severity = vim.diagnostic.severity.HINT,
            message = resolve_err,
            source = DIAG_SOURCE,
        })
    end

    for _, err in ipairs(errors) do
        table.insert(diagnostics, {
            lnum = err.lnum or 0,
            col = 0,
            end_col = 0,
            severity = vim.diagnostic.severity.ERROR,
            message = err.message,
            source = DIAG_SOURCE,
        })
    end

    vim.diagnostic.set(get_ns(), bufnr, diagnostics)
end

-- ── Vault-wide doctor ────────────────────────────────────────────────

---@class vault.typecheck.DoctorReport
---@field scanned integer
---@field errors vault.typecheck.Error[]
---@field untyped string[]
---@field error_files table<string, boolean> -- unique file paths with errors

---@return vault.typecheck.DoctorReport
function M.doctor()
    local root = vault_root()
    local all_md = vim.fn.glob(root .. "/**/*.md", false, true)
    ---@type vault.typecheck.DoctorReport
    local report = { scanned = 0, errors = {}, untyped = {}, error_files = {} }

    for _, path in ipairs(all_md) do
        -- Skip templates and READMEs
        if path:match("/Templates/") or path:match("README%.md$") then
            goto skip
        end
        report.scanned = report.scanned + 1

        local errors, resolve_err = M.validate_file(path)
        if resolve_err then
            table.insert(report.untyped, path)
        end
        for _, err in ipairs(errors) do
            err.path = path
            table.insert(report.errors, err)
            report.error_files[path] = true
        end

        ::skip::
    end

    return report
end

--- Auto-fix known patterns: wrap plain-text wikilink fields.
---@return vault.typecheck.DoctorReport -- report after fixes applied
function M.doctor_fix()
    local root = vault_root()
    local shared = require("vault.bases.views.shared")
    local all_md = vim.fn.glob(root .. "/**/*.md", false, true)
    local fixed = 0

    for _, path in ipairs(all_md) do
        if path:match("/Templates/") or path:match("README%.md$") then
            goto skip
        end

        local raw = fm.read_raw_frontmatter(path)
        local cats = raw.categories
        if type(cats) == "string" then cats = { cats } end

        local template_path, _ = resolve.resolve(cats, root)
        if not template_path then goto skip end

        local schema = get_schema(template_path)
        local changes = {}

        for field_name, field_type in pairs(schema.fields) do
            if field_type.kind == "wikilink" then
                local value = raw[field_name]
                if type(value) == "string"
                    and value ~= ""
                    and not value:match("^%[%[.-%]%]$")
                then
                    -- Wrap in wikilink brackets
                    local prefix = field_type.prefix or ""
                    if prefix ~= "" and not value:match("^" .. vim.pesc(prefix)) then
                        value = prefix .. value
                    end
                    changes[field_name] = "[[" .. value .. "]]"
                end
            end
        end

        if next(changes) then
            shared.set_frontmatter_fields(path, changes)
            fixed = fixed + 1
        end

        ::skip::
    end

    -- Re-run doctor after fixes
    local report = M.doctor()
    return report
end

-- ── Autocmd setup ────────────────────────────────────────────────────

--- Set up BufWritePost autocmd for on-save diagnostics.
--- Also invalidates schema cache when a template is saved.
function M.setup_autocmds()
    local group = vim.api.nvim_create_augroup("vault-typecheck", { clear = true })

    -- On-save diagnostics (only when enabled)
    vim.api.nvim_create_autocmd("BufWritePost", {
        pattern = "*.md",
        group = group,
        callback = function(ev)
            local path = vim.api.nvim_buf_get_name(ev.buf)
            -- Invalidate cache if a template was saved
            if path:match("/Templates/") then
                M.clear_cache()
                return
            end
            -- Only diagnose if on_save is enabled
            local cfg = require("vault.config").options.typecheck or {}
            if cfg.on_save then
                M.diagnose_buffer(ev.buf)
            end
        end,
    })
end

return M
