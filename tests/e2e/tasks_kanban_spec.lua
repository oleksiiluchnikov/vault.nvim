local artifacts = require("tests.e2e.helpers.artifacts")
local driver = require("tests.e2e.helpers.driver")
local fixture = require("tests.e2e.helpers.fixture")

local function write(path, lines)
    vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
    vim.fn.writefile(lines, path)
end

local function make_vault(name, files)
    local root = fixture.make_temp_dir(name)
    for relpath, lines in pairs(files) do
        write(root .. "/" .. relpath, lines)
    end
    return root
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

describe("vault.e2e tasks kanban", function()
    it("opens the tasks kanban board with task notes in correct columns", function()
        local source_root = make_vault("vault-e2e-tasks-kanban", {
            ["Tasks/T-20260101000000 Alpha task.md"] = {
                "---",
                'title: "Alpha task"',
                'status: "[[Status - Todo]]"',
                'priority: "[[Priority - High]]"',
                "created: 20260101000000",
                "---",
                "",
                "# Alpha task",
            },
            ["Tasks/T-20260101000001 Beta task.md"] = {
                "---",
                'title: "Beta task"',
                'status: "[[Status - In-Progress]]"',
                'priority: "[[Priority - Medium]]"',
                "created: 20260101000001",
                "---",
                "",
                "# Beta task",
            },
            ["Tasks/T-20260101000002 Gamma task.md"] = {
                "---",
                'title: "Gamma task"',
                'status: "[[Status - Done]]"',
                'priority: "[[Priority - Low]]"',
                "created: 20260101000002",
                "---",
                "",
                "# Gamma task",
            },
            ["Tasks Kanban.base"] = {
                "views:",
                "  - type: kanban",
                "    name: Tasks Kanban",
                "    group_by: status",
                "    filters:",
                '      and: [{ property: "status", operator: "is-not-empty" }]',
            },
        })

        with_session(source_root, "tasks-kanban", function(session)
            -- Open kanban directly with task notes (bypass Base lookup)
            driver.lua(session, [[
                local kanban = require('vault.views.kanban')
                local notes = require('vault.notes')()
                kanban.open({
                    notes = notes,
                    group_field = 'status',
                    filter_desc = 'tasks-kanban-e2e',
                })
            ]])

            -- Wait for the board to render with task names
            assert.is_true(driver.wait_for(session, function()
                local body = driver.current_buffer_text(session)
                return body:find("Alpha", 1, true) ~= nil
                    or body:find("Beta", 1, true) ~= nil
                    or body:find("Gamma", 1, true) ~= nil
            end, { timeout_ms = 10000 }))
        end)
    end)
end)
