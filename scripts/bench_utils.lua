--- bench_utils.lua — Shared benchmark utilities
---
--- Provides timing, statistics, fixture generation, and JSON output
--- for both vault.nvim and vimtable.nvim benchmark harnesses.
---
--- @module "scripts.bench_utils"

--- @class bench.Result
--- @field name string  Metric name
--- @field unit string  "ms" or "us"
--- @field min number   Minimum value
--- @field max number   Maximum value
--- @field median number  Median value
--- @field p95 number    95th percentile
--- @field p99 number    99th percentile
--- @field mean number   Arithmetic mean
--- @field stddev number  Standard deviation
--- @field iterations integer  Number of iterations
--- @field samples number[]  Raw sample values

--- @class bench.SystemInfo
--- @field nvim_version string
--- @field luajit_version string
--- @field os string
--- @field arch string
--- @field date string

--- @class bench.Report
--- @field system bench.SystemInfo
--- @field metrics bench.Result[]
--- @field timestamp string

--- @class bench.CompareRow
--- @field name string
--- @field unit string
--- @field baseline_median number|nil
--- @field latest_median number|nil
--- @field median_change number|nil
--- @field baseline_p95 number|nil
--- @field latest_p95 number|nil
--- @field p95_change number|nil
--- @field baseline_unit string|nil
--- @field latest_unit string|nil

--- @class bench.Utils
local M = {}

--- @class bench.MeasureHooks
--- @field before_each? fun(iteration: integer, is_warmup: boolean): nil
--- @field after_each? fun(iteration: integer, is_warmup: boolean): nil

-------------------------------------------------------------------------------
-- Timing
-------------------------------------------------------------------------------

--- Get high-resolution time in nanoseconds.
--- @return integer
function M.hrtime()
    return vim.uv.hrtime()
end

--- Measure execution time of a function in milliseconds.
--- @param fn fun()  Function to measure
--- @return number ms  Elapsed time in milliseconds
function M.time_ms(fn)
    local t0 = vim.uv.hrtime()
    fn()
    local t1 = vim.uv.hrtime()
    return (t1 - t0) / 1e6
end

--- Run a function N times and collect timing samples.
--- @param fn fun()  Function to benchmark
--- @param iterations integer  Number of iterations
--- @param warmup? integer  Warmup iterations (not measured, default 1)
--- @param hooks? bench.MeasureHooks  Optional per-iteration setup and teardown hooks
--- @return number[]  Array of elapsed times in milliseconds
function M.measure(fn, iterations, warmup, hooks)
    warmup = warmup or 1
    hooks = hooks or {}

    local before_each = hooks.before_each
    local after_each = hooks.after_each

    -- Warmup
    for i = 1, warmup do
        if before_each then
            before_each(i, true)
        end
        fn()
        if after_each then
            after_each(i, true)
        end
    end
    -- Collect
    --- @type number[]
    local samples = {}
    for i = 1, iterations do
        if before_each then
            before_each(i, false)
        end
        samples[i] = M.time_ms(fn)
        if after_each then
            after_each(i, false)
        end
    end
    return samples
end

-------------------------------------------------------------------------------
-- Statistics
-------------------------------------------------------------------------------

--- Compute a percentile from sorted samples using linear interpolation.
--- @param sorted number[]
--- @param p number
--- @return number
function M.percentile(sorted, p)
    local n = #sorted
    assert(n > 0, "bench_utils.percentile: empty samples")
    if n == 1 then
        return sorted[1]
    end

    local clamped = math.max(0, math.min(1, p))
    local position = 1 + (n - 1) * clamped
    local lower = math.floor(position)
    local upper = math.ceil(position)

    if lower == upper then
        return sorted[lower]
    end

    local weight = position - lower
    return sorted[lower] + (sorted[upper] - sorted[lower]) * weight
end

--- Compute statistics from a sample array.
--- @param samples number[]
--- @return { min: number, max: number, median: number, mean: number, stddev: number, p95: number, p99: number }
function M.stats(samples)
    local n = #samples
    assert(n > 0, "bench_utils.stats: empty samples")

    -- Sort for median
    local sorted = {}
    for i = 1, n do
        sorted[i] = samples[i]
    end
    table.sort(sorted)

    local min_val = sorted[1]
    local max_val = sorted[n]

    -- Median
    --- @type number
    local median
    if n % 2 == 1 then
        median = sorted[math.ceil(n / 2)]
    else
        median = (sorted[n / 2] + sorted[n / 2 + 1]) / 2
    end

    -- Mean
    local sum = 0
    for i = 1, n do
        sum = sum + sorted[i]
    end
    local mean = sum / n

    -- Standard deviation
    local var_sum = 0
    for i = 1, n do
        local d = sorted[i] - mean
        var_sum = var_sum + d * d
    end
    local stddev = math.sqrt(var_sum / n)

    return {
        min = min_val,
        max = max_val,
        median = median,
        p95 = M.percentile(sorted, 0.95),
        p99 = M.percentile(sorted, 0.99),
        mean = mean,
        stddev = stddev,
    }
end

--- Build a bench.Result from raw samples.
--- @param name string  Metric name
--- @param samples number[]  Raw timing samples in ms
--- @param unit? string  Unit label (default "ms")
--- @return bench.Result
function M.result(name, samples, unit)
    local s = M.stats(samples)
    return {
        name = name,
        unit = unit or "ms",
        min = M.round(s.min, 3),
        max = M.round(s.max, 3),
        median = M.round(s.median, 3),
        p95 = M.round(s.p95, 3),
        p99 = M.round(s.p99, 3),
        mean = M.round(s.mean, 3),
        stddev = M.round(s.stddev, 3),
        iterations = #samples,
        samples = samples,
    }
end

--- Round a number to N decimal places.
--- @param x number
--- @param decimals integer
--- @return number
function M.round(x, decimals)
    local mult = 10 ^ decimals
    return math.floor(x * mult + 0.5) / mult
end

--- @param name string
--- @param filter string|nil
--- @return boolean
function M.matches_filter(name, filter)
    if type(filter) ~= "string" or filter == "" then
        return true
    end

    return string.find(string.lower(name), string.lower(filter), 1, true) ~= nil
end

--- @param path string
--- @return table
function M.read_report(path)
    local lines = vim.fn.readfile(path)
    if #lines == 0 then
        error("empty benchmark report: " .. path)
    end

    return vim.json.decode(table.concat(lines, "\n"))
end

--- @param metrics table[]
--- @return table<string, table>
function M.metric_map(metrics)
    local map = {}
    for _, metric in ipairs(metrics or {}) do
        if type(metric.name) == "string" then
            map[metric.name] = metric
        end
    end
    return map
end

--- @param baseline number
--- @param latest number
--- @return number|nil
function M.percent_change(baseline, latest)
    if type(baseline) ~= "number" or type(latest) ~= "number" or baseline <= 0 then
        return nil
    end

    return ((latest - baseline) / baseline) * 100
end

--- @param baseline table
--- @param latest table
--- @param filter string|nil
--- @return bench.CompareRow[], string[], string[]
function M.compare_reports(baseline, latest, filter)
    local baseline_metrics = M.metric_map(baseline.metrics)
    local latest_metrics = M.metric_map(latest.metrics)

    --- @type bench.CompareRow[]
    local rows = {}
    --- @type string[]
    local missing = {}
    --- @type string[]
    local added = {}

    for name, base in pairs(baseline_metrics) do
        if M.matches_filter(name, filter) then
            local cur = latest_metrics[name]
            if not cur then
                missing[#missing + 1] = name
            else
                rows[#rows + 1] = {
                    name = name,
                    unit = tostring(cur.unit or base.unit or "ms"),
                    baseline_median = tonumber(base.median),
                    latest_median = tonumber(cur.median),
                    median_change = M.percent_change(tonumber(base.median), tonumber(cur.median)),
                    baseline_p95 = tonumber(base.p95),
                    latest_p95 = tonumber(cur.p95),
                    p95_change = M.percent_change(tonumber(base.p95), tonumber(cur.p95)),
                    baseline_unit = base.unit,
                    latest_unit = cur.unit,
                }
            end
        end
    end

    for name, _ in pairs(latest_metrics) do
        if M.matches_filter(name, filter) and not baseline_metrics[name] then
            added[#added + 1] = name
        end
    end

    table.sort(rows, function(a, b)
        local a_change = a.median_change or -math.huge
        local b_change = b.median_change or -math.huge
        if a_change == b_change then
            return a.name < b.name
        end
        return a_change > b_change
    end)
    table.sort(missing)
    table.sort(added)

    return rows, missing, added
end

--- @param change number|nil
--- @return string
function M.format_percent(change)
    if type(change) ~= "number" then
        return "n/a"
    end

    return string.format("%+.1f%%", change)
end

--- @param report bench.Report
--- @param path string
--- @return string
function M.write_report(report, path)
    local json = M.json_encode(report)
    local out_dir = vim.fn.fnamemodify(path, ":h")
    if out_dir ~= "" and out_dir ~= "." then
        vim.fn.mkdir(out_dir, "p")
    end

    local f, err = io.open(path, "w")
    if not f then
        error(string.format("failed to open benchmark report %s: %s", path, tostring(err)))
    end

    f:write(json .. "\n")
    f:close()
    return json
end

-------------------------------------------------------------------------------
-- System info
-------------------------------------------------------------------------------

--- Collect system information for the benchmark report.
--- @return bench.SystemInfo
function M.system_info()
    local v = vim.version()
    local nvim_version = string.format("v%d.%d.%d", v.major, v.minor, v.patch)
    if v.prerelease then
        nvim_version = nvim_version .. "-" .. v.prerelease
    end

    --- @type string
    local luajit_version = jit and jit.version or "PUC Lua"
    --- @type string
    local os_name = jit and jit.os or vim.uv.os_uname().sysname
    --- @type string
    local arch = jit and jit.arch or vim.uv.os_uname().machine

    return {
        nvim_version = nvim_version,
        luajit_version = luajit_version,
        os = os_name,
        arch = arch,
        date = os.date("%Y-%m-%dT%H:%M:%S"),
    }
end

-------------------------------------------------------------------------------
-- JSON output (minimal, no dependencies)
-------------------------------------------------------------------------------

--- Encode a value as JSON string (minimal implementation).
--- Handles strings, numbers, booleans, nil, arrays, and maps.
--- @param val any
--- @param indent? integer  Current indentation level (for pretty-printing)
--- @return string
function M.json_encode(val, indent)
    indent = indent or 0
    local pad = string.rep("  ", indent)
    local pad_inner = string.rep("  ", indent + 1)

    if val == nil or val == vim.NIL then
        return "null"
    elseif type(val) == "boolean" then
        return val and "true" or "false"
    elseif type(val) == "number" then
        if val ~= val then
            return "null"
        end -- NaN
        if val == math.huge then
            return "1e308"
        end
        if val == -math.huge then
            return "-1e308"
        end
        return string.format("%.6g", val)
    elseif type(val) == "string" then
        -- Escape special characters
        local escaped = val:gsub("\\", "\\\\")
            :gsub('"', '\\"')
            :gsub("\n", "\\n")
            :gsub("\r", "\\r")
            :gsub("\t", "\\t")
        return '"' .. escaped .. '"'
    elseif type(val) == "table" then
        -- Detect array vs object
        local is_array = #val > 0 or next(val) == nil
        if is_array and #val > 0 then
            -- Check it's a proper sequence
            for i = 1, #val do
                if val[i] == nil then
                    is_array = false
                    break
                end
            end
        end

        if is_array then
            if #val == 0 then
                return "[]"
            end
            local items = {}
            for i = 1, #val do
                items[i] = pad_inner .. M.json_encode(val[i], indent + 1)
            end
            return "[\n" .. table.concat(items, ",\n") .. "\n" .. pad .. "]"
        else
            local items = {}
            -- Sort keys for deterministic output
            local keys = {}
            for k, _ in pairs(val) do
                if type(k) == "string" then
                    keys[#keys + 1] = k
                end
            end
            table.sort(keys)
            for _, k in ipairs(keys) do
                local v = val[k]
                items[#items + 1] = pad_inner .. '"' .. k .. '": ' .. M.json_encode(v, indent + 1)
            end
            if #items == 0 then
                return "{}"
            end
            return "{\n" .. table.concat(items, ",\n") .. "\n" .. pad .. "}"
        end
    else
        return '"' .. tostring(val) .. '"'
    end
end

-------------------------------------------------------------------------------
-- Fixture vault generation
-------------------------------------------------------------------------------

--- Generate a fixture vault with N markdown notes for benchmarking.
--- Each note has frontmatter with slug, title, status, tags, created, modified.
--- @param dir string  Directory to create the vault in
--- @param count integer  Number of notes to generate
--- @return nil
function M.generate_fixture_vault(dir, count)
    vim.fn.mkdir(dir, "p")

    --- @type string[]
    local statuses = { "active", "done", "archived", "draft", "review" }
    --- @type string[]
    local tag_pool = {
        "project/alpha",
        "project/beta",
        "project/gamma",
        "area/work",
        "area/personal",
        "area/health",
        "type/note",
        "type/task",
        "type/reference",
        "priority/high",
        "priority/medium",
        "priority/low",
    }

    for i = 1, count do
        local slug = string.format("note-%04d", i)
        local status = statuses[(i % #statuses) + 1]
        local tag_count = (i % 3) + 1
        --- @type string[]
        local tags = {}
        for t = 1, tag_count do
            tags[t] = tag_pool[((i + t) % #tag_pool) + 1]
        end
        local tags_str = '  - "' .. table.concat(tags, '"\n  - "') .. '"'

        local day = (i % 28) + 1
        local month = ((i - 1) % 12) + 1
        local date_str = string.format("2026-%02d-%02d", month, day)

        local content = table.concat({
            "---",
            "slug: " .. slug,
            'title: "Note ' .. i .. ' — Benchmark Fixture"',
            "status: " .. status,
            "tags:",
            tags_str,
            "created: " .. date_str,
            "modified: " .. date_str,
            "categories:",
            '  - "[[category - tasks]]"',
            "---",
            "",
            "# " .. slug,
            "",
            "This is benchmark fixture note " .. i .. ".",
            "It contains some body text for realistic file sizes.",
            "",
            "## Section A",
            "",
            "- Item one for " .. slug,
            "- Item two with [[note-" .. string.format("%04d", (i % count) + 1) .. "]] wikilink",
            "- Item three with #" .. tags[1],
            "",
            "## Section B",
            "",
            "Some paragraph text to bulk up the file size a bit. "
                .. "This simulates a real note with actual content that "
                .. "the scanner needs to read and parse.",
            "",
        }, "\n")

        local path = dir .. "/" .. slug .. ".md"
        local f = io.open(path, "w")
        if f then
            f:write(content)
            f:close()
        end
    end
end

-------------------------------------------------------------------------------
-- Report formatting
-------------------------------------------------------------------------------

--- Print a results table to stderr for human consumption.
--- @param results bench.Result[]
--- @return nil
function M.print_table(results)
    io.stderr:write("\n")
    io.stderr:write(
        string.format(
            "%-40s %10s %10s %10s %10s %10s %10s %10s %6s\n",
            "Metric",
            "Min",
            "Median",
            "P95",
            "P99",
            "Mean",
            "Max",
            "StdDev",
            "N"
        )
    )
    io.stderr:write(string.rep("─", 122) .. "\n")
    for _, r in ipairs(results) do
        io.stderr:write(
            string.format(
                "%-40s %9.3f%s %9.3f%s %9.3f%s %9.3f%s %9.3f%s %9.3f%s %9.3f%s %5d\n",
                r.name,
                r.min,
                r.unit,
                r.median,
                r.unit,
                r.p95,
                r.unit,
                r.p99,
                r.unit,
                r.mean,
                r.unit,
                r.max,
                r.unit,
                r.stddev,
                r.unit,
                r.iterations
            )
        )
    end
    io.stderr:write("\n")
end

--- @param results bench.Result[]
--- @param limit integer|nil
--- @return nil
function M.print_hotspots(results, limit)
    if #results == 0 then
        return
    end

    limit = math.max(1, math.min(limit or 10, #results))

    local sorted = {}
    for i, result in ipairs(results) do
        sorted[i] = result
    end

    table.sort(sorted, function(a, b)
        if a.median == b.median then
            return a.name < b.name
        end
        return a.median > b.median
    end)

    io.stderr:write(string.format("Top %d hottest metrics (median):\n", limit))
    io.stderr:write(
        string.format("%-4s %-44s %10s %10s %10s\n", "#", "Metric", "Median", "P95", "P99")
    )
    io.stderr:write(string.rep("-", 84) .. "\n")
    for i = 1, limit do
        local r = sorted[i]
        io.stderr:write(
            string.format(
                "%-4d %-44s %9.3f%s %9.3f%s %9.3f%s\n",
                i,
                r.name,
                r.median,
                r.unit,
                r.p95,
                r.unit,
                r.p99,
                r.unit
            )
        )
    end
    io.stderr:write("\n")
end

--- @param rows bench.CompareRow[]
--- @return nil
function M.print_compare_table(rows)
    if #rows == 0 then
        return
    end

    io.stderr:write(
        string.format(
            "%-40s %12s %12s %10s %12s %12s %10s\n",
            "Metric",
            "Base Med",
            "Latest Med",
            "Delta",
            "Base P95",
            "Latest P95",
            "P95 Delta"
        )
    )
    io.stderr:write(string.rep("-", 114) .. "\n")

    for _, row in ipairs(rows) do
        local unit = row.unit or "ms"
        io.stderr:write(
            string.format(
                "%-40s %9.3f%s %9.3f%s %10s %9.3f%s %9.3f%s %10s\n",
                row.name,
                row.baseline_median or 0,
                unit,
                row.latest_median or 0,
                unit,
                M.format_percent(row.median_change),
                row.baseline_p95 or 0,
                unit,
                row.latest_p95 or 0,
                unit,
                M.format_percent(row.p95_change)
            )
        )
    end

    io.stderr:write("\n")
end

--- Build the full report structure.
--- @param results bench.Result[]
--- @return bench.Report
function M.build_report(results)
    -- Strip raw samples from the report (too verbose for JSON output)
    --- @type bench.Result[]
    local clean = {}
    for i, r in ipairs(results) do
        clean[i] = {
            name = r.name,
            unit = r.unit,
            min = r.min,
            max = r.max,
            median = r.median,
            p95 = r.p95,
            p99 = r.p99,
            mean = r.mean,
            stddev = r.stddev,
            iterations = r.iterations,
        }
    end

    return {
        system = M.system_info(),
        metrics = clean,
        timestamp = os.date("%Y-%m-%dT%H:%M:%S"),
    }
end

return M
