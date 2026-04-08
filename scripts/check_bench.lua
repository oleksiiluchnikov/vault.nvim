--- check_bench.lua — compare latest benchmark report against a baseline

--- @class bench.CheckArgs
--- @field baseline string
--- @field latest string
--- @field threshold number
--- @field min_ms number

--- @return bench.CheckArgs
local function parse_args()
    --- @type bench.CheckArgs
    local args = {
        baseline = "benchmarks/baseline-500.json",
        latest = "benchmarks/latest.json",
        threshold = 20,
        min_ms = 1,
    }

    local argv = vim.v.argv or {}
    local after_sep = false
    for i, arg in ipairs(argv) do
        if arg == "--" then
            after_sep = true
        elseif after_sep and arg == "--baseline" and argv[i + 1] then
            args.baseline = argv[i + 1]
        elseif after_sep and arg == "--latest" and argv[i + 1] then
            args.latest = argv[i + 1]
        elseif after_sep and arg == "--threshold" and argv[i + 1] then
            args.threshold = tonumber(argv[i + 1]) or args.threshold
        elseif after_sep and arg == "--min-ms" and argv[i + 1] then
            args.min_ms = tonumber(argv[i + 1]) or args.min_ms
        end
    end

    return args
end

--- @param path string
--- @return table
local function read_report(path)
    local lines = vim.fn.readfile(path)
    if #lines == 0 then
        error("empty benchmark report: " .. path)
    end
    return vim.json.decode(table.concat(lines, "\n"))
end

--- @param metrics table[]
--- @return table<string, table>
local function metric_map(metrics)
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
local function percent_change(baseline, latest)
    if type(baseline) ~= "number" or type(latest) ~= "number" or baseline <= 0 then
        return nil
    end
    return ((latest - baseline) / baseline) * 100
end

local function main()
    local args = parse_args()
    local baseline = read_report(args.baseline)
    local latest = read_report(args.latest)

    local baseline_metrics = metric_map(baseline.metrics)
    local latest_metrics = metric_map(latest.metrics)

    --- @type string[]
    local failures = {}
    --- @type string[]
    local warnings = {}

    for name, base in pairs(baseline_metrics) do
        local cur = latest_metrics[name]
        if not cur then
            failures[#failures + 1] = string.format("missing metric in latest report: %s", name)
        elseif cur.unit ~= base.unit then
            failures[#failures + 1] = string.format(
                "unit mismatch for %s: baseline=%s latest=%s",
                name,
                tostring(base.unit),
                tostring(cur.unit)
            )
        else
            if
                type(base.median) == "number"
                and type(cur.median) == "number"
                and base.median >= args.min_ms
            then
                local median_change = percent_change(base.median, cur.median)
                if median_change and median_change > args.threshold then
                    failures[#failures + 1] = string.format(
                        "%s median regressed by %.1f%% (baseline %.3f%s -> latest %.3f%s)",
                        name,
                        median_change,
                        base.median,
                        tostring(base.unit or ""),
                        cur.median,
                        tostring(cur.unit or "")
                    )
                end
            end

            if
                type(base.p95) == "number"
                and type(cur.p95) == "number"
                and base.p95 >= args.min_ms
            then
                local p95_change = percent_change(base.p95, cur.p95)
                if p95_change and p95_change > args.threshold then
                    warnings[#warnings + 1] = string.format(
                        "%s p95 regressed by %.1f%% (baseline %.3f%s -> latest %.3f%s)",
                        name,
                        p95_change,
                        base.p95,
                        tostring(base.unit or ""),
                        cur.p95,
                        tostring(cur.unit or "")
                    )
                end
            end
        end
    end

    for name, _ in pairs(latest_metrics) do
        if not baseline_metrics[name] then
            warnings[#warnings + 1] = string.format("new metric not present in baseline: %s", name)
        end
    end

    io.stderr:write(
        string.format(
            "Benchmark compare: latest=%s baseline=%s threshold=%.1f%% min_ms=%.1f\n",
            args.latest,
            args.baseline,
            args.threshold,
            args.min_ms
        )
    )

    if #warnings > 0 then
        io.stderr:write("Warnings:\n")
        for _, warning in ipairs(warnings) do
            io.stderr:write("  - " .. warning .. "\n")
        end
    end

    if #failures > 0 then
        io.stderr:write("Failures:\n")
        for _, failure in ipairs(failures) do
            io.stderr:write("  - " .. failure .. "\n")
        end
        vim.cmd("cquit 1")
        return
    end

    io.stderr:write("Benchmark compare passed.\n")
    vim.cmd("qall!")
end

main()
