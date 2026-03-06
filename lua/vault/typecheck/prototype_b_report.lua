--- Prototype B — Module 3: Reporter
--- Surfaces validation errors as Neovim diagnostics and doctor reports.
--- THROWAWAY — reference only, will not ship as-is.

local infer = require("vault.typecheck.prototype_b_infer")
local validate = require("vault.typecheck.prototype_b_validate")

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

local shared = require("vault.bases.views.shared")

-- ── Frontmatter reading (raw, preserving types) ─────────────────────

---@param path string
---@return table<string, any>
local function read_raw_frontmatter(path)
    ---@type table<string, any>
    local fields = {}
    local ok, lines = pcall(vim.fn.readfile, path, "", 50)
    if not ok then return fields end
    if not lines[1] or not lines[1]:match("^%-%-%-") then return fields end

    local current_key = nil ---@type string|nil
    local current_list = nil ---@type string[]|nil
    for i = 2, #lines do
        if lines[i]:match("^%-%-%-") then break end
        local list_item = lines[i]:match("^%s+%-%s+(.+)")
        if list_item and current_key and current_list then
            list_item = list_item:gsub('^"(.*)"$', "%1"):gsub("^'(.*)'$", "%1")
            table.insert(current_list, list_item)
        else
            local key, value = lines[i]:match("^([%w_%-]+):%s*(.*)")
            if key then
                if current_key and current_list then
                    fields[current_key] = current_list
                end
                current_key = key
                current_list = nil
                value = vim.trim(value or "")
                if value == "" then
                    current_list = {}
                elseif value:match("^%[") and value:match("%]$") then
                    local items = {}
                    local inner = value:match("^%[(.*)%]$") or ""
                    for item in inner:gmatch("[^,]+") do
                        item = vim.trim(item)
                        item = item:gsub('^"(.*)"$', "%1"):gsub("^'(.*)'$", "%1")
                        if item ~= "" then table.insert(items, item) end
                    end
                    fields[key] = items
                    current_key = nil
                else
                    local num = tonumber(value)
                    if num and not value:match("[\"']") then
                        fields[key] = num
                        current_key = nil
                    else
                        value = value:gsub('^"(.*)"$', "%1"):gsub("^'(.*)'$", "%1")
                        fields[key] = value
                        current_key = nil
                    end
                end
            end
        end
    end
    if current_key and current_list then
        fields[current_key] = current_list
    end
    return fields
end

-- ── Template resolution ──────────────────────────────────────────────

---@param categories string[]|nil
---@return string|nil template_path, string|nil error
local function resolve_template(categories)
    if not categories or #categories == 0 then
        return nil, "no categories field"
    end
    if #categories > 1 then
        return nil, "multiple categories not supported (got " .. #categories .. ")"
    end

    local cat_name = categories[1]:match("^%[%[(.-)%]%]$") or categories[1]
    local root = vault_root()

    ---@type string|nil
    local cat_path
    for _, p in ipairs({
        root .. "/" .. cat_name .. ".md",
        root .. "/Categories/" .. cat_name .. ".md",
        root .. "/References/" .. cat_name .. ".md",
    }) do
        if vim.fn.filereadable(p) == 1 then
            cat_path = p
            break
        end
    end

    if not cat_path then
        return nil, "category note not found: " .. cat_name
    end

    local fields = shared.read_frontmatter_fields(cat_path, { "template" })
    local tpl = fields.template
    if not tpl or tpl == "" then
        return nil, "category '" .. cat_name .. "' has no template field"
    end

    local tpl_path = root .. "/Templates/" .. tpl .. ".md"
    if vim.fn.filereadable(tpl_path) == 0 then
        return nil, "template not found: " .. tpl_path
    end

    return tpl_path, nil
end

-- ── Wikilink target checker ──────────────────────────────────────────

---@param wikilink string
---@return string|nil
local function check_wikilink_target(wikilink)
    local inner = wikilink:match("^%[%[(.-)%]%]$")
    if not inner then return "invalid wikilink syntax" end

    local root = vault_root()
    for _, p in ipairs({
        root .. "/" .. inner .. ".md",
        root .. "/References/" .. inner .. ".md",
        root .. "/Categories/" .. inner .. ".md",
        root .. "/Tasks/" .. inner .. ".md",
    }) do
        if vim.fn.filereadable(p) == 1 then return nil end
    end

    local glob = vim.fn.glob(root .. "/**/" .. inner .. ".md", false, true)
    if #glob > 0 then return nil end

    return "dangling wikilink: [[" .. inner .. "]] (target not found)"
end

-- ── Line map builder ─────────────────────────────────────────────────

---@param path string
---@return table<string, integer>
local function build_line_map(path)
    ---@type table<string, integer>
    local map = {}
    local ok, lines = pcall(vim.fn.readfile, path, "", 50)
    if not ok then return map end
    if not lines[1] or not lines[1]:match("^%-%-%-") then return map end
    for i = 2, #lines do
        if lines[i]:match("^%-%-%-") then break end
        local key = lines[i]:match("^([%w_%-]+):")
        if key then map[key] = i - 1 end
    end
    return map
end

-- ── Schema cache ─────────────────────────────────────────────────────

---@type table<string, vault.typecheck.Schema>
local schema_cache = {}

-- ── Public API ───────────────────────────────────────────────────────

---@param bufnr integer
function M.diagnose_buffer(bufnr)
    local path = vim.api.nvim_buf_get_name(bufnr)
    if not path:match("%.md$") then return end

    local raw = read_raw_frontmatter(path)
    local cats = raw.categories
    if type(cats) == "string" then cats = { cats } end

    local tpl_path, resolve_err = resolve_template(cats)
    ---@type vim.Diagnostic[]
    local diagnostics = {}

    if not tpl_path then
        table.insert(diagnostics, {
            lnum = 0, col = 0, end_col = 0,
            severity = vim.diagnostic.severity.HINT,
            message = resolve_err or "untyped note",
            source = DIAG_SOURCE,
        })
        vim.diagnostic.set(get_ns(), bufnr, diagnostics)
        return
    end

    if not schema_cache[tpl_path] then
        schema_cache[tpl_path] = infer.load_schema(tpl_path, read_raw_frontmatter)
    end

    local errors = validate.validate({
        schema = schema_cache[tpl_path],
        raw_fields = raw,
        line_map = build_line_map(path),
        check_wikilink = check_wikilink_target,
    })

    for _, err in ipairs(errors) do
        table.insert(diagnostics, {
            lnum = err.lnum or 0, col = 0, end_col = 0,
            severity = vim.diagnostic.severity.ERROR,
            message = err.message,
            source = DIAG_SOURCE,
        })
    end

    vim.diagnostic.set(get_ns(), bufnr, diagnostics)
end

---@class vault.typecheck.DoctorReport
---@field scanned integer
---@field errors vault.typecheck.Error[]
---@field untyped string[]

---@return vault.typecheck.DoctorReport
function M.doctor()
    local root = vault_root()
    local all_md = vim.fn.glob(root .. "/**/*.md", false, true)
    ---@type vault.typecheck.DoctorReport
    local report = { scanned = 0, errors = {}, untyped = {} }

    for _, path in ipairs(all_md) do
        if path:match("/Templates/") or path:match("README%.md$") then goto skip end
        report.scanned = report.scanned + 1

        local raw = read_raw_frontmatter(path)
        local cats = raw.categories
        if type(cats) == "string" then cats = { cats } end

        local tpl_path, resolve_err = resolve_template(cats)
        if not tpl_path then
            table.insert(report.untyped, path)
            goto skip
        end

        if not schema_cache[tpl_path] then
            schema_cache[tpl_path] = infer.load_schema(tpl_path, read_raw_frontmatter)
        end

        local errors = validate.validate({
            schema = schema_cache[tpl_path],
            raw_fields = raw,
            line_map = build_line_map(path),
            check_wikilink = check_wikilink_target,
        })

        for _, err in ipairs(errors) do
            err.path = path
            table.insert(report.errors, err)
        end

        ::skip::
    end

    return report
end

---@param opts? { on_save?: boolean }
function M.setup(opts)
    opts = opts or {}
    if opts.on_save then
        vim.api.nvim_create_autocmd("BufWritePost", {
            pattern = "*.md",
            callback = function(ev) M.diagnose_buffer(ev.buf) end,
            group = vim.api.nvim_create_augroup("vault-typecheck", { clear = true }),
        })
    end
end

function M.clear_cache()
    schema_cache = {}
end

return M
