local artifacts = require("tests.e2e.helpers.artifacts")
local driver = require("tests.e2e.helpers.driver")
local fixture = require("tests.e2e.helpers.fixture")

local function write(path, lines)
    vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
    vim.fn.writefile(lines, path)
end

local function make_source_vault(name, files)
    local root = fixture.make_temp_dir(name)
    for relpath, lines in pairs(files) do
        write(root .. "/" .. relpath, lines)
    end
    return root
end

local function file_contains(path, needle)
    if vim.fn.filereadable(path) == 0 then
        return false
    end
    return table.concat(vim.fn.readfile(path), "\n"):find(needle, 1, true) ~= nil
end

local function task_files(root)
    return vim.fn.glob(root .. "/Tasks/*.md", false, true)
end

local function with_session(source_root, scenario, fn)
    local session = driver.start({ source_root = source_root, scenario = scenario })
    local ok, err = pcall(fn, session)
    if not ok then
        driver.capture(session)
        artifacts.write_vault_diff(session.artifacts_dir, source_root, session.root)
        driver.stop(session)
        error(err)
    end
    driver.stop(session)
end

describe("vault.e2e tasks lifecycle", function()
    it("covers :Vault tasks promote from a real note line", function()
        local source_root = make_source_vault("vault-e2e-tasks-promote", {
            ["Inbox/Capture.md"] = {
                "- Build E2E harness",
            },
        })

        with_session(source_root, "tasks-promote", function(session)
            local capture_path = session.root .. "/Inbox/Capture.md"
            driver.command(session, "edit " .. vim.fn.fnameescape(capture_path))
            driver.command(session, "1")
            driver.command(session, "Vault tasks promote")

            assert.is_true(driver.wait_for(session, function()
                return #task_files(session.root) == 1
            end))

            local text = driver.current_buffer_text(session)
            assert.is_true(text:find("%-%s*%[%[T%-", 1) ~= nil)

            local created = task_files(session.root)[1]
            assert.is_true(file_contains(created, 'title: "Build E2E harness"'))
        end)
    end)

    it("covers :Vault tasks status and :Vault tasks pick-next", function()
        local source_root = make_source_vault("vault-e2e-tasks-status", {
            ["Tasks/T-20260312000100 High unblocked.md"] = {
                "---",
                'status: "[[Status - Backlog]]"',
                'priority: "[[Priority - High]]"',
                'title: "High unblocked"',
                "blocked_by: []",
                "---",
                "",
                "# High unblocked",
            },
            ["Tasks/T-20260312000101 Critical blocked.md"] = {
                "---",
                'status: "[[Status - Todo]]"',
                'priority: "[[Priority - Critical]]"',
                'title: "Critical blocked"',
                "blocked_by:",
                '  - "[[T-20260312000999 Missing blocker]]"',
                "---",
                "",
                "# Critical blocked",
            },
        })

        with_session(source_root, "tasks-status-pick-next", function(session)
            local task_path = session.root .. "/Tasks/T-20260312000100 High unblocked.md"
            driver.command(session, "edit " .. vim.fn.fnameescape(task_path))
            driver.command(session, "Vault tasks status Status - Todo")

            assert.is_true(driver.wait_for(session, function()
                return file_contains(task_path, "[[Status - Todo]]")
            end))

            driver.command(session, "bdelete!")
            driver.command(session, "Vault tasks pick-next")

            assert.is_true(driver.wait_for(session, function()
                return driver.current_buffer_name(session):find("T%-20260312000100 High unblocked%.md") ~= nil
            end))
        end)
    end)

    it("covers :Vault tasks recur now", function()
        local source_root = make_source_vault("vault-e2e-tasks-recur-now", {
            ["Tasks/T-20260312000200-Daily-recurring.md"] = {
                "---",
                'title: "Daily recurring"',
                'status: "[[Status - Todo]]"',
                'executor: "[[Executor - Human]]"',
                'category: "[[Category - Green Task]]"',
                'priority: "[[Priority - Medium]]"',
                'repeat: "every day when done"',
                'due: "[[2026-03-06 Friday]]"',
                "---",
                "",
                "# Daily recurring",
            },
        })

        with_session(source_root, "tasks-recur-now", function(session)
            local src = session.root .. "/Tasks/T-20260312000200-Daily-recurring.md"
            driver.command(session, "edit " .. vim.fn.fnameescape(src))
            driver.command(session, "Vault tasks recur now")

            assert.is_true(driver.wait_for(session, function()
                return #task_files(session.root) == 2
            end, { timeout_ms = 8000 }))

            assert.is_true(file_contains(src, "last_recur_spawned"))
        end)
    end)

    it("covers :Vault tasks recur sweep", function()
        local source_root = make_source_vault("vault-e2e-tasks-recur-sweep", {
            ["Tasks/T-20260312000300 Weekly recurring done.md"] = {
                "---",
                'title: "Weekly recurring done"',
                'status: "[[Status - Done]]"',
                'executor: "[[Executor - Human]]"',
                'category: "[[Category - Green Task]]"',
                'priority: "[[Priority - Medium]]"',
                'repeat: "every week"',
                'due: "[[2026-03-06 Friday]]"',
                "---",
                "",
                "# Weekly recurring done",
            },
        })

        with_session(source_root, "tasks-recur-sweep", function(session)
            driver.command(session, "Vault tasks recur sweep")

            assert.is_true(driver.wait_for(session, function()
                return #task_files(session.root) == 2
            end, { timeout_ms = 8000 }))

            local src = session.root .. "/Tasks/T-20260312000300 Weekly recurring done.md"
            assert.is_true(file_contains(src, "last_recur_spawned"))
        end)
    end)

    it("covers :Vault tasks doctor fix", function()
        local source_root = make_source_vault("vault-e2e-tasks-doctor", {
            ["Tasks/T-20260312000400 Plain status.md"] = {
                "---",
                'title: "Plain status"',
                'status: "Status - Todo"',
                "---",
                "",
                "# Plain status",
            },
        })

        with_session(source_root, "tasks-doctor-fix", function(session)
            driver.command(session, "Vault tasks doctor fix")
            local path = session.root .. "/Tasks/T-20260312000400 Plain status.md"
            assert.is_true(driver.wait_for(session, function()
                return file_contains(path, 'status: "[[Status - Todo]]"')
            end, { timeout_ms = 8000 }))
        end)
    end)
end)
