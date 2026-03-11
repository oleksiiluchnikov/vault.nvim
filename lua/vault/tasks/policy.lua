local tasks_config = require("vault.tasks.config")

local M = {}

--- @param value string
--- @return string
function M.trim(value)
    return (value or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

--- @param value string
--- @return string
function M.unwrap_link(value)
    local out = M.trim(value)
    out = out:gsub("^%[%[(.-)%]%]$", "%1")
    return M.trim(out)
end

--- @return table<string, integer>
function M.status_order_map()
    local map = {}
    for idx, status in ipairs(tasks_config.get().status_order or {}) do
        map[status] = idx
    end
    return map
end

--- @return table<string, integer>
function M.priority_order_map()
    local map = {}
    for idx, priority in ipairs(tasks_config.get().priority_order or {}) do
        map[priority] = idx
    end
    return map
end

--- @return table<string, true>
function M.completed_status_set()
    local map = {}
    for _, status in ipairs(tasks_config.get().completed_statuses or {}) do
        map[status] = true
    end
    return map
end

--- @return table<string, table<string, true>>
function M.transition_map()
    return tasks_config.get().transitions or {}
end

--- @param value string
--- @return string
function M.normalize_status(value)
    local candidate = M.unwrap_link(value)
    if M.status_order_map()[candidate] then
        return candidate
    end
    local lowered = candidate:lower():gsub("_", "-")
    local aliases = tasks_config.get().aliases or {}
    return aliases[lowered] or candidate
end

--- @param value string
--- @return string
function M.normalize_priority(value)
    local candidate = M.unwrap_link(value)
    if M.priority_order_map()[candidate] then
        return candidate
    end
    return "Priority - Medium"
end

--- @return string[]
function M.statuses()
    return vim.deepcopy(tasks_config.get().status_order or {})
end

--- @param status string
--- @return string
function M.status_link(status)
    return string.format("[[%s]]", status)
end

return M
