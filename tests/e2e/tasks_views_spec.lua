local driver = require("tests.e2e.helpers.driver")
local fixture = require("tests.e2e.helpers.fixture")
local artifacts = require("tests.e2e.helpers.artifacts")

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
        driver.stop(session)
        error(err)
    end
    driver.stop(session)
end

describe("vault.e2e tasks views", function()
    local source_root
    before_each(function()
        source_root = make_vault("vault-e2e-tasks-views", {
            ["Tasks/T-20260101000000 Backlog item.md"] = {
                "---",
                'title: "Backlog item"',
                'status: "[[Status - Backlog]]"',
                'priority: "[[Priority - Medium]]"',
                "created: 20260101000000",
                "---",
                "",
                "# Backlog item",
            },
            ["Tasks/T-20260101000001 Active item.md"] = {
                "---",
                'title: "Active item"',
                'status: "[[Status - In-Progress]]"',
                'priority: "[[Priority - High]]"',
                "created: 20260101000001",
                "---",
                "",
                "# Active item",
            },
            ["views/Tasks Backlog.base"] = {
                "views:",
                "  - type: table",
                "    name: Tasks Backlog",
                "    filters:",
                '      and: [{ property: "status", operator: "is-not-empty" }]',
            },
        })
    end)

    it("opens tasks list without error", function()
        with_session(source_root, "tasks-list", function(session)
            driver.command(session, "Vault tasks list")
            assert.is_true(driver.wait_for(session, function()
                local ft = driver.expr(session, "&filetype")
                local bufname = driver.current_buffer_name(session)
                return ft == "TelescopePrompt"
                    or bufname:find("vault://", 1, true) ~= nil
            end, { timeout_ms = 10000 }))
        end)
    end)
end)
