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
