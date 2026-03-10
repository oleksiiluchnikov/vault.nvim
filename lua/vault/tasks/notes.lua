local log = require("vault.log").scope("tasks.notes")
local shared = require("vault.bases.views.shared")

local M = {}

--- A lightweight representation of a task note read from disk.
--- @class vault.TasksNote
--- @field path string Absolute filesystem path to the task file.
--- @field stem string Filename without directory or extension (e.g. `"T-20240101120000 My Task"`).
--- @field title string Human-readable task title (falls back to `stem` when absent from frontmatter).
--- @field status string Canonical status string, e.g. `"Status - Todo"`.
--- @field priority string Canonical priority string, e.g. `"Priority - Medium"`.
--- @field blocked_by string[] Stems of tasks that must complete before this one can start.

--- Allowed status values sorted by workflow order (lower = earlier in workflow).
--- @alias vault.TasksNote.StatusOrder table<string, integer>

--- @type vault.TasksNote.StatusOrder
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

--- Allowed priority values sorted by urgency (lower = higher priority).
--- @alias vault.TasksNote.PriorityOrder table<string, integer>

--- @type vault.TasksNote.PriorityOrder
local PRIORITY_ORDER = {
    ["Priority - Critical"] = 1,
    ["Priority - High"] = 2,
    ["Priority - Medium"] = 3,
    ["Priority - Low"] = 4,
}

--- Set of status strings that represent a task that is no longer actionable.
--- @type table<string, true>
local COMPLETED_STATUS = {
    ["Status - Done"] = true,
    ["Status - Failed"] = true,
    ["Status - Deprecated"] = true,
    ["Status - Archived"] = true,
}

--- Valid status-transition graph. Each key maps to the statuses it may advance to.
--- @alias vault.TasksNote.TransitionMap table<string, table<string, true>>

--- @type vault.TasksNote.TransitionMap
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

--- Maps lowercase weekday names to the Lua `os.date("%w")` convention + 1  (1=Sun..7=Sat).
--- @type table<string, integer>
local WEEKDAY_TO_NUM = {
    sunday = 1,
    monday = 2,
    tuesday = 3,
    wednesday = 4,
    thursday = 5,
    friday = 6,
    saturday = 7,
}

--- Return the plugin-level task_notes config table (or an empty table when absent).
--- @return table
local function cfg()
    local options = require("vault.config").options
    return options.task_notes or {}
end

--- Strip leading and trailing whitespace from a string.
--- @param value string
--- @return string
local function trim(value)
    return (value or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

--- Remove wikilink brackets from a value, e.g. `"[[foo]]"` → `"foo"`.
--- @param value string
--- @return string
local function unwrap_link(value)
    local out = trim(value)
    out = out:gsub("^%[%[(.-)%]%]$", "%1")
    return trim(out)
end

--- Normalise a raw status string (possibly a wikilink or alias) to its canonical form.
--- Falls back to the unwrapped candidate if no alias matches.
--- @param value string
--- @return string
local function normalize_status(value)
    local candidate = unwrap_link(value)
    if STATUS_ORDER[candidate] then
        return candidate
    end
    local lowered = candidate:lower():gsub("_", "-")
    --- @type table<string, string>
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

--- Normalise a raw priority string to its canonical form.
--- Returns `"Priority - Medium"` when the value is unknown.
--- @param value string
--- @return string
local function normalize_priority(value)
    local candidate = unwrap_link(value)
    if PRIORITY_ORDER[candidate] then
        return candidate
    end
    return "Priority - Medium"
end

--- Return today's date formatted as an ISO 8601 string (`"YYYY-MM-DD"`).
--- @return string
local function today_iso()
    return os.date("%Y-%m-%d")
end

--- Parse a value into an ISO 8601 date string (`"YYYY-MM-DD"`).
--- Accepts both `"YYYY-MM-DD"` and `"YYYYMMDD"` formats (possibly wrapped in `[[ ]]`).
--- Returns `nil` when the value is not a recognisable date.
--- @param value any
--- @return string|nil
local function parse_iso_date(value)
    if type(value) ~= "string" then return nil end
    local v = unwrap_link(value)
    local y, m, d = v:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)")
    if y then return string.format("%s-%s-%s", y, m, d) end
    y, m, d = v:match("^(%d%d%d%d)(%d%d)(%d%d)")
    if y then return string.format("%s-%s-%s", y, m, d) end
    return nil
end

--- Wrap an ISO date in a wikilink with weekday appended, e.g. `"[[2024-01-01 Monday]]"`.
--- @param iso string ISO 8601 date string (`"YYYY-MM-DD"`).
--- @return string
local function iso_to_wikilink(iso)
    local y, m, d = iso:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)$")
    if not y then return string.format("[[%s]]", iso) end
    local ts = os.time({ year = tonumber(y), month = tonumber(m), day = tonumber(d), hour = 12 })
    return string.format("[[%s %s]]", iso, os.date("%A", ts))
end

--- Return the ISO date that is `days` calendar days after `iso`.
--- Returns `iso` unchanged when it is not a valid `"YYYY-MM-DD"` string.
--- @param iso string Base ISO 8601 date.
--- @param days integer Number of days to add (may be negative).
--- @return string
local function add_days_iso(iso, days)
    local y, m, d = iso:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)$")
    if not y then return iso end
    local t = os.time({ year = tonumber(y), month = tonumber(m), day = tonumber(d), hour = 12 }) + (days * 86400)
    return os.date("%Y-%m-%d", t)
end

--- Return the weekday number (1=Sun … 7=Sat) for the given ISO date, or `nil` on parse failure.
--- @param iso string ISO 8601 date string (`"YYYY-MM-DD"`).
--- @return integer|nil
local function weekday_num_from_iso(iso)
    local y, m, d = iso:match("^(%d%d%d%d)%-(%d%d)%-(%d%d)$")
    if not y then return nil end
    local t = os.time({ year = tonumber(y), month = tonumber(m), day = tonumber(d), hour = 12 })
    return tonumber(os.date("%w", t)) + 1
end

--- Return the ISO date of the next occurrence of `target_wday` after `from_iso`.
--- Always advances by at least one day (never returns `from_iso` itself).
--- @param from_iso string ISO 8601 base date.
--- @param target_wday integer Target weekday number (1=Sun … 7=Sat).
--- @return string
local function next_weekday_iso(from_iso, target_wday)
    local from_wday = weekday_num_from_iso(from_iso) or target_wday
    local delta = (target_wday - from_wday) % 7
    if delta == 0 then delta = 7 end
    return add_days_iso(from_iso, delta)
end

--- Return the ISO date `months` calendar months after `iso`, optionally pinning to `day_override`.
--- Clamps the day to the last valid day of the resulting month.
--- @param iso string ISO 8601 base date (`"YYYY-MM-DD"`).
--- @param months integer Number of months to add.
--- @param day_override integer|nil When provided, use this day-of-month instead of `iso`'s day.
--- @return string
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

--- Normalise a repeat rule value to a trimmed, lowercase string, or `nil` when blank/absent.
--- @param value any
--- @return string|nil
local function normalize_repeat(value)
    if type(value) ~= "string" then return nil end
    local v = trim(value):lower():gsub("%s+", " ")
    if v == "" then return nil end
    return v
end

--- Frontmatter values read from a task file for recurrence calculation.
--- @class vault.TasksNote.RecurValues
--- @field title string|nil Human-readable task title.
--- @field status string|nil Raw status value from frontmatter.
--- @field executor string|nil Executor wikilink value.
--- @field category string|nil Category wikilink value.
--- @field priority string|nil Priority wikilink value.
--- @field feature string|nil Feature wikilink value.
--- @field project string|nil Project wikilink value.
--- @field initiative string|nil Initiative wikilink value.
--- @field estimation string|nil Estimation value.
--- @field due string|nil Due date value (ISO or wikilink).
--- @field repeat string|nil Repeat rule string.
--- @field repeat_start string|nil Override start date for recurrence window.
--- @field repeat_weekday string|nil Explicit weekday name for weekly recurrence.
--- @field repeat_day_of_month string|nil Explicit day-of-month for monthly recurrence.
--- @field series_id string|nil Slug identifying the recurrence series.
--- @field last_recur_spawned string|nil Wikilink to the last spawned child task.

--- Compute the ISO date of the next due occurrence given the task's recurrence rule.
--- Returns `nil` when the task has no repeat rule or the rule is unrecognised.
--- @param task_values vault.TasksNote.RecurValues Frontmatter values of the task.
--- @param completed_iso string ISO date on which the task was (or is being) completed.
--- @return string|nil
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

--- Return the absolute path to the vault root (with symlinks resolved).
--- @return string
local function vault_root()
    local root = require("vault.config").options.root
    return vim.fn.resolve(vim.fn.expand(root))
end

--- Return the relative path of the tasks directory inside the vault.
--- @return string
function M.tasks_dir_rel()
    return cfg().dir or "Tasks"
end

--- Return the absolute filesystem path of the tasks directory.
--- @return string
function M.tasks_dir_abs()
    return vault_root() .. "/" .. M.tasks_dir_rel()
end

--- Return the ordered list of all recognised status strings.
--- @return string[]
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

--- Return a timestamp string suitable for use in filenames (`"YYYYMMDDHHmmSS"`).
--- @return string
function M.timestamp()
    return os.date("%Y%m%d%H%M%S")
end

--- Sanitise a user-supplied task name for use as a filename component.
--- Strips control characters, replaces path separators with `-`, and collapses whitespace.
--- @param name string Raw task name.
--- @return string
function M.sanitize_name(name)
    local out = trim(name)
    out = out:gsub("[\r\n\t]", " ")
    out = out:gsub("[/\\:]", "-")
    out = out:gsub("%s+", " ")
    return trim(out)
end

--- Build the filename stem for a new task file.
--- Format: `"T-<timestamp> <sanitised name>"`.
--- @param name string Sanitised task name.
--- @param ts string Timestamp string from `M.timestamp()`.
--- @return string
function M.filename(name, ts)
    return string.format("T-%s %s", ts, M.sanitize_name(name))
end

--- Extract the filename stem (no directory, no extension) from an absolute path.
--- @param path string Absolute filesystem path.
--- @return string
local function stem_from_path(path)
    return vim.fn.fnamemodify(path, ":t:r")
end

--- Read frontmatter fields from a task file and return a structured note representation.
--- Returns `nil` when the path cannot be read.
--- @param path string Absolute path to the task `.md` file.
--- @return vault.TasksNote|nil
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
    --- @type string[]
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

--- Collect all task file paths under the tasks directory (recursively), sorted.
--- Returns an empty list when the directory does not exist.
--- @return string[]
local function collect_task_paths()
    local dir = M.tasks_dir_abs()
    if vim.fn.isdirectory(dir) == 0 then
        return {}
    end
    local ext = require("vault.config").options.ext or ".md"
    local out = {} ---@type string[]
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

--- Return all task notes found under the tasks directory.
--- @return vault.TasksNote[]
function M.all()
    local result = {} ---@type vault.TasksNote[]
    for _, path in ipairs(collect_task_paths()) do
        local task = M.read_task(path)
        if task then
            table.insert(result, task)
        end
    end
    return result
end

--- Return `true` when the dependency identified by `stem` is in a completed state.
--- Returns `false` when the dependency does not exist in `by_stem`.
--- @param stem string Stem of the dependency task.
--- @param by_stem table<string, vault.TasksNote> Index of all tasks keyed by stem.
--- @return boolean
local function dependency_complete(stem, by_stem)
    local dep = by_stem[unwrap_link(stem)]
    if not dep then
        return false
    end
    return COMPLETED_STATUS[dep.status] == true
end

--- Return `true` when `task` has at least one incomplete dependency.
--- @param task vault.TasksNote
--- @param by_stem table<string, vault.TasksNote> Index of all tasks keyed by stem.
--- @return boolean
function M.is_blocked(task, by_stem)
    for _, dep in ipairs(task.blocked_by) do
        if not dependency_complete(dep, by_stem) then
            return true
        end
    end
    return false
end

--- Return `true` when `task` has a status considered completed (done/failed/deprecated/archived).
--- @param task vault.TasksNote
--- @return boolean
function M.is_completed(task)
    return COMPLETED_STATUS[task.status] == true
end

--- Return all tasks that are neither completed nor blocked, sorted by priority then status then title.
--- @return vault.TasksNote[]
function M.pick_candidates()
    local all = M.all()
    --- @type table<string, vault.TasksNote>
    local by_stem = {}
    for _, item in ipairs(all) do
        by_stem[item.stem] = item
    end
    local candidates = {} ---@type vault.TasksNote[]
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

--- Wrap a status string in wikilink brackets.
--- @param status string Canonical status string.
--- @return string
local function status_link(status)
    return string.format("[[%s]]", status)
end

--- Transition the task at `path` to `new_status`, enforcing the allowed transition graph.
--- When the task transitions to `"Status - Done"` and has an active repeat rule, a new
--- recurring child task is automatically created with the next computed due date.
--- Returns `(true, nil)` on success or `(false, error_message)` on failure.
--- @param path string Absolute path to the task file.
--- @param new_status string Desired target status (raw or canonical form).
--- @return boolean ok
--- @return string|nil error_message
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
        --- @type vault.TasksNote.RecurValues
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

--- Return the status strings that `status` may legally transition to.
--- @param status string Current status (raw or canonical form).
--- @return string[]
function M.next_statuses(status)
    local current = normalize_status(status)
    local out = {} ---@type string[]
    local allowed = VALID_TRANSITIONS[current] or {}
    for _, candidate in ipairs(M.statuses()) do
        if allowed[candidate] then
            table.insert(out, candidate)
        end
    end
    return out
end

--- Return the absolute path of the task file currently open in the active Neovim buffer.
--- Returns `nil` when the buffer does not contain a task file.
--- @return string|nil
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

--- Create a new task file with default frontmatter and body template.
--- Returns the absolute path of the created file, or `nil` on failure.
--- @param name string Human-readable task name (will be sanitised).
--- @param opts table|nil Optional overrides for frontmatter fields (`status`, `executor`, `category`, `priority`, `title`).
--- @return string|nil
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

    --- @type string[]
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

--- A single issue found by the doctor scan.
--- @class vault.TasksDoctorIssue
--- @field kind string Category of issue (e.g. `"missing-status"`, `"unknown-status"`, `"non-wikilink-status"`).
--- @field path string Absolute path to the offending task file.
--- @field stem string Filename stem of the offending task.
--- @field title string Title of the offending task.
--- @field status_raw string|nil Raw status value read from frontmatter.
--- @field status_normalized string|nil Normalised form of the status (may be unknown).

--- Aggregated report returned by `M.doctor()`.
--- @class vault.TasksDoctorReport
--- @field scanned integer Total number of task files examined.
--- @field issues vault.TasksDoctorIssue[] List of problems found.
--- @field fixed integer Number of issues automatically repaired (only when `fix = true`).

--- Scan all task files for frontmatter quality issues and optionally repair them.
--- @param args table|nil Options table; set `args.fix = true` to apply automatic fixes.
--- @return vault.TasksDoctorReport
function M.doctor(args)
    args = args or {}
    local fix = args.fix == true
    --- @type vault.TasksDoctorReport
    local report = {
        scanned = 0,
        issues = {},
        fixed = 0,
    }

    --- @param kind string
    --- @param path string
    --- @param values table<string, any>|nil
    --- @param normalized string|nil
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

--- Manually spawn the next recurring instance of a task that already has a repeat rule.
--- When `force` is `false` (default) the call is a no-op if `last_recur_spawned` is set.
--- Returns `(new_path, nil)` on success or `(nil, error_message)` on failure.
--- @param path string Absolute path to the source (parent) task file.
--- @param force boolean|nil When `true`, spawns even if a child was already created.
--- @return string|nil new_path
--- @return string|nil error_message
function M.recur_spawn(path, force)
    --- @type vault.TasksNote.RecurValues
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

--- Preview the wikilink that would be written as the due date of the next recurring instance.
--- Returns `(wikilink_string, nil)` on success or `(nil, error_message)` when the rule is
--- absent or the next date cannot be computed.
--- @param path string Absolute path to the task file.
--- @return string|nil next_due_wikilink
--- @return string|nil error_message
function M.recur_preview(path)
    --- @type vault.TasksNote.RecurValues
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

--- Walk all task files and spawn a new recurring instance for every completed task
--- that has a repeat rule and has not yet had its successor created.
--- Returns `(scanned, spawned)` counts.
--- @return integer scanned Total files examined.
--- @return integer spawned Number of new recurring tasks created.
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
