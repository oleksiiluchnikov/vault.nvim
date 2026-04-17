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
--- @field filter string|nil
--- @field out string
--- @field list_metrics boolean
--- @field top integer

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
    local args = {
        vault_size = 15000,
        filter = nil,
        out = "benchmarks/latest.json",
        list_metrics = false,
        top = 10,
    }

    local argv = vim.v.argv or {}
    local after_sep = false
    for i, arg in ipairs(argv) do
        if arg == "--" then
            after_sep = true
        elseif after_sep and arg == "--vault-size" and argv[i + 1] then
            args.vault_size = tonumber(argv[i + 1]) or 15000
        elseif after_sep and arg == "--filter" and argv[i + 1] then
            args.filter = argv[i + 1]
        elseif after_sep and arg == "--out" and argv[i + 1] then
            args.out = argv[i + 1]
        elseif after_sep and arg == "--top" and argv[i + 1] then
            args.top = tonumber(argv[i + 1]) or args.top
        elseif after_sep and arg == "--list-metrics" then
            args.list_metrics = true
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

--- @param ids integer[]
--- @return table<integer, boolean>
local function id_set(ids)
    local set = {}
    for _, id in ipairs(ids) do
        set[id] = true
    end
    return set
end

--- @param existing_wins table<integer, boolean>
--- @return nil
local function close_new_windows(existing_wins)
    for _, win in ipairs(vim.api.nvim_list_wins()) do
        if not existing_wins[win] and vim.api.nvim_win_is_valid(win) then
            pcall(vim.api.nvim_win_close, win, true)
        end
    end
end

--- @param existing_bufs table<integer, boolean>
--- @return nil
local function delete_new_buffers(existing_bufs)
    for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
        if not existing_bufs[bufnr] then
            delete_buffer(bufnr)
        end
    end
end

--- @param picker Picker|nil
--- @return nil
local function open_picker_and_close(picker)
    if not picker then
        return
    end

    local existing_wins = id_set(vim.api.nvim_list_wins())
    local existing_bufs = id_set(vim.api.nvim_list_bufs())

    vim.schedule(function()
        close_new_windows(existing_wins)
    end)

    picker:find()

    close_new_windows(existing_wins)
    delete_new_buffers(existing_bufs)
    ensure_scratch_buffer()
end

--- @param picker_factory fun(): any
--- @return nil
local function measure_progressive_picker_ready(picker_factory)
    picker_factory()
end

local function clear_picker_caches()
    local Scanner = require("vault.scanner")
    Scanner.invalidate_notes_cache()
    Scanner.clear_rust_cache()
end

local function prewarm_picker_state()
    require("vault.prewarm").prewarm_notes()
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

--- @param st bench.GridSaveState
--- @param paths table<string, { path: string }>|table<string, string>
--- @param ge any
--- @return nil
local function reset_full_save_state(st, paths, ge)
    st.note_paths = {}
    st.note_mtimes = {}
    for slug, entry in pairs(paths) do
        local path = type(entry) == "table" and entry.path or entry
        if type(path) == "string" and path ~= "" then
            st.note_paths[slug] = path
            st.note_mtimes[slug] = ge._get_mtime(path)
        end
    end
    st.saving = false
    st.last_save_profile = nil
end

--- @param ge any
--- @param paths table<string, { path: string }>|table<string, string>
--- @param bufnr integer
--- @param label string
--- @return bench.GridSaveState
local function make_full_save_state(ge, paths, bufnr, label)
    --- @type bench.GridSaveState
    local st = {
        grid = {
            bufnr = function()
                return bufnr
            end,
            reload = function() end,
        },
        note_paths = {},
        note_mtimes = {},
        save_mode = nil,
        saving = false,
        last_save_profile = nil,
        columns = { "slug", "title", "status", "tags" },
        filter_desc = label,
    }
    reset_full_save_state(st, paths, ge)
    return st
end

--- @param rename_count integer
--- @return table
local function make_batch_rename_diff(rename_count)
    local diff = {
        updates = {},
        deletes = {},
        creates = {},
        custom = {},
        errors = {},
    }

    for i = 1, rename_count do
        local slug = string.format("note-%04d", i)
        diff.custom[#diff.custom + 1] = {
            type = "rename",
            extra = {
                old_slug = slug,
                new_slug = "renamed/" .. slug,
                source_field = "slug",
            },
        }
    end

    return diff
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

local METRIC_NAMES = {
    "setup()",
    "commands module load",
    "Scanner.paths() cold",
    "Scanner.slugs() cold",
    "Scanner.tags()",
    "Scanner.wikilinks()",
    "Scanner.properties()",
    "Scanner.lines() (pure Lua)",
    "Scanner.paths_and_wikilinks_cached() cold",
    "Scanner.paths_and_wikilinks_cached() warm",
    "Scanner.paths_and_wikilinks_cached() 1 file changed",
    "Config.setup()",
    "picker notes() open [cold]",
    "picker notes() open [warm]",
    "picker notes() open [preloaded]",
    "picker notes() ready [cold]",
    "picker notes() ready [prewarmed]",
    "picker linked() open [cold]",
    "picker linked() open [prewarmed]",
    "picker linked() ready [cold]",
    "picker linked() ready [prewarmed]",
    "picker orphans() open [cold]",
    "picker orphans() open [prewarmed]",
    "picker orphans() ready [cold]",
    "picker orphans() ready [prewarmed]",
    "picker inbox() open [cold]",
    "picker inbox() open [prewarmed]",
    "picker inbox() ready [cold]",
    "picker inbox() ready [prewarmed]",
    "picker tags() open [cold]",
    "picker tags() open [warm]",
    "picker properties() open [cold]",
    "picker properties() open [warm]",
    "picker dirs() open [cold]",
    "picker dirs() open [warm]",
    "picker wikilinks() open [cold]",
    "picker wikilinks() open [warm]",
    "Notes.from_paths()",
    "grid build_records()",
    "grid open() [preloaded]",
    "grid save no-op (:w)",
    "grid on_save update",
    "grid on_save rename",
    "grid on_save rename batch",
    "Watcher.handle_rename()",
}

--- @param prefix string
--- @return string[]
local function phase_metric_names(prefix)
    local names = { prefix }
    for _, phase in ipairs(SAVE_PHASE_KEYS) do
        names[#names + 1] = prefix .. " phase " .. phase
    end
    return names
end

for _, name in ipairs(phase_metric_names("grid on_save update")) do
    if name ~= "grid on_save update" then
        METRIC_NAMES[#METRIC_NAMES + 1] = name
    end
end
for _, name in ipairs(phase_metric_names("grid on_save rename")) do
    if name ~= "grid on_save rename" then
        METRIC_NAMES[#METRIC_NAMES + 1] = name
    end
end
for _, name in ipairs(phase_metric_names("grid on_save rename batch")) do
    if name ~= "grid on_save rename batch" then
        METRIC_NAMES[#METRIC_NAMES + 1] = name
    end
end

local SCANNER_METRICS = {
    "Scanner.paths() cold",
    "Scanner.slugs() cold",
    "Scanner.tags()",
    "Scanner.wikilinks()",
    "Scanner.properties()",
    "Scanner.lines() (pure Lua)",
    "Scanner.paths_and_wikilinks_cached() cold",
    "Scanner.paths_and_wikilinks_cached() warm",
    "Scanner.paths_and_wikilinks_cached() 1 file changed",
}

local GRID_METRICS = {
    "Notes.from_paths()",
    "grid build_records()",
    "grid open() [preloaded]",
    "grid save no-op (:w)",
}

local PICKER_METRICS = {
    "picker notes() open [cold]",
    "picker notes() open [warm]",
    "picker notes() open [preloaded]",
    "picker notes() ready [cold]",
    "picker notes() ready [prewarmed]",
    "picker linked() open [cold]",
    "picker linked() open [prewarmed]",
    "picker linked() ready [cold]",
    "picker linked() ready [prewarmed]",
    "picker orphans() open [cold]",
    "picker orphans() open [prewarmed]",
    "picker orphans() ready [cold]",
    "picker orphans() ready [prewarmed]",
    "picker inbox() open [cold]",
    "picker inbox() open [prewarmed]",
    "picker inbox() ready [cold]",
    "picker inbox() ready [prewarmed]",
    "picker tags() open [cold]",
    "picker tags() open [warm]",
    "picker properties() open [cold]",
    "picker properties() open [warm]",
    "picker dirs() open [cold]",
    "picker dirs() open [warm]",
    "picker wikilinks() open [cold]",
    "picker wikilinks() open [warm]",
}

local UPDATE_METRICS = phase_metric_names("grid on_save update")
local RENAME_METRICS = phase_metric_names("grid on_save rename")
local RENAME_BATCH_METRICS = phase_metric_names("grid on_save rename batch")

--- @param filter string|nil
--- @param name string
--- @return boolean
local function matches_metric_filter(filter, name)
    if type(filter) ~= "string" or filter == "" then
        return true
    end

    return string.find(string.lower(name), string.lower(filter), 1, true) ~= nil
end

--- @param args bench.VaultArgs
--- @param names string[]
--- @return boolean
local function wants_metric(args, names)
    if type(args.filter) ~= "string" or args.filter == "" then
        return true
    end

    for _, name in ipairs(names) do
        if matches_metric_filter(args.filter, name) then
            return true
        end
    end

    return false
end

--- @param filter string|nil
--- @return boolean
local function has_matching_metric(filter)
    for _, name in ipairs(METRIC_NAMES) do
        if matches_metric_filter(filter, name) then
            return true
        end
    end

    return false
end

local function print_metric_names()
    for _, name in ipairs(METRIC_NAMES) do
        io.stdout:write(name .. "\n")
    end
end

local function ensure_vault_core_available()
    local ok, err = pcall(require, "vault_core")
    if not ok then
        error(
            "vault_core is not built. Run `just build` before benchmarks. Original error: "
                .. tostring(err)
        )
    end
end

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
--- @param args bench.VaultArgs
--- @param prefix string
--- @param phase_samples table<string, number[]>
local function add_phase_metrics(results, bench, args, prefix, phase_samples)
    for _, phase in ipairs(SAVE_PHASE_KEYS) do
        local metric_name = prefix .. " phase " .. phase
        if wants_metric(args, { metric_name }) then
            results[#results + 1] = bench.result(metric_name, phase_samples[phase])
        end
    end
end

local function main()
    local args = parse_args()
    local bench = dofile(vim.fn.getcwd() .. "/scripts/bench_utils.lua")

    if args.list_metrics then
        print_metric_names()
        return
    end

    if not has_matching_metric(args.filter) then
        error(string.format("no benchmark metrics matched filter: %s", tostring(args.filter)))
    end

    ensure_vault_core_available()

    io.stderr:write(string.format("vault.nvim benchmark — vault_size=%d\n", args.vault_size))
    if type(args.filter) == "string" and args.filter ~= "" then
        io.stderr:write(string.format("Filter: %s\n", args.filter))
    end

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

    if wants_metric(args, { "setup()" }) then
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
    end

    if wants_metric(args, { "commands module load" }) then
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

    if wants_metric(args, SCANNER_METRICS) then
        setup_vault(fixture_dir)
        local Scanner = require("vault.scanner")

        if wants_metric(args, { "Scanner.paths() cold" }) then
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
        end

        if wants_metric(args, { "Scanner.slugs() cold" }) then
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
        end

        if wants_metric(args, { "Scanner.tags()" }) then
            add_metric("Scanner.tags()", results, bench, function()
                Scanner.tags()
            end, 5, 1)
        end

        if wants_metric(args, { "Scanner.wikilinks()" }) then
            add_metric("Scanner.wikilinks()", results, bench, function()
                Scanner.wikilinks()
            end, 5, 1)
        end

        if wants_metric(args, { "Scanner.properties()" }) then
            add_metric("Scanner.properties()", results, bench, function()
                Scanner.properties()
            end, 5, 1)
        end

        if wants_metric(args, { "Scanner.lines() (pure Lua)" }) then
            add_metric("Scanner.lines() (pure Lua)", results, bench, function()
                Scanner.lines()
            end, 5, 1)
        end

        if wants_metric(args, { "Scanner.paths_and_wikilinks_cached() cold" }) then
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
        end

        if wants_metric(args, { "Scanner.paths_and_wikilinks_cached() warm" }) then
            Scanner.clear_rust_cache()
            Scanner.paths_and_wikilinks_cached()
            add_metric("Scanner.paths_and_wikilinks_cached() warm", results, bench, function()
                Scanner.paths_and_wikilinks_cached()
            end, 20, 2)
        end
    end

    if wants_metric(args, { "Scanner.paths_and_wikilinks_cached() 1 file changed" }) then
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

    if wants_metric(args, { "Config.setup()" }) then
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

    if wants_metric(args, PICKER_METRICS) then
        setup_vault(fixture_dir)

        local Scanner = require("vault.scanner")
        local Notes = require("vault.notes")
        local notes_picker = require("telescope._extensions.vault.pickers.notes")
        local linked_picker = require("telescope._extensions.vault.pickers.linked")
        local orphans_picker = require("telescope._extensions.vault.pickers.orphans")
        local inbox_picker = require("telescope._extensions.vault.pickers.inbox")
        local tags_picker = require("telescope._extensions.vault.pickers.tags")
        local properties_picker = require("telescope._extensions.vault.pickers.properties")
        local dirs_picker = require("telescope._extensions.vault.pickers.dirs")
        local wikilinks_picker = require("telescope._extensions.vault.pickers.wikilinks")

        io.stderr:write("\n== Pickers ==\n")

        if wants_metric(args, { "picker notes() open [cold]" }) then
            add_metric(
                "picker notes() open [cold]",
                results,
                bench,
                function()
                    open_picker_and_close(notes_picker({ sort_by = "mtime" }))
                end,
                5,
                0,
                {
                    before_each = function()
                        clear_picker_caches()
                    end,
                }
            )
        end

        if wants_metric(args, { "picker notes() open [warm]" }) then
            add_metric("picker notes() open [warm]", results, bench, function()
                open_picker_and_close(notes_picker({ sort_by = "mtime" }))
            end, 10, 1)
        end

        if wants_metric(args, { "picker notes() open [preloaded]" }) then
            local raw_paths, wikilinks_map = Scanner.paths_and_wikilinks_cached()
            local notes = Notes.from_paths(raw_paths)

            add_metric("picker notes() open [preloaded]", results, bench, function()
                open_picker_and_close(notes_picker({
                    notes = notes,
                    _wikilinks_map = wikilinks_map,
                    sort_by = "mtime",
                }))
            end, 10, 1)
        end

        if wants_metric(args, { "picker notes() ready [cold]" }) then
            add_metric(
                "picker notes() ready [cold]",
                results,
                bench,
                function()
                    measure_progressive_picker_ready(function()
                        return notes_picker({ sort_by = "mtime", _measure_ready_only = true })
                    end)
                end,
                5,
                0,
                {
                    before_each = function()
                        clear_picker_caches()
                    end,
                }
            )
        end

        if wants_metric(args, { "picker notes() ready [prewarmed]" }) then
            add_metric(
                "picker notes() ready [prewarmed]",
                results,
                bench,
                function()
                    measure_progressive_picker_ready(function()
                        return notes_picker({ sort_by = "mtime", _measure_ready_only = true })
                    end)
                end,
                5,
                0,
                {
                    before_each = function()
                        clear_picker_caches()
                        prewarm_picker_state()
                    end,
                }
            )
        end

        if wants_metric(args, { "picker linked() open [cold]" }) then
            add_metric(
                "picker linked() open [cold]",
                results,
                bench,
                function()
                    open_picker_and_close(linked_picker({ sort_by = "mtime" }))
                end,
                5,
                0,
                {
                    before_each = function()
                        clear_picker_caches()
                    end,
                }
            )
        end

        if wants_metric(args, { "picker linked() open [prewarmed]" }) then
            add_metric(
                "picker linked() open [prewarmed]",
                results,
                bench,
                function()
                    open_picker_and_close(linked_picker({ sort_by = "mtime" }))
                end,
                5,
                0,
                {
                    before_each = function()
                        clear_picker_caches()
                        prewarm_picker_state()
                    end,
                }
            )
        end

        if wants_metric(args, { "picker linked() ready [cold]" }) then
            add_metric(
                "picker linked() ready [cold]",
                results,
                bench,
                function()
                    measure_progressive_picker_ready(function()
                        return linked_picker({ sort_by = "mtime", _measure_ready_only = true })
                    end)
                end,
                5,
                0,
                {
                    before_each = function()
                        clear_picker_caches()
                    end,
                }
            )
        end

        if wants_metric(args, { "picker linked() ready [prewarmed]" }) then
            add_metric(
                "picker linked() ready [prewarmed]",
                results,
                bench,
                function()
                    measure_progressive_picker_ready(function()
                        return linked_picker({ sort_by = "mtime", _measure_ready_only = true })
                    end)
                end,
                5,
                0,
                {
                    before_each = function()
                        clear_picker_caches()
                        prewarm_picker_state()
                    end,
                }
            )
        end

        if wants_metric(args, { "picker orphans() open [cold]" }) then
            add_metric(
                "picker orphans() open [cold]",
                results,
                bench,
                function()
                    open_picker_and_close(orphans_picker({ sort_by = "mtime" }))
                end,
                5,
                0,
                {
                    before_each = function()
                        clear_picker_caches()
                    end,
                }
            )
        end

        if wants_metric(args, { "picker orphans() open [prewarmed]" }) then
            add_metric(
                "picker orphans() open [prewarmed]",
                results,
                bench,
                function()
                    open_picker_and_close(orphans_picker({ sort_by = "mtime" }))
                end,
                5,
                0,
                {
                    before_each = function()
                        clear_picker_caches()
                        prewarm_picker_state()
                    end,
                }
            )
        end

        if wants_metric(args, { "picker orphans() ready [cold]" }) then
            add_metric(
                "picker orphans() ready [cold]",
                results,
                bench,
                function()
                    measure_progressive_picker_ready(function()
                        return orphans_picker({ sort_by = "mtime", _measure_ready_only = true })
                    end)
                end,
                5,
                0,
                {
                    before_each = function()
                        clear_picker_caches()
                    end,
                }
            )
        end

        if wants_metric(args, { "picker orphans() ready [prewarmed]" }) then
            add_metric(
                "picker orphans() ready [prewarmed]",
                results,
                bench,
                function()
                    measure_progressive_picker_ready(function()
                        return orphans_picker({ sort_by = "mtime", _measure_ready_only = true })
                    end)
                end,
                5,
                0,
                {
                    before_each = function()
                        clear_picker_caches()
                        prewarm_picker_state()
                    end,
                }
            )
        end

        if wants_metric(args, { "picker inbox() open [cold]" }) then
            add_metric(
                "picker inbox() open [cold]",
                results,
                bench,
                function()
                    open_picker_and_close(inbox_picker())
                end,
                5,
                0,
                {
                    before_each = function()
                        clear_picker_caches()
                    end,
                }
            )
        end

        if wants_metric(args, { "picker inbox() open [prewarmed]" }) then
            add_metric(
                "picker inbox() open [prewarmed]",
                results,
                bench,
                function()
                    open_picker_and_close(inbox_picker())
                end,
                5,
                0,
                {
                    before_each = function()
                        clear_picker_caches()
                        prewarm_picker_state()
                    end,
                }
            )
        end

        if wants_metric(args, { "picker inbox() ready [cold]" }) then
            add_metric(
                "picker inbox() ready [cold]",
                results,
                bench,
                function()
                    measure_progressive_picker_ready(function()
                        return inbox_picker({ _measure_ready_only = true })
                    end)
                end,
                5,
                0,
                {
                    before_each = function()
                        clear_picker_caches()
                    end,
                }
            )
        end

        if wants_metric(args, { "picker inbox() ready [prewarmed]" }) then
            add_metric(
                "picker inbox() ready [prewarmed]",
                results,
                bench,
                function()
                    measure_progressive_picker_ready(function()
                        return inbox_picker({ _measure_ready_only = true })
                    end)
                end,
                5,
                0,
                {
                    before_each = function()
                        clear_picker_caches()
                        prewarm_picker_state()
                    end,
                }
            )
        end

        if wants_metric(args, { "picker tags() open [warm]" }) then
            add_metric("picker tags() open [warm]", results, bench, function()
                open_picker_and_close(tags_picker())
            end, 10, 1)
        end

        if wants_metric(args, { "picker tags() open [cold]" }) then
            add_metric(
                "picker tags() open [cold]",
                results,
                bench,
                function()
                    open_picker_and_close(tags_picker())
                end,
                5,
                0,
                {
                    before_each = function()
                        clear_picker_caches()
                    end,
                }
            )
        end

        if wants_metric(args, { "picker properties() open [cold]" }) then
            add_metric(
                "picker properties() open [cold]",
                results,
                bench,
                function()
                    open_picker_and_close(properties_picker())
                end,
                5,
                0,
                {
                    before_each = function()
                        clear_picker_caches()
                    end,
                }
            )
        end

        if wants_metric(args, { "picker properties() open [warm]" }) then
            add_metric("picker properties() open [warm]", results, bench, function()
                open_picker_and_close(properties_picker())
            end, 10, 1)
        end

        if wants_metric(args, { "picker dirs() open [cold]" }) then
            add_metric(
                "picker dirs() open [cold]",
                results,
                bench,
                function()
                    open_picker_and_close(dirs_picker())
                end,
                5,
                0,
                {
                    before_each = function()
                        clear_picker_caches()
                    end,
                }
            )
        end

        if wants_metric(args, { "picker dirs() open [warm]" }) then
            add_metric("picker dirs() open [warm]", results, bench, function()
                open_picker_and_close(dirs_picker())
            end, 10, 1)
        end

        if wants_metric(args, { "picker wikilinks() open [cold]" }) then
            add_metric(
                "picker wikilinks() open [cold]",
                results,
                bench,
                function()
                    open_picker_and_close(wikilinks_picker())
                end,
                5,
                0,
                {
                    before_each = function()
                        clear_picker_caches()
                    end,
                }
            )
        end

        if wants_metric(args, { "picker wikilinks() open [warm]" }) then
            add_metric("picker wikilinks() open [warm]", results, bench, function()
                open_picker_and_close(wikilinks_picker())
            end, 10, 1)
        end
    end

    if wants_metric(args, GRID_METRICS) then
        setup_vault(fixture_dir)
        local Scanner = require("vault.scanner")
        local Notes = require("vault.notes")
        local grid = require("vault.views.grid")
        local raw_paths = Scanner.paths()
        local notes = Notes.from_paths(raw_paths)

        if wants_metric(args, { "Notes.from_paths()" }) then
            add_metric("Notes.from_paths()", results, bench, function()
                Notes.from_paths(raw_paths)
            end, 20, 2)
        end

        if wants_metric(args, { "grid build_records()" }) then
            add_metric("grid build_records()", results, bench, function()
                grid._build_records(notes.map, { "slug", "title", "status", "tags" }, nil)
            end, 20, 2)
        end

        if wants_metric(args, { "grid open() [preloaded]" }) then
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

        if wants_metric(args, { "grid save no-op (:w)" }) then
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

    if wants_metric(args, UPDATE_METRICS) then
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
        if wants_metric(args, { "grid on_save update" }) then
            results[#results + 1] = bench.result("grid on_save update", total_samples)
        end
        add_phase_metrics(results, bench, args, "grid on_save update", phase_samples)

        delete_buffer(bufnr)
        delete_path(update_root)
    end

    if wants_metric(args, RENAME_METRICS) then
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
        if wants_metric(args, { "grid on_save rename" }) then
            results[#results + 1] = bench.result("grid on_save rename", total_samples)
        end
        add_phase_metrics(results, bench, args, "grid on_save rename", phase_samples)

        delete_buffer(bufnr)
        delete_path(rename_root)
    end

    if wants_metric(args, RENAME_BATCH_METRICS) then
        local rename_root = new_temp_vault_copy(fixture_dir, "bench-grid-rename-batch")
        setup_vault(rename_root)
        local Scanner = require("vault.scanner")
        local grid = require("vault.views.grid")
        local raw_paths = Scanner.paths()
        local bufnr = vim.api.nvim_create_buf(false, true)
        local state = make_full_save_state(grid, raw_paths, bufnr, "bench-grid-rename-batch")
        local on_save = grid._make_on_save(state)
        local phase_samples = new_phase_samples()
        local capture_profile = false
        local rename_count = math.min(100, math.max(10, math.floor(args.vault_size / 10)))

        grid._buf_states[bufnr] = state
        io.stderr:write("Measuring: grid on_save rename batch...\n")
        local total_samples = bench.measure(
            function()
                local done_err = "PENDING"
                on_save(make_batch_rename_diff(rename_count), function(err)
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
                    reset_full_save_state(state, raw_paths, grid)
                    grid._vt_undo.clear(bufnr)
                    Scanner.invalidate_notes_cache()
                    Scanner.clear_rust_cache()
                end,
                after_each = function()
                    local snap = grid._vt_undo.restore(bufnr)
                    if snap then
                        grid._apply_undo(bufnr, snap)
                    end
                end,
            }
        )
        if wants_metric(args, { "grid on_save rename batch" }) then
            results[#results + 1] = bench.result("grid on_save rename batch", total_samples)
        end
        add_phase_metrics(results, bench, args, "grid on_save rename batch", phase_samples)

        grid._buf_states[bufnr] = nil
        delete_buffer(bufnr)
        delete_path(rename_root)
    end

    if wants_metric(args, { "Watcher.handle_rename()" }) then
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

    if #results == 0 then
        error("benchmark run completed without collecting any metrics")
    end

    bench.print_hotspots(results, args.top)
    bench.print_table(results)

    local report = bench.build_report(results)
    report.vault_size = args.vault_size
    report.filter = args.filter or vim.NIL

    local json = bench.write_report(report, args.out)
    io.stdout:write(json .. "\n")
    io.stderr:write("Results saved to " .. args.out .. "\n")
end

main()
vim.cmd("qall!")
