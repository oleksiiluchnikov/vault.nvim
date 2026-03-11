local log = require("vault.log").scope("tasks.create")
local shared = require("vault.views.shared")
local tasks_config = require("vault.tasks.config")
local paths = require("vault.tasks.paths")
local policy = require("vault.tasks.policy")

local M = {}

--- @return string
function M.timestamp()
    return os.date("%Y%m%d%H%M%S")
end

--- @param name string
--- @return string
function M.sanitize_name(name)
    local out = policy.trim(name)
    out = out:gsub("[\r\n\t]", " ")
    out = out:gsub("[/\\:]", "-")
    out = out:gsub("%s+", " ")
    return policy.trim(out)
end

--- @param name string
--- @param ts string
--- @return string
function M.filename(name, ts)
    return string.format("T-%s %s", ts, M.sanitize_name(name))
end

--- @param name string
--- @param opts table|nil
--- @return string|nil
function M.create(name, opts)
    opts = opts or {}
    local options = tasks_config.get()
    local clean_name = M.sanitize_name(name)
    if clean_name == "" then
        log.warn("Usage: :Vault tasks new <name>")
        return nil
    end
    local ts = M.timestamp()
    local stem = M.filename(clean_name, ts)
    local ext = require("vault.config").options.ext or ".md"
    local dir = paths.tasks_dir_abs()
    if vim.fn.isdirectory(dir) == 0 then
        vim.fn.mkdir(dir, "p")
    end
    local path = string.format("%s/%s%s", dir, stem, ext)
    if vim.fn.filereadable(path) == 1 then
        log.warn("Task already exists: %s", stem)
        return path
    end
    local title = opts.title or clean_name
    local status = opts.status or options.default_status or "[[Status - Backlog]]"
    local executor = opts.executor or options.default_executor or "[[Executor - Human]]"
    local category = opts.category or options.default_category or "[[Category - Green Task]]"
    local priority = opts.priority or options.default_priority or "[[Priority - Medium]]"

    local lines = {
        "---",
        'categories:',
        '  - "[[Tasks]]"',
        'type: "task"',
        'uuid: ""',
        'icon: ""',
        string.format('status: "%s"', status),
        string.format('executor: "%s"', executor),
        string.format('category: "%s"', category),
        string.format('priority: "%s"', priority),
        'feature: ""',
        'project: ""',
        'initiative: ""',
        'blocked_by: []',
        'due: ""',
        'estimation: ""',
        string.format('title: "%s"', title:gsub('"', '\\"')),
        string.format("created: %s", ts),
        string.format("modified: %s", ts),
        "---",
        "",
        string.format("# %s", title),
        "",
        "## Context",
        "",
        "- ",
        "",
        "## Acceptance Criteria",
        "",
        "- [ ] ",
        "",
        "## Notes",
        "",
        "- ",
    }
    local ok, err = shared.atomic_writefile(path, lines)
    if not ok then
        log.error("Failed to create task: %s", tostring(err))
        return nil
    end
    return path
end

return M
