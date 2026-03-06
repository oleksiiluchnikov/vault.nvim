--- Vault Frontmatter Type Checker
---
--- Infers schemas from template files and validates note frontmatter.
--- Templates are the only source of truth — no JSON Schema, no separate config.
---
--- Resolution chain:
---   note categories → category note → template field → Templates/*.md → schema
---
--- ## Public API
---
--- - `setup(opts)` — enable on-save diagnostics (off by default)
--- - `diagnose_buffer(bufnr)` — validate a single buffer, set vim.diagnostic
--- - `doctor()` — vault-wide scan, returns report
--- - `doctor_fix()` — auto-fix known patterns (e.g., wikilink wrapping)
--- - `clear_cache()` — invalidate cached schemas (after template edits)
---
--- ## Architecture
---
--- ```
--- init.lua          ← you are here (public API facade)
--- ├── infer.lua     ← pure Lua type inference from template defaults
--- ├── validate.lua  ← pure Lua field validation
--- ├── resolve.lua   ← template resolution chain
--- ├── frontmatter.lua ← raw frontmatter reader
--- └── report.lua    ← Neovim integration (diagnostics, doctor, autocmds)
--- ```

local report = require("vault.typecheck.report")

---@class vault.typecheck.SetupOpts
---@field on_save? boolean -- enable BufWritePost diagnostics (default: false)

local M = {}

--- Set up the vault type checker.
--- When `on_save` is true, validates `.md` files on every save and shows
--- diagnostics in the gutter. Off by default (ADHD-friendly).
---@param opts? vault.typecheck.SetupOpts
function M.setup(opts)
    opts = opts or {}
    -- Store in config
    local config = require("vault.config")
    if not config.options.typecheck then
        config.options.typecheck = {}
    end
    config.options.typecheck.on_save = opts.on_save or false
    -- Set up autocmds (always — handles template cache invalidation too)
    report.setup_autocmds()
end

--- Validate a buffer and set Neovim diagnostics.
---@param bufnr integer
function M.diagnose_buffer(bufnr)
    report.diagnose_buffer(bufnr)
end

--- Run vault-wide type check. Returns a report.
---@return vault.typecheck.DoctorReport
function M.doctor()
    return report.doctor()
end

--- Run vault-wide type check with auto-fix for known patterns.
---@return vault.typecheck.DoctorReport -- report after fixes applied
function M.doctor_fix()
    return report.doctor_fix()
end

--- Clear the schema cache. Call after editing template files.
function M.clear_cache()
    report.clear_cache()
end

return M
