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

describe("vault.e2e kanban and calendar filter variants", function()
    local source_root
    before_each(function()
        source_root = make_vault("vault-e2e-view-filters", {
            ["Inbox/dated-note.md"] = {
                "---",
                'title: "dated note"',
                'status: "active"',
                'due: "2026-03-14"',
                "tags:",
                "  - view-test",
                "---",
                "",
                "# Dated note",
            },
            ["Inbox/other-dated.md"] = {
                "---",
                'title: "other dated"',
                'status: "done"',
                'due: "2026-03-20"',
                "tags:",
                "  - view-test",
                "---",
                "",
                "# Other dated",
            },
        })
    end)

    it("opens kanban with dir filter", function()
        with_session(source_root, "kanban-dir", function(session)
            driver.command(session, "Vault kanban dir Inbox")
            assert.is_true(driver.wait_for(session, function()
                local body = driver.current_buffer_text(session)
                return body:find("dated note", 1, true) ~= nil
                    or body:find("other dated", 1, true) ~= nil
            end, { timeout_ms = 10000 }))
        end)
    end)

    it("opens calendar with date field override", function()
        with_session(source_root, "calendar-date", function(session)
            driver.command(session, "Vault calendar date=due")
            assert.is_true(driver.wait_for(session, function()
                local body = driver.current_buffer_text(session)
                return body:find("dated note", 1, true) ~= nil
                    or body:find("other dated", 1, true) ~= nil
            end, { timeout_ms = 10000 }))
        end)
    end)
end)
