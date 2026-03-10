local M = {}

local LEGACY_DEFAULT_COLUMNS = { "slug", "title", "status", "tags" }
local LEGACY_ROW_HL = {
    { match = { status = "done" }, hl = "VaultRowDone" },
    { match = { status = "archived" }, hl = "VaultRowDone" },
    { match = { tags = {} }, hl = "VaultRowUntagged" },
}

local function with_legacy_compat(cfg)
    cfg.columns = cfg.columns or cfg.default_columns
    return cfg
end

---@class vault.GridViewConfig
---@field default_columns string[]
---@field identity_mode "conceal"|"extmark"|"visible"
---@field delete_hard_cap integer
---@field create_hard_cap integer
---@field row_hl vault.RowHlRule[]|fun(record: table, row_idx: integer): string|nil

--- @return vault.GridViewConfig
function M.get()
    local options = require("vault.config").options
    local cfg = options.views and options.views.grid or {}
    local legacy = options.process or {}

    return with_legacy_compat({
        default_columns = cfg.default_columns or legacy.columns or LEGACY_DEFAULT_COLUMNS,
        identity_mode = cfg.identity_mode or legacy.identity_mode or "conceal",
        delete_hard_cap = cfg.delete_hard_cap or 100,
        create_hard_cap = cfg.create_hard_cap or 100,
        row_hl = cfg.row_hl or legacy.row_hl or LEGACY_ROW_HL,
    })
end

return M
