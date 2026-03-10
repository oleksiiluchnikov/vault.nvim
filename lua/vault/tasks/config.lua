local M = {}

local LEGACY_PRIORITY_ORDER = {
    "Priority - Critical",
    "Priority - High",
    "Priority - Medium",
    "Priority - Low",
}

local LEGACY_COMPLETED_STATUSES = {
    "Status - Done",
    "Status - Failed",
    "Status - Deprecated",
    "Status - Archived",
}

local LEGACY_ALIASES = {
    backlog = "Status - Backlog",
    todo = "Status - Todo",
    ["in-progress"] = "Status - In-Progress",
    ["inprogress"] = "Status - In-Progress",
    ["in-review"] = "Status - In-Review",
    ["inreview"] = "Status - In-Review",
    done = "Status - Done",
    failed = "Status - Failed",
    deprecated = "Status - Deprecated",
    archived = "Status - Archived",
}

local LEGACY_TRANSITIONS = {
    ["Status - Backlog"] = { ["Status - Todo"] = true, ["Status - Archived"] = true },
    ["Status - Todo"] = { ["Status - In-Progress"] = true, ["Status - Archived"] = true },
    ["Status - In-Progress"] = {
        ["Status - In-Review"] = true,
        ["Status - Deprecated"] = true,
        ["Status - Archived"] = true,
    },
    ["Status - In-Review"] = {
        ["Status - Done"] = true,
        ["Status - Failed"] = true,
        ["Status - Archived"] = true,
    },
    ["Status - Done"] = { ["Status - Archived"] = true },
    ["Status - Failed"] = { ["Status - Archived"] = true },
    ["Status - Deprecated"] = { ["Status - Archived"] = true },
    ["Status - Archived"] = {},
}

---@class vault.TasksConfig
---@field dir? string
---@field fields? { status?: string, priority?: string, blocked_by?: string }
---@field defaults? { status?: string, executor?: string, category?: string, priority?: string }
---@field status_order? string[]
---@field priority_order? string[]
---@field completed_statuses? string[]
---@field aliases? table<string, string>
---@field transitions? table<string, table<string, true>>

local function legacy_to_modern(task_notes)
    task_notes = task_notes or {}
    return {
        dir = task_notes.dir,
        fields = {
            status = task_notes.status_field,
            priority = task_notes.priority_field,
            blocked_by = task_notes.blocked_by_field,
        },
        defaults = {
            status = task_notes.default_status,
            executor = task_notes.default_executor,
            category = task_notes.default_category,
            priority = task_notes.default_priority,
        },
        status_order = task_notes.status_order,
        priority_order = LEGACY_PRIORITY_ORDER,
        completed_statuses = LEGACY_COMPLETED_STATUSES,
        aliases = LEGACY_ALIASES,
        transitions = LEGACY_TRANSITIONS,
    }
end

---@param cfg vault.TasksConfig
---@return vault.TasksConfig
local function with_legacy_compat(cfg)
    cfg.fields = cfg.fields or {}
    cfg.defaults = cfg.defaults or {}
    cfg.status_field = cfg.status_field or cfg.fields.status or "status"
    cfg.priority_field = cfg.priority_field or cfg.fields.priority or "priority"
    cfg.blocked_by_field = cfg.blocked_by_field or cfg.fields.blocked_by or "blocked_by"
    cfg.default_status = cfg.default_status or cfg.defaults.status or "[[Status - Backlog]]"
    cfg.default_executor = cfg.default_executor or cfg.defaults.executor or "[[Executor - Human]]"
    cfg.default_category = cfg.default_category or cfg.defaults.category or "[[Category - Green Task]]"
    cfg.default_priority = cfg.default_priority or cfg.defaults.priority or "[[Priority - Medium]]"
    return cfg
end

--- @return vault.TasksConfig
function M.get()
    local options = require("vault.config").options
    local base = legacy_to_modern(options.task_notes)
    local modern = type(options.tasks) == "table" and options.tasks or {}
    local merged = vim.tbl_deep_extend("force", base, modern)
    return with_legacy_compat(merged)
end

--- @return string
function M.tasks_dir_rel()
    local cfg = M.get()
    return cfg.dir or "Tasks"
end

return M
