--- check_bench.lua — compare one benchmark report against another

local bench = dofile(vim.fn.getcwd() .. "/scripts/bench_utils.lua")

--- @class bench.CheckArgs
--- @field baseline string
--- @field latest string
--- @field threshold number
--- @field min_ms number
--- @field filter string|nil
--- @field fail_on_regression boolean

--- @param raw string|nil
--- @param default boolean
--- @return boolean
local function parse_bool(raw, default)
    if raw == nil then
        return default
    end

    local lowered = string.lower(raw)
    if lowered == "1" or lowered == "true" or lowered == "yes" or lowered == "on" then
        return true
    end
    if lowered == "0" or lowered == "false" or lowered == "no" or lowered == "off" then
        return false
    end

    return default
end

--- @return bench.CheckArgs
local function parse_args()
    --- @type bench.CheckArgs
    local args = {
        baseline = "benchmarks/baseline-500.json",
        latest = "benchmarks/latest.json",
        threshold = 20,
        min_ms = 1,
        filter = nil,
        fail_on_regression = true,
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
        elseif after_sep and arg == "--filter" and argv[i + 1] then
            args.filter = argv[i + 1]
        elseif after_sep and arg == "--fail-on-regression" and argv[i + 1] then
            args.fail_on_regression = parse_bool(argv[i + 1], args.fail_on_regression)
        end
    end

    return args
end

local function main()
    local args = parse_args()
    local baseline = bench.read_report(args.baseline)
    local latest = bench.read_report(args.latest)
    local rows, missing, added = bench.compare_reports(baseline, latest, args.filter)

    if #rows == 0 and #missing == 0 and #added == 0 then
        error(string.format("no benchmark metrics matched filter: %s", tostring(args.filter)))
    end

    --- @type string[]
    local failures = {}
    --- @type string[]
    local warnings = {}

    for _, row in ipairs(rows) do
        if row.latest_unit ~= row.baseline_unit then
            failures[#failures + 1] = string.format(
                "unit mismatch for %s: baseline=%s latest=%s",
                row.name,
                tostring(row.baseline_unit),
                tostring(row.latest_unit)
            )
        else
            if
                type(row.baseline_median) == "number"
                and type(row.latest_median) == "number"
                and row.baseline_median >= args.min_ms
            then
                local median_change = row.median_change
                if median_change and median_change > args.threshold then
                    failures[#failures + 1] = string.format(
                        "%s median regressed by %.1f%% (baseline %.3f%s -> latest %.3f%s)",
                        row.name,
                        median_change,
                        row.baseline_median,
                        tostring(row.baseline_unit or ""),
                        row.latest_median,
                        tostring(row.latest_unit or "")
                    )
                end
            end

            if
                type(row.baseline_p95) == "number"
                and type(row.latest_p95) == "number"
                and row.baseline_p95 >= args.min_ms
            then
                local p95_change = row.p95_change
                if p95_change and p95_change > args.threshold then
                    warnings[#warnings + 1] = string.format(
                        "%s p95 regressed by %.1f%% (baseline %.3f%s -> latest %.3f%s)",
                        row.name,
                        p95_change,
                        row.baseline_p95,
                        tostring(row.baseline_unit or ""),
                        row.latest_p95,
                        tostring(row.latest_unit or "")
                    )
                end
            end
        end
    end

    for _, name in ipairs(missing) do
        local message = string.format("missing metric in latest report: %s", name)
        if args.fail_on_regression then
            failures[#failures + 1] = message
        else
            warnings[#warnings + 1] = message
        end
    end

    for _, name in ipairs(added) do
        warnings[#warnings + 1] = string.format("new metric not present in baseline: %s", name)
    end

    io.stderr:write(
        string.format(
            "Benchmark compare: latest=%s baseline=%s threshold=%.1f%% min_ms=%.1f mode=%s\n",
            args.latest,
            args.baseline,
            args.threshold,
            args.min_ms,
            args.fail_on_regression and "gate" or "report"
        )
    )
    if type(args.filter) == "string" and args.filter ~= "" then
        io.stderr:write("Filter: " .. args.filter .. "\n")
    end
    io.stderr:write("\n")
    bench.print_compare_table(rows)

    if #warnings > 0 then
        io.stderr:write("Warnings:\n")
        for _, warning in ipairs(warnings) do
            io.stderr:write("  - " .. warning .. "\n")
        end
    end

    if #failures > 0 then
        io.stderr:write(
            args.fail_on_regression and "Failures:\n" or "Regressions over threshold:\n"
        )
        for _, failure in ipairs(failures) do
            io.stderr:write("  - " .. failure .. "\n")
        end
        if args.fail_on_regression then
            vim.cmd("cquit 1")
            return
        end
    end

    if args.fail_on_regression then
        io.stderr:write("Benchmark compare passed.\n")
    else
        io.stderr:write("Benchmark compare completed.\n")
    end
    vim.cmd("qall!")
end

main()
