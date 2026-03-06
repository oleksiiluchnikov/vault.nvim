local log = require("vault.log").scope("tasks.notes")
local shared = require("vault.bases.views.shared")

local M = {}

---@class vault.TasksNote
---@field path string
---@field stem string
---@field title string
---@field status string
---@field priority string
---@field blocked_by string[]

local STATUS_ORDER = {
    ["Status - Backlog"] = 1,
    ["Status - Todo"] = 2,
    ["Status - In-Progress"] = 3,
    ["Status - In-Review"] = 4,
    ["Status - Done"] = 5,
    ["Status - Failed"] = 6,
    ["Status - Deprecated"] = 7,
    ["Status - Archived"] = 8,
}

local PRIORITY_ORDER = {
    ["Priority - Critical"] = 1,
    ["Priority - High"] = 2,
    ["Priority - Medium"] = 3,
    ["Priority - Low"] = 4,
}

local COMPLETED_STATUS = {
    ["Status - Done"] = true,
    ["Status - Failed"] = true,
    ["Status - Deprecated"] = true,
    ["Status - Archived"] = true,
}

local VALID_TRANSITIONS = {
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

---@return table
local function cfg()
    local options = require("vault.config").options
    return options.task_notes or {}
end

---@param value string
---@return string
local function trim(value)
    return (value or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

---@param value string
---@return string
local function unwrap_link(value)
    local out = trim(value)
    out = out:gsub("^%[%[(.-)%]%]$", "%1")
    return trim(out)
end

---@param value string
---@return string
local function normalize_status(value)
    local candidate = unwrap_link(value)
    if STATUS_ORDER[candidate] then
        return candidate
    end
    local lowered = candidate:lower():gsub("_", "-")
    local aliases = {
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
    return aliases[lowered] or candidate
end

---@param value string
---@return string
local function normalize_priority(value)
    local candidate = unwrap_link(value)
    if PRIORITY_ORDER[candidate] then
        return candidate
    end
    return "Priority - Medium"
end

---@return string
local function vault_root()
    local root = require("vault.config").options.root
    return vim.fn.resolve(vim.fn.expand(root))
end

---@return string
function M.tasks_dir_rel()
    return cfg().dir or "Tasks"
end

---@return string
function M.tasks_dir_abs()
    return vault_root() .. "/" .. M.tasks_dir_rel()
end

---@return string[]
function M.statuses()
    return {
        "Status - Backlog",
        "Status - Todo",
        "Status - In-Progress",
        "Status - In-Review",
        "Status - Done",
        "Status - Failed",
        "Status - Deprecated",
        "Status - Archived",
    }
end

---@return string
function M.timestamp()
    return os.date("%Y%m%d%H%M%S")
end

---@param name string
---@return string
function M.sanitize_name(name)
    local out = trim(name)
    out = out:gsub("[\r\n\t]", " ")
    out = out:gsub("[/\\:]", "-")
    out = out:gsub("%s+", " ")
    return trim(out)
end

---@param name string
---@param ts string
---@return string
function M.filename(name, ts)
    return string.format("T-%s %s", ts, M.sanitize_name(name))
end

---@param path string
---@return string
local function stem_from_path(path)
    return vim.fn.fnamemodify(path, ":t:r")
end

---@param path string
---@return vault.TasksNote|nil
function M.read_task(path)
    local values = shared.read_frontmatter_fields(path, {
        "title",
        "status",
        "priority",
        "blocked_by",
    })
    local stem = stem_from_path(path)
    local status = normalize_status(values.status or "Status - Backlog")
    local priority = normalize_priority(values.priority or "Priority - Medium")
    local blocked = values.blocked_by
    if type(blocked) ~= "table" then
        blocked = {}
    end
    local blocked_by = {}
    for _, item in ipairs(blocked) do
        if type(item) == "string" and item ~= "" then
            blocked_by[#blocked_by + 1] = unwrap_link(item)
        end
    end
    return {
        path = path,
        stem = stem,
        title = values.title or stem,
        status = status,
        priority = priority,
        blocked_by = blocked_by,
    }
end

---@return string[]
local function collect_task_paths()
    local dir = M.tasks_dir_abs()
    if vim.fn.isdirectory(dir) == 0 then
        return {}
    end
    local ext = require("vault.config").options.ext or ".md"
    local out = {}
    local function walk(current)
        for name, kind in vim.fs.dir(current) do
            local child = current .. "/" .. name
            if kind == "directory" then
                walk(child)
            elseif kind == "file" and name:sub(-#ext) == ext then
                table.insert(out, child)
            end
        end
    end
    walk(dir)
    table.sort(out)
    return out
end

---@return vault.TasksNote[]
function M.all()
    local result = {}
    for _, path in ipairs(collect_task_paths()) do
        local task = M.read_task(path)
        if task then
            table.insert(result, task)
        end
    end
    return result
end

---@param stem string
---@param by_stem table<string, vault.TasksNote>
---@return boolean
local function dependency_complete(stem, by_stem)
    local dep = by_stem[unwrap_link(stem)]
    if not dep then
        return false
    end
    return COMPLETED_STATUS[dep.status] == true
end

---@param task vault.TasksNote
---@param by_stem table<string, vault.TasksNote>
---@return boolean
function M.is_blocked(task, by_stem)
    for _, dep in ipairs(task.blocked_by) do
        if not dependency_complete(dep, by_stem) then
            return true
        end
    end
    return false
end

---@param task vault.TasksNote
---@return boolean
function M.is_completed(task)
    return COMPLETED_STATUS[task.status] == true
end

---@return vault.TasksNote[]
function M.pick_candidates()
    local all = M.all()
    local by_stem = {}
    for _, item in ipairs(all) do
        by_stem[item.stem] = item
    end
    local candidates = {}
    for _, item in ipairs(all) do
        if not M.is_completed(item) and not M.is_blocked(item, by_stem) then
            table.insert(candidates, item)
        end
    end
    table.sort(candidates, function(a, b)
        local pa = PRIORITY_ORDER[a.priority] or 99
        local pb = PRIORITY_ORDER[b.priority] or 99
        if pa ~= pb then
            return pa < pb
        end
        local sa = STATUS_ORDER[a.status] or 99
        local sb = STATUS_ORDER[b.status] or 99
        if sa ~= sb then
            return sa < sb
        end
        return a.title < b.title
    end)
    return candidates
end

---@param status string
---@return string
local function status_link(status)
    return string.format("[[%s]]", status)
end

---@param path string
---@param new_status string
---@return boolean, string|nil
function M.set_status(path, new_status)
    local task = M.read_task(path)
    if not task then
        return false, "Task not found"
    end
    local from_status = normalize_status(task.status)
    local to_status = normalize_status(new_status)
    if not STATUS_ORDER[to_status] then
        return false, "Unknown status: " .. tostring(new_status)
    end
    if from_status == to_status then
        return true, nil
    end
    local allowed = VALID_TRANSITIONS[from_status] or {}
    if not allowed[to_status] then
        return false, string.format("Invalid transition: %s -> %s", from_status, to_status)
    end
    shared.set_frontmatter_fields(path, {
        status = status_link(to_status),
        modified = M.timestamp(),
    })
    return true, nil
end

---@param status string
---@return string[]
function M.next_statuses(status)
    local current = normalize_status(status)
    local out = {}
    local allowed = VALID_TRANSITIONS[current] or {}
    for _, candidate in ipairs(M.statuses()) do
        if allowed[candidate] then
            table.insert(out, candidate)
        end
    end
    return out
end

---@return string|nil
function M.current_task_path()
    local path = vim.fn.expand("%:p")
    if type(path) ~= "string" or path == "" then
        return nil
    end
    local abs = vim.fn.resolve(path)
    local root = M.tasks_dir_abs()
    local prefix = root:match("/$") and root or (root .. "/")
    if abs ~= root and not vim.startswith(abs, prefix) then
        return nil
    end
    if not abs:match(vim.pesc(require("vault.config").options.ext or ".md") .. "$") then
        return nil
    end
    return abs
end

---@param name string
---@param opts table|nil
---@return string|nil
function M.create(name, opts)
    opts = opts or {}
    local options = cfg()
    local clean_name = M.sanitize_name(name)
    if clean_name == "" then
        log.warn("Usage: :Vault tasks new <name>")
        return nil
    end
    local ts = M.timestamp()
    local stem = M.filename(clean_name, ts)
    local ext = require("vault.config").options.ext or ".md"
    local dir = M.tasks_dir_abs()
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

---@class vault.TasksDoctorIssue
---@field kind string
---@field path string
---@field stem string
---@field title string
---@field status_raw string|nil
---@field status_normalized string|nil

---@class vault.TasksDoctorReport
---@field scanned integer
---@field issues vault.TasksDoctorIssue[]
---@field fixed integer

---@param args table|nil
---@return vault.TasksDoctorReport
function M.doctor(args)
    args = args or {}
    local fix = args.fix == true
    local report = {
        scanned = 0,
        issues = {},
        fixed = 0,
    }

    local function add_issue(kind, path, values, normalized)
        local stem = stem_from_path(path)
        local title = (values and values.title) or stem
        table.insert(report.issues, {
            kind = kind,
            path = path,
            stem = stem,
            title = title,
            status_raw = values and values.status or nil,
            status_normalized = normalized,
        })
    end

    for _, path in ipairs(collect_task_paths()) do
        report.scanned = report.scanned + 1
        local values = shared.read_frontmatter_fields(path, { "title", "status" })
        local raw_status = values.status

        if type(raw_status) ~= "string" or trim(raw_status) == "" then
            add_issue("missing-status", path, values, nil)
            if fix then
                shared.set_frontmatter_fields(path, {
                    status = "[[Status - Backlog]]",
                    modified = M.timestamp(),
                })
                report.fixed = report.fixed + 1
            end
        else
            local normalized = normalize_status(raw_status)
            if not STATUS_ORDER[normalized] then
                add_issue("unknown-status", path, values, normalized)
            else
                local is_link = trim(raw_status):match("^%[%[.-%]%]$") ~= nil
                if not is_link then
                    add_issue("non-wikilink-status", path, values, normalized)
                    if fix then
                        shared.set_frontmatter_fields(path, {
                            status = status_link(normalized),
                            modified = M.timestamp(),
                        })
                        report.fixed = report.fixed + 1
                    end
                end
            end
        end
    end

    return report
end

return M
