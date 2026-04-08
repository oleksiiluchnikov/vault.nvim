--- trace_vault_notes.lua — Trace :Vault notes performance step by step
---
--- Runs headless via:
---   NVIM_LISTEN_ADDRESS= nvim --headless -u tests/minimal_init.lua \
---     -l scripts/trace_vault_notes.lua [-- --vault-root /path/to/vault]
---
--- Instruments the full call chain of `:Vault notes` and prints a
--- step-by-step timing breakdown.

local function hrtime() return vim.uv.hrtime() end

--- @param label string
--- @param fn fun(): any
--- @return any result, number ms
local function timed(label, fn)
    collectgarbage("collect")
    local t0 = hrtime()
    local result = fn()
    local t1 = hrtime()
    local ms = (t1 - t0) / 1e6
    io.stderr:write(string.format("  %-55s %8.3f ms\n", label, ms))
    return result, ms
end

local function main()
    -- Parse args
    local vault_root = nil
    local argv = vim.v.argv or {}
    local after_sep = false
    for i, arg in ipairs(argv) do
        if arg == "--" then after_sep = true
        elseif after_sep and arg == "--vault-root" and argv[i + 1] then
            vault_root = argv[i + 1]
        end
    end

    -- Default to the knowledge vault if no arg and it exists
    if not vault_root then
        local home = os.getenv("HOME") or ""
        local candidates = {
            home .. "/knowledge",
            vim.fn.getcwd() .. "/benchmarks/fixture-vault-500",
        }
        for _, c in ipairs(candidates) do
            if vim.fn.isdirectory(c) == 1 then
                vault_root = c
                break
            end
        end
    end

    if not vault_root then
        io.stderr:write("ERROR: No vault root found. Use --vault-root /path/to/vault\n")
        vim.cmd("cquit!")
        return
    end

    io.stderr:write(string.format("\n=== :Vault notes trace — %s ===\n\n", vault_root))

    --- @type table<string, number>
    local timings = {}
    local total_t0 = hrtime()

    -- ── Step 0: Setup ────────────────────────────────────────────────────────
    io.stderr:write("[Step 0] Setup\n")
    timed("require('vault').setup()", function()
        -- Clear all vault modules for cold start
        for mod_name, _ in pairs(package.loaded) do
            if mod_name:match("^vault") or mod_name:match("^telescope") then
                package.loaded[mod_name] = nil
            end
        end
        require("vault").setup({
            root = vault_root,
            ext = ".md",
            features = { commands = false, watcher = false, cmp = false },
        })
    end)

    -- ── Step 1: Lazy-load commands module ────────────────────────────────────
    io.stderr:write("\n[Step 1] Commands module load (first :Vault invocation)\n")
    local _, cmd_ms = timed("require('vault.commands')", function()
        return require("vault.commands")
    end)
    timings["commands_load"] = cmd_ms

    -- ── Step 2: Scanner.paths() — Notes metadata ────────────────────────────
    io.stderr:write("\n[Step 2] Scanner — note metadata\n")
    local Scanner = require("vault.scanner")

    -- Cold scan
    Scanner.invalidate_notes_cache()
    require("vault.core.state").set_global_key("cache.notes.paths", nil)
    local paths_result, paths_ms = timed("Scanner.paths() [cold]", function()
        return Scanner.paths()
    end)
    timings["scanner_paths_cold"] = paths_ms

    local note_count = 0
    for _ in pairs(paths_result) do note_count = note_count + 1 end
    io.stderr:write(string.format("    → %d notes found\n", note_count))

    -- Warm scan (cached)
    local _, paths_warm_ms = timed("Scanner.paths() [warm/cached]", function()
        return Scanner.paths()
    end)
    timings["scanner_paths_warm"] = paths_warm_ms

    -- ── Step 3: Notes collection construction ────────────────────────────────
    io.stderr:write("\n[Step 3] Notes collection construction\n")
    local Notes_class
    local notes_instance
    local _, notes_ms = timed("require('vault.notes')()", function()
        Notes_class = require("vault.notes")
        notes_instance = Notes_class()
        return notes_instance
    end)
    timings["notes_constructor"] = notes_ms
    io.stderr:write(string.format("    → %d notes in collection\n", vim.tbl_count(notes_instance.map)))

    -- ── Step 4: Notes:list() ─────────────────────────────────────────────────
    io.stderr:write("\n[Step 4] Notes:list()\n")
    local results, list_ms = timed("notes:list()", function()
        return notes_instance:list()
    end)
    timings["notes_list"] = list_ms
    io.stderr:write(string.format("    → %d results\n", #results))

    -- ── Step 5a: Combined scan (cold — first call) ─────────────────────────
    io.stderr:write("\n[Step 5a] Combined cached scan: COLD (first call)\n")
    -- Clear Rust cache to force cold start
    Scanner.clear_rust_cache()
    local raw_paths_combined, wl_map_combined
    local _, cold_ms = timed("Scanner.paths_and_wikilinks_cached() [COLD]", function()
        raw_paths_combined, wl_map_combined = Scanner.paths_and_wikilinks_cached()
        return wl_map_combined
    end)
    timings["cached_scan_cold"] = cold_ms
    local wl_count = 0
    for _ in pairs(wl_map_combined) do wl_count = wl_count + 1 end
    io.stderr:write(string.format("    → %d notes + %d wikilinks in one pass\n", note_count, wl_count))

    -- ── Step 5b: Combined scan (warm — second call, mtime-validated) ──────
    io.stderr:write("\n[Step 5b] Combined cached scan: WARM (no files changed)\n")
    local raw_paths_warm, wl_map_warm
    local _, warm_ms = timed("Scanner.paths_and_wikilinks_cached() [WARM]", function()
        raw_paths_warm, wl_map_warm = Scanner.paths_and_wikilinks_cached()
        return wl_map_warm
    end)
    timings["cached_scan_warm"] = warm_ms

    -- ── Step 5c: Notes.from_paths (no re-scan) ──────────────────────────────
    io.stderr:write("\n[Step 5c] Notes.from_paths (build collection from pre-loaded data)\n")
    local notes_from_paths
    local _, from_paths_ms = timed("Notes.from_paths(raw_paths)", function()
        notes_from_paths = require("vault.notes").from_paths(raw_paths_warm)
        return notes_from_paths
    end)
    timings["notes_from_paths"] = from_paths_ms
    local results_combined = notes_from_paths:list()
    io.stderr:write(string.format("    → %d notes in collection\n", #results_combined))

    -- ── Step 6: note_stats.collect — link counting (with pre-loaded wikilinks) ─
    io.stderr:write("\n[Step 6] note_stats.collect(results, wikilinks_map) — no rescan\n")
    local note_stats = require("telescope._extensions.vault.pickers.notes.stats")
    local link_counts
    local _, stats_ms = timed("note_stats.collect(results, wl_map)", function()
        link_counts = note_stats.collect(results_combined, wl_map_combined)
        return link_counts
    end)
    timings["note_stats_collect"] = stats_ms

    -- ── Step 7: Entry maker + display setup ──────────────────────────────────
    io.stderr:write("\n[Step 7] Column width calculation\n")
    local _, entry_ms = timed("Column width + entry iteration", function()
        local col_2_maxwidth = 0
        local out_col_width = 0
        local in_col_width = 0
        local dang_col_width = 0
        for _, note in ipairs(results_combined) do
            local relpath = note.data.relpath
            local col_2 = ""
            if relpath:find("/", 1, true) then
                col_2 = string.match(relpath, "(.*/)") or ""
            end
            if col_2:len() > col_2_maxwidth then
                col_2_maxwidth = col_2:len()
            end
            local out_text, in_text, dang_text = note_stats.columns(link_counts[note.data.slug])
            out_col_width = math.max(out_col_width, out_text:len())
            in_col_width = math.max(in_col_width, in_text:len())
            dang_col_width = math.max(dang_col_width, dang_text:len())
        end
        return { col_2_maxwidth, out_col_width, in_col_width, dang_col_width }
    end)
    timings["entry_setup"] = entry_ms

    -- ── Step 8: Sort by mtime (pre-computed) ─────────────────────────────────
    io.stderr:write("\n[Step 8] Sort by mtime (pre-computed ftime lookup)\n")
    local _, sort_ms = timed("pre-compute ftime + table.sort", function()
        local ftime = {}
        for _, note in ipairs(results_combined) do
            ftime[note.data.path] = vim.fn.getftime(note.data.path)
        end
        table.sort(results_combined, function(a, b)
            return ftime[a.data.path] < ftime[b.data.path]
        end)
    end)
    timings["sort_mtime"] = sort_ms

    -- ── Step 9: Telescope module loading ─────────────────────────────────────
    io.stderr:write("\n[Step 9] Telescope module loading\n")
    local _, tele_ms = timed("require telescope modules", function()
        require("telescope.pickers")
        require("telescope.finders")
        require("telescope.sorters")
        require("telescope.pickers.entry_display")
    end)
    timings["telescope_load"] = tele_ms

    -- ── Summary ──────────────────────────────────────────────────────────────
    local total_ms = (hrtime() - total_t0) / 1e6

    io.stderr:write("\n" .. string.rep("=", 70) .. "\n")
    io.stderr:write("SUMMARY\n")
    io.stderr:write(string.rep("=", 70) .. "\n\n")

    --- @type { label: string, ms: number }[]
    local sorted = {}
    for k, v in pairs(timings) do
        sorted[#sorted + 1] = { label = k, ms = v }
    end
    table.sort(sorted, function(a, b) return a.ms > b.ms end)

    io.stderr:write(string.format("%-40s %10s %8s\n", "Step", "Time (ms)", "% Total"))
    io.stderr:write(string.rep("-", 62) .. "\n")
    for _, item in ipairs(sorted) do
        io.stderr:write(string.format("%-40s %10.3f %7.1f%%\n",
            item.label, item.ms, (item.ms / total_ms) * 100))
    end
    io.stderr:write(string.rep("-", 62) .. "\n")
    io.stderr:write(string.format("%-40s %10.3f %7.1f%%\n", "TOTAL (measured steps)", total_ms, 100))
    io.stderr:write(string.format("\nVault: %d notes\n", note_count))

    -- Observations
    io.stderr:write("\nOBSERVATIONS:\n")
    if timings["wikilinks_scan"] and timings["wikilinks_scan"] > 10 then
        io.stderr:write(string.format(
            "  ⚠ Wikilinks scan is %.0fms — dominates picker open time.\n"
            .. "    This calls Scanner.wikilinks() which runs vault_core.wikilinks()\n"
            .. "    on the entire vault. Consider caching link counts.\n",
            timings["wikilinks_scan"]))
    end
    if timings["note_stats_collect"] and timings["note_stats_collect"] > 5 then
        io.stderr:write(string.format(
            "  ⚠ note_stats.collect() is %.0fms — iterates all wikilinks to build\n"
            .. "    per-note link counts. Most of this is the wikilinks scan itself.\n",
            timings["note_stats_collect"]))
    end
    if timings["sort_mtime"] and timings["sort_mtime"] > 5 then
        io.stderr:write(string.format(
            "  ⚠ mtime sort is %.0fms — calls vim.fn.getftime() per note in comparator.\n"
            .. "    Pre-compute mtime into a lookup table before sorting.\n",
            timings["sort_mtime"]))
    end
    io.stderr:write("\n")
end

main()
vim.cmd("qall!")
