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

local WEEKDAY_TO_NUM = {
    sunday = 1,
    monday = 2,
    tuesday = 3,
    wednesday = 4,
    thursday = 5,
    friday = 6,
    saturday = 7,
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
local function today_iso()
    return os.date("%Y-%m-%d")
end

---@param value any
---@return string|nil
local function parse_iso_date(value)
    if type(value) ~= "string" then return nil end
    local v = unwrap_link(value)
    local y, m, d = v:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)")
    if y then return string.format("%s-%s-%s", y, m, d) end
    y, m, d = v:match("^(%d%d%d%d)(%d%d)(%d%d)")
    if y then return string.format("%s-%s-%s", y, m, d) end
    return nil
end

---@param iso string
---@return string
local function iso_to_wikilink(iso)
    local y, m, d = iso:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)$")
    if not y then return string.format("[[%s]]", iso) end
    local ts = os.time({ year = tonumber(y), month = tonumber(m), day = tonumber(d), hour = 12 })
    return string.format("[[%s %s]]", iso, os.date("%A", ts))
end

---@param iso string
---@param days integer
---@return string
local function add_days_iso(iso, days)
    local y, m, d = iso:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)$")
    if not y then return iso end
    local t = os.time({ year = tonumber(y), month = tonumber(m), day = tonumber(d), hour = 12 }) + (days * 86400)
    return os.date("%Y-%m-%d", t)
end

---@param iso string
---@return integer|nil
local function weekday_num_from_iso(iso)
    local y, m, d = iso:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)$")
    if not y then return nil end
    local t = os.time({ year = tonumber(y), month = tonumber(m), day = tonumber(d), hour = 12 })
    return tonumber(os.date("%w", t)) + 1
end

---@param from_iso string
---@param target_wday integer 1=Sun..7=Sat
---@return string
local function next_weekday_iso(from_iso, target_wday)
    local from_wday = weekday_num_from_iso(from_iso) or target_wday
    local delta = (target_wday - from_wday) % 7
    if delta == 0 then delta = 7 end
    return add_days_iso(from_iso, delta)
end

---@param iso string
---@param months integer
---@param day_override integer|nil
---@return string
local function add_months_iso(iso, months, day_override)
    local y, m, d = iso:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)$")
    if not y then return iso end
    local yi, mi, di = tonumber(y), tonumber(m), tonumber(d)
    local total = (yi * 12 + (mi - 1)) + months
    local ny = math.floor(total / 12)
    local nm = (total % 12) + 1
    local wanted_day = day_override or di
    local last_day = tonumber(os.date("%d", os.time({ year = ny, month = nm + 1, day = 0, hour = 12 })))
    local nd = math.min(wanted_day, last_day)
    return string.format("%04d-%02d-%02d", ny, nm, nd)
end

---@param value any
---@return string|nil
local function normalize_repeat(value)
    if type(value) ~= "string" then return nil end
    local v = trim(value):lower():gsub("%s+", " ")
    if v == "" then return nil end
    return v
end

---@param task_values table
---@param completed_iso string
---@return string|nil
local function next_due_iso(task_values, completed_iso)
    local rule = normalize_repeat(task_values["repeat"])
    if not rule then return nil end

    local due_iso = parse_iso_date(task_values.due)
    local start_iso = parse_iso_date(task_values.repeat_start) or due_iso or completed_iso
    local base_done = completed_iso

    if rule == "every day when done" then
        return add_days_iso(base_done, 1)
    end
    local n_days = rule:match("^every (%d+) days when done$")
    if n_days then
        return add_days_iso(base_done, tonumber(n_days))
    end
    if rule == "every week when done" then
        return add_days_iso(base_done, 7)
    end
    if rule == "every 2 weeks when done" then
        return add_days_iso(base_done, 14)
    end
    if rule == "every month when done" then
        return add_months_iso(base_done, 1)
    end

    if rule == "every day" then
        return add_days_iso(base_done, 1)
    end
    if rule == "every weekday" then
        local probe = base_done
        for _ = 1, 7 do
            probe = add_days_iso(probe, 1)
            local wd = weekday_num_from_iso(probe)
            if wd and wd >= 2 and wd <= 6 then
                return probe
            end
        end
        return add_days_iso(base_done, 1)
    end
    if rule == "every week" then
        local explicit = trim(task_values.repeat_weekday or ""):lower()
        local target = WEEKDAY_TO_NUM[explicit]
        if not target then
            target = weekday_num_from_iso(due_iso or base_done)
        end
        target = target or weekday_num_from_iso(base_done) or 2
        return next_weekday_iso(base_done, target)
    end
    if rule == "every other week" then
        local target = weekday_num_from_iso(start_iso) or weekday_num_from_iso(base_done) or 2
        local next_candidate = next_weekday_iso(base_done, target)
        local anchor = start_iso
        while next_candidate <= base_done do
            next_candidate = add_days_iso(next_candidate, 14)
        end
        if anchor then
            local guard = 0
            while next_candidate < add_days_iso(base_done, 1) and guard < 20 do
                next_candidate = add_days_iso(next_candidate, 14)
                guard = guard + 1
            end
        end
        return next_candidate
    end
    if rule == "every month" then
        local day = tonumber(task_values.repeat_day_of_month or "")
        if not day and due_iso then
            day = tonumber(due_iso:match("%-(%d%d)$"))
        end
        return add_months_iso(base_done, 1, day)
    end

    return nil
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

    if to_status == "Status - Done" then
        local values = shared.read_frontmatter_fields(path, {
            "title",
            "status",
            "executor",
            "category",
            "priority",
            "feature",
            "project",
            "initiative",
            "estimation",
            "due",
            "repeat",
            "repeat_start",
            "repeat_weekday",
            "repeat_day_of_month",
            "series_id",
            "last_recur_spawned",
        })

        local repeat_rule = normalize_repeat(values["repeat"])
        if repeat_rule and trim(values.last_recur_spawned or "") == "" then
            local done_iso = today_iso()
            local next_iso = next_due_iso(values, done_iso)
            if next_iso then
                local created = M.create(values.title or task.title, {
                    status = "[[Status - Backlog]]",
                    executor = values.executor,
                    category = values.category,
                    priority = values.priority,
                    title = values.title or task.title,
                })
                if created then
                    local new_stem = stem_from_path(created)
                    local old_stem = stem_from_path(path)
                    local series_id = trim(values.series_id or "")
                    if series_id == "" then
                        series_id = old_stem
                    end

                    shared.set_frontmatter_fields(created, {
                        feature = values.feature,
                        project = values.project,
                        initiative = values.initiative,
                        estimation = values.estimation,
                        due = iso_to_wikilink(next_iso),
                        ["repeat"] = values["repeat"],
                        repeat_start = values.repeat_start,
                        repeat_weekday = values.repeat_weekday,
                        repeat_day_of_month = values.repeat_day_of_month,
                        series_id = series_id,
                        recurs_from = string.format("[[%s]]", old_stem),
                    })

                    shared.set_frontmatter_fields(path, {
                        series_id = series_id,
                        last_recur_spawned = string.format("[[%s]]", new_stem),
                    })
                    log.info("Spawned recurring task: %s", new_stem)
                end
            end
        end
    end

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

---@param path string
---@param force boolean|nil
---@return string|nil, string|nil
function M.recur_spawn(path, force)
    local values = shared.read_frontmatter_fields(path, {
        "title",
        "status",
        "executor",
        "category",
        "priority",
        "feature",
        "project",
        "initiative",
        "estimation",
        "due",
        "repeat",
        "repeat_start",
        "repeat_weekday",
        "repeat_day_of_month",
        "series_id",
        "last_recur_spawned",
    })

    local repeat_rule = normalize_repeat(values["repeat"])
    if not repeat_rule then
        return nil, "Task has no repeat rule"
    end
    if not force and trim(values.last_recur_spawned or "") ~= "" then
        return nil, "Recurring instance already spawned"
    end

    local next_iso = next_due_iso(values, today_iso())
    if not next_iso then
        return nil, "Cannot compute next due date for repeat rule"
    end

    local created = M.create(values.title or stem_from_path(path), {
        status = "[[Status - Backlog]]",
        executor = values.executor,
        category = values.category,
        priority = values.priority,
        title = values.title or stem_from_path(path),
    })
    if not created then
        return nil, "Failed to create recurring task"
    end

    local new_stem = stem_from_path(created)
    local old_stem = stem_from_path(path)
    local series_id = trim(values.series_id or "")
    if series_id == "" then series_id = old_stem end

    shared.set_frontmatter_fields(created, {
        feature = values.feature,
        project = values.project,
        initiative = values.initiative,
        estimation = values.estimation,
        due = iso_to_wikilink(next_iso),
        ["repeat"] = values["repeat"],
        repeat_start = values.repeat_start,
        repeat_weekday = values.repeat_weekday,
        repeat_day_of_month = values.repeat_day_of_month,
        series_id = series_id,
        recurs_from = string.format("[[%s]]", old_stem),
    })

    shared.set_frontmatter_fields(path, {
        series_id = series_id,
        last_recur_spawned = string.format("[[%s]]", new_stem),
    })

    return created, nil
end

---@param path string
---@return string|nil, string|nil
function M.recur_preview(path)
    local values = shared.read_frontmatter_fields(path, {
        "repeat",
        "due",
        "repeat_start",
        "repeat_weekday",
        "repeat_day_of_month",
    })
    local repeat_rule = normalize_repeat(values["repeat"])
    if not repeat_rule then
        return nil, "Task has no repeat rule"
    end
    local next_iso = next_due_iso(values, today_iso())
    if not next_iso then
        return nil, "Cannot compute next due date for repeat rule"
    end
    return iso_to_wikilink(next_iso), nil
end

---@return integer, integer
function M.recur_sweep()
    local scanned = 0
    local spawned = 0
    for _, path in ipairs(collect_task_paths()) do
        scanned = scanned + 1
        local task = M.read_task(path)
        if task and M.is_completed(task) then
            local created = M.recur_spawn(path, false)
            if created then
                spawned = spawned + 1
            end
        end
    end
    return scanned, spawned
end

return M
