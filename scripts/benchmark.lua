--- benchmark.lua — vault.nvim performance benchmark harness
---
--- Runs headless via:
---   nvim --headless -u tests/minimal_init.lua -l scripts/benchmark.lua [-- --vault-size N]
---
--- Measures setup, scanner, and workflow-sensitive vault.nvim operations.
--- Outputs JSON to stdout and a human-readable table to stderr.

local uv = vim.uv or vim.loop

--- @class bench.VaultArgs
--- @field vault_size integer

--- @class bench.VaultConfigOpts
--- @field features? table<string, boolean>

--- @class bench.GridSaveState
--- @field grid { bufnr: fun(): integer }
--- @field note_paths table<string, string>
--- @field note_mtimes table<string, integer>
--- @field save_mode any
--- @field saving boolean|string
--- @field last_save_profile? table

--- @param path string
--- @return string[]
local function read_lines(path)
    return vim.fn.readfile(path)
end

--- @param path string
--- @param lines string[]
--- @return nil
local function write_lines(path, lines)
    vim.fn.writefile(lines, path)
end

--- @param lines string[]
--- @return string[]
local function clone_lines(lines)
    local copy = {}
    for i = 1, #lines do
        copy[i] = lines[i]
    end
    return copy
end

--- @param path string
--- @param delta integer
--- @return nil
local function bump_mtime(path, delta)
    local stat = uv.fs_stat(path)
    if not stat then
        return
    end

    local atime = stat.atime and stat.atime.sec or os.time()
    local mtime = stat.mtime and stat.mtime.sec or os.time()
    uv.fs_utime(path, atime, mtime + delta)
end

--- @param src string
--- @param dst string
--- @return nil
local function copy_dir(src, dst)
    vim.fn.mkdir(dst, "p")
    vim.fn.system({ "cp", "-R", src .. "/.", dst })
    if vim.v.shell_error ~= 0 then
        error(string.format("failed to copy %s -> %s", src, dst))
    end
end

--- @param path string
--- @return nil
local function delete_path(path)
    if vim.fn.isdirectory(path) == 1 then
        vim.fn.delete(path, "rf")
        return
    end
    if vim.fn.filereadable(path) == 1 then
        vim.fn.delete(path)
    end
end

--- @param src string
--- @param label string
--- @return string
local function new_temp_vault_copy(src, label)
    local path = vim.fn.tempname() .. "-" .. label
    copy_dir(src, path)
    return path
end

local function clear_vault_modules()
    for mod_name, _ in pairs(package.loaded) do
        if mod_name:match("^vault") or mod_name:match("^telescope") then
            package.loaded[mod_name] = nil
        end
    end
end

--- @param root string
--- @param opts? bench.VaultConfigOpts
--- @return nil
local function setup_vault(root, opts)
    opts = opts or {}
    clear_vault_modules()

    require("vault").setup(vim.tbl_deep_extend("force", {
        root = root,
        ext = ".md",
        features = {
            commands = false,
            watcher = false,
            cmp = false,
        },
        watcher = {
            prompt_on_rename = false,
            notify_on_rename = false,
            frontmatter_key = "slug",
            auto_update_links = true,
        },
        notify = {
            on_write = false,
        },
        log = {
            level = "error",
            file = false,
        },
    }, opts))
end

--- @return bench.VaultArgs
local function parse_args()
    --- @type bench.VaultArgs
    local args = { vault_size = 500 }

    local argv = vim.v.argv or {}
    local after_sep = false
    for i, arg in ipairs(argv) do
        if arg == "--" then
            after_sep = true
        elseif after_sep and arg == "--vault-size" and argv[i + 1] then
            args.vault_size = tonumber(argv[i + 1]) or 500
        end
    end

    return args
end

local function ensure_scratch_buffer()
    vim.cmd("silent! noautocmd enew!")
end

--- @param bufnr integer|nil
--- @return nil
local function delete_buffer(bufnr)
    if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
        return
    end

    if vim.api.nvim_get_current_buf() == bufnr then
        ensure_scratch_buffer()
    end

    pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
end

--- @param ge any
--- @param path string
--- @param slug string
--- @param bufnr integer
--- @return bench.GridSaveState
local function make_save_state(ge, path, slug, bufnr)
    return {
        grid = {
            bufnr = function()
                return bufnr
            end,
        },
        note_paths = { [slug] = path },
        note_mtimes = { [slug] = ge._get_mtime(path) },
        save_mode = nil,
        saving = false,
        last_save_profile = nil,
    }
end

--- @param st bench.GridSaveState
--- @param path string
--- @param slug string
--- @param ge any
--- @return nil
local function reset_save_state(st, path, slug, ge)
    st.note_paths = { [slug] = path }
    st.note_mtimes = { [slug] = ge._get_mtime(path) }
    st.saving = false
    st.last_save_profile = nil
end

--- @param name string
--- @param results bench.Result[]
--- @param bench bench.Utils
--- @param fn fun(): nil
--- @param iterations integer
--- @param warmup integer
--- @param hooks? bench.MeasureHooks
--- @return nil
local function add_metric(name, results, bench, fn, iterations, warmup, hooks)
    io.stderr:write(string.format("Measuring: %s...\n", name))
    local samples = bench.measure(fn, iterations, warmup, hooks)
    results[#results + 1] = bench.result(name, samples)
end

local SAVE_PHASE_KEYS = {
    "snapshot_for_undo",
    "apply_structural_ops",
    "watcher.handle_rename",
    "post_save_refresh",
}

--- @return table<string, number[]>
local function new_phase_samples()
    local samples = {}
    for _, phase in ipairs(SAVE_PHASE_KEYS) do
        samples[phase] = {}
    end
    return samples
end

--- @param phase_samples table<string, number[]>
--- @param profile table|nil
local function record_phase_samples(phase_samples, profile)
    local phases = type(profile) == "table" and profile.phases or {}
    for _, phase in ipairs(SAVE_PHASE_KEYS) do
        local bucket = phase_samples[phase]
        bucket[#bucket + 1] = tonumber(phases[phase] or 0) or 0
    end
end

--- @param results bench.Result[]
--- @param bench bench.Utils
--- @param prefix string
--- @param phase_samples table<string, number[]>
local function add_phase_metrics(results, bench, prefix, phase_samples)
    for _, phase in ipairs(SAVE_PHASE_KEYS) do
        results[#results + 1] = bench.result(prefix .. " phase " .. phase, phase_samples[phase])
    end
end

local function main()
    local args = parse_args()
    local bench = dofile(vim.fn.getcwd() .. "/scripts/bench_utils.lua")

    io.stderr:write(string.format("vault.nvim benchmark — vault_size=%d\n", args.vault_size))

    local fixture_dir = vim.fn.getcwd() .. "/benchmarks/fixture-vault-" .. args.vault_size
    if vim.fn.isdirectory(fixture_dir) == 0 then
        io.stderr:write(
            string.format(
                "Generating fixture vault with %d notes at %s...\n",
                args.vault_size,
                fixture_dir
            )
        )
        bench.generate_fixture_vault(fixture_dir, args.vault_size)
        io.stderr:write("Done.\n")
    else
        io.stderr:write(string.format("Using existing fixture vault at %s\n", fixture_dir))
    end

    --- @type bench.Result[]
    local results = {}

    io.stderr:write("\n== Startup & scanner ==\n")

    add_metric("setup()", results, bench, function()
        clear_vault_modules()
        require("vault").setup({
            root = fixture_dir,
            ext = ".md",
            features = { commands = false, watcher = false, cmp = false },
            notify = { on_write = false },
            log = { level = "error", file = false },
        })
    end, 10, 2)

    do
        clear_vault_modules()
        require("vault").setup({
            root = fixture_dir,
            ext = ".md",
            features = { commands = false, watcher = false, cmp = false },
            notify = { on_write = false },
            log = { level = "error", file = false },
        })

        add_metric("commands module load", results, bench, function()
            package.loaded["vault.commands"] = nil
            package.loaded["vault.commands.registry"] = nil
            package.loaded["vault.commands.completions"] = nil
            for mod_name, _ in pairs(package.loaded) do
                if mod_name:match("^telescope%._extensions%.vault") then
                    package.loaded[mod_name] = nil
                end
            end
            require("vault.commands")
        end, 10, 2)
    end

    do
        setup_vault(fixture_dir)
        local Scanner = require("vault.scanner")

        add_metric(
            "Scanner.paths() cold",
            results,
            bench,
            function()
                Scanner.paths()
            end,
            10,
            2,
            {
                before_each = function()
                    Scanner.invalidate_notes_cache()
                end,
            }
        )

        add_metric(
            "Scanner.slugs() cold",
            results,
            bench,
            function()
                Scanner.slugs()
            end,
            10,
            2,
            {
                before_each = function()
                    require("vault.core.state").set_global_key("cache.notes.slugs", nil)
                end,
            }
        )

        add_metric("Scanner.tags()", results, bench, function()
            Scanner.tags()
        end, 5, 1)

        add_metric("Scanner.wikilinks()", results, bench, function()
            Scanner.wikilinks()
        end, 5, 1)

        add_metric("Scanner.properties()", results, bench, function()
            Scanner.properties()
        end, 5, 1)

        add_metric("Scanner.lines() (pure Lua)", results, bench, function()
            Scanner.lines()
        end, 5, 1)

        add_metric(
            "Scanner.paths_and_wikilinks_cached() cold",
            results,
            bench,
            function()
                Scanner.paths_and_wikilinks_cached()
            end,
            10,
            2,
            {
                before_each = function()
                    Scanner.clear_rust_cache()
                end,
            }
        )

        Scanner.clear_rust_cache()
        Scanner.paths_and_wikilinks_cached()
        add_metric("Scanner.paths_and_wikilinks_cached() warm", results, bench, function()
            Scanner.paths_and_wikilinks_cached()
        end, 20, 2)
    end

    do
        local scan_root = new_temp_vault_copy(fixture_dir, "bench-scan")
        setup_vault(scan_root)
        local Scanner = require("vault.scanner")
        local path = scan_root .. "/note-0001.md"
        local original_lines = read_lines(path)
        local mutation_tick = 0

        Scanner.clear_rust_cache()
        Scanner.paths_and_wikilinks_cached()

        add_metric(
            "Scanner.paths_and_wikilinks_cached() 1 file changed",
            results,
            bench,
            function()
                Scanner.paths_and_wikilinks_cached()
            end,
            10,
            1,
            {
                before_each = function(iteration, is_warmup)
                    mutation_tick = mutation_tick + 1
                    local lines = clone_lines(original_lines)
                    lines[#lines + 1] = string.format(
                        "benchmark-cache-marker-%s-%d",
                        is_warmup and "warmup" or "run",
                        iteration + mutation_tick
                    )
                    write_lines(path, lines)
                    bump_mtime(path, iteration + mutation_tick + 1)
                end,
            }
        )

        write_lines(path, original_lines)
        delete_path(scan_root)
    end

    io.stderr:write("\n== Config & workflow ==\n")

    do
        setup_vault(fixture_dir)
        local Config = require("vault.config")

        add_metric("Config.setup()", results, bench, function()
            Config.setup({
                root = fixture_dir,
                ext = ".md",
                features = { commands = false, watcher = false, cmp = false },
                notify = { on_write = false },
                log = { level = "error", file = false },
            })
        end, 50, 5)
    end

    do
        setup_vault(fixture_dir)
        local Scanner = require("vault.scanner")
        local Notes = require("vault.notes")
        local grid = require("vault.views.grid")
        local raw_paths = Scanner.paths()
        local notes = Notes.from_paths(raw_paths)

        add_metric("Notes.from_paths()", results, bench, function()
            Notes.from_paths(raw_paths)
        end, 20, 2)

        add_metric("grid build_records()", results, bench, function()
            grid._build_records(notes.map, { "slug", "title", "status", "tags" }, nil)
        end, 20, 2)

        do
            local open_index = 0
            local current_bufnr = nil
            add_metric(
                "grid open() [preloaded]",
                results,
                bench,
                function()
                    open_index = open_index + 1
                    grid.open({
                        notes = notes,
                        filter_desc = string.format("bench-grid-open-%d", open_index),
                        columns = { "slug", "title", "status", "tags" },
                    })
                    current_bufnr = vim.api.nvim_get_current_buf()
                end,
                10,
                1,
                {
                    after_each = function()
                        delete_buffer(current_bufnr)
                        current_bufnr = nil
                    end,
                }
            )
        end

        do
            local open_index = 0
            local current_bufnr = nil
            add_metric(
                "grid save no-op (:w)",
                results,
                bench,
                function()
                    vim.cmd("silent write")
                end,
                10,
                1,
                {
                    before_each = function()
                        open_index = open_index + 1
                        grid.open({
                            notes = notes,
                            filter_desc = string.format("bench-grid-save-noop-%d", open_index),
                            columns = { "slug", "title", "status", "tags" },
                        })
                        current_bufnr = vim.api.nvim_get_current_buf()
                    end,
                    after_each = function()
                        delete_buffer(current_bufnr)
                        current_bufnr = nil
                    end,
                }
            )
        end
    end

    do
        local update_root = new_temp_vault_copy(fixture_dir, "bench-grid-update")
        setup_vault(update_root)
        local Scanner = require("vault.scanner")
        local grid = require("vault.views.grid")
        local note_path = update_root .. "/note-0001.md"
        local original_lines = read_lines(note_path)
        local bufnr = vim.api.nvim_create_buf(false, true)
        local state = make_save_state(grid, note_path, "note-0001", bufnr)
        local on_save = grid._make_on_save(state)
        local phase_samples = new_phase_samples()
        local capture_profile = false

        io.stderr:write("Measuring: grid on_save update...\n")
        local total_samples = bench.measure(
            function()
                local done_err = "PENDING"
                on_save({
                    updates = {
                        { id = "note-0001", fields = { status = "bench-updated" } },
                    },
                    deletes = {},
                    creates = {},
                    custom = {},
                    errors = {},
                }, function(err)
                    done_err = err or false
                end)
                if done_err ~= false then
                    error(tostring(done_err))
                end
                if capture_profile then
                    record_phase_samples(phase_samples, state.last_save_profile)
                end
            end,
            10,
            1,
            {
                before_each = function(_, is_warmup)
                    capture_profile = not is_warmup
                    write_lines(note_path, original_lines)
                    reset_save_state(state, note_path, "note-0001", grid)
                    grid._vt_undo.clear(bufnr)
                    Scanner.invalidate_notes_cache()
                    Scanner.clear_rust_cache()
                end,
            }
        )
        results[#results + 1] = bench.result("grid on_save update", total_samples)
        add_phase_metrics(results, bench, "grid on_save update", phase_samples)

        delete_buffer(bufnr)
        delete_path(update_root)
    end

    do
        local rename_root = new_temp_vault_copy(fixture_dir, "bench-grid-rename")
        setup_vault(rename_root)
        local Scanner = require("vault.scanner")
        local grid = require("vault.views.grid")
        local old_slug = "note-0001"
        local new_slug = "renamed-note-0001"
        local old_path = rename_root .. "/note-0001.md"
        local new_path = rename_root .. "/renamed-note-0001.md"
        local ref_path = rename_root .. "/note-" .. string.format("%04d", args.vault_size) .. ".md"
        local old_lines = read_lines(old_path)
        local ref_lines = read_lines(ref_path)
        local bufnr = vim.api.nvim_create_buf(false, true)
        local state = make_save_state(grid, old_path, old_slug, bufnr)
        local on_save = grid._make_on_save(state)
        local phase_samples = new_phase_samples()
        local capture_profile = false

        io.stderr:write("Measuring: grid on_save rename...\n")
        local total_samples = bench.measure(
            function()
                local done_err = "PENDING"
                on_save({
                    updates = {},
                    deletes = {},
                    creates = {},
                    custom = {
                        {
                            type = "rename",
                            extra = {
                                old_slug = old_slug,
                                new_slug = new_slug,
                                source_field = "slug",
                            },
                        },
                    },
                    errors = {},
                }, function(err)
                    done_err = err or false
                end)
                if done_err ~= false then
                    error(tostring(done_err))
                end
                if capture_profile then
                    record_phase_samples(phase_samples, state.last_save_profile)
                end
            end,
            10,
            1,
            {
                before_each = function(_, is_warmup)
                    capture_profile = not is_warmup
                    delete_path(new_path)
                    write_lines(old_path, old_lines)
                    write_lines(ref_path, ref_lines)
                    reset_save_state(state, old_path, old_slug, grid)
                    grid._vt_undo.clear(bufnr)
                    Scanner.invalidate_notes_cache()
                    Scanner.clear_rust_cache()
                end,
            }
        )
        results[#results + 1] = bench.result("grid on_save rename", total_samples)
        add_phase_metrics(results, bench, "grid on_save rename", phase_samples)

        delete_buffer(bufnr)
        delete_path(rename_root)
    end

    do
        local watcher_root = new_temp_vault_copy(fixture_dir, "bench-watcher")
        setup_vault(watcher_root)
        local Scanner = require("vault.scanner")
        local Watcher = require("vault.watcher")
        local watcher = Watcher()
        watcher:disable_oil_guard()

        local old_path = watcher_root .. "/note-0001.md"
        local new_path = watcher_root .. "/renamed-note-0001.md"
        local ref_path = watcher_root .. "/note-" .. string.format("%04d", args.vault_size) .. ".md"
        local old_lines = read_lines(old_path)
        local ref_lines = read_lines(ref_path)
        local rename_tick = 0

        add_metric(
            "Watcher.handle_rename()",
            results,
            bench,
            function()
                local patched = watcher:handle_rename(old_path, new_path, true)
                if patched < 1 then
                    error(string.format("expected watcher rename patch, got %s", tostring(patched)))
                end
            end,
            10,
            1,
            {
                before_each = function(iteration, is_warmup)
                    rename_tick = rename_tick + 1
                    delete_path(new_path)
                    write_lines(old_path, old_lines)
                    write_lines(ref_path, ref_lines)
                    bump_mtime(old_path, iteration + rename_tick + (is_warmup and 50 or 0))
                    bump_mtime(ref_path, iteration + rename_tick + (is_warmup and 50 or 0))
                    Scanner.invalidate_notes_cache()
                    Scanner.clear_rust_cache()
                    local ok, err = uv.fs_rename(old_path, new_path)
                    if not ok then
                        error(tostring(err))
                    end
                    Scanner.invalidate_notes_cache()
                    Scanner.clear_rust_cache()
                end,
            }
        )

        delete_path(watcher_root)
    end

    bench.print_table(results)

    local report = bench.build_report(results)
    report.vault_size = args.vault_size

    local json = bench.json_encode(report)
    io.stdout:write(json .. "\n")

    local out_dir = vim.fn.getcwd() .. "/benchmarks"
    vim.fn.mkdir(out_dir, "p")
    local out_path = out_dir .. "/latest.json"
    local f = io.open(out_path, "w")
    if f then
        f:write(json .. "\n")
        f:close()
        io.stderr:write("Results saved to " .. out_path .. "\n")
    end
end

main()
vim.cmd("qall!")
