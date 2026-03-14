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

local function calendar_month(session)
    driver.lua(session, [[
        vim.g._calendar_month = ""
        local calendar = require("vault.views.calendar")
        for _, st in pairs(calendar._cal_states) do
            if st.cal and st.cal._st then
                vim.g._calendar_month = string.format("%04d-%02d", st.cal._st.year, st.cal._st.month)
                return
            end
        end
        error("calendar state not found")
    ]])
    return driver.expr(session, "g:_calendar_month")
end

describe("vault.e2e calendar date field types", function()
    it("renders ISO string date fields on the calendar", function()
        local source_root = make_vault("vault-e2e-calendar-date-types", {
            ["Inbox/alpha.md"] = {
                "---",
                'title: "Alpha record"',
                'date: "2026-03-10"',
                "---",
                "",
                "# Alpha record",
            },
            ["Inbox/beta.md"] = {
                "---",
                'title: "Beta record"',
                'date: "2026-03-16"',
                "---",
                "",
                "# Beta record",
            },
            ["Inbox/gamma.md"] = {
                "---",
                'title: "Gamma record"',
                'date: "2026-03-28"',
                "---",
                "",
                "# Gamma record",
            },
        })

        with_session(source_root, "calendar-date-types-open", function(session)
            driver.command(session, "Vault calendar date=date primary=title")

            assert.is_true(driver.wait_for(session, function()
                local body = driver.current_buffer_text(session)
                return body:find("Alpha record", 1, true) ~= nil
                    and body:find("Beta record", 1, true) ~= nil
                    and body:find("Gamma record", 1, true) ~= nil
            end, { timeout_ms = 10000 }))
        end)
    end)

    it("navigates months with ]m and [m", function()
        local source_root = make_vault("vault-e2e-calendar-date-types-nav", {
            ["Inbox/march-note.md"] = {
                "---",
                'title: "March record"',
                'date: "2026-03-10"',
                "---",
                "",
                "# March record",
            },
            ["Inbox/april-note.md"] = {
                "---",
                'title: "April record"',
                'date: "2026-04-12"',
                "---",
                "",
                "# April record",
            },
        })

        with_session(source_root, "calendar-date-types-nav", function(session)
            driver.command(session, "Vault calendar date=date primary=title")

            assert.is_true(driver.wait_for(session, function()
                return calendar_month(session) == "2026-03"
            end, { timeout_ms = 10000 }))

            driver.keys(session, "]m")
            assert.is_true(driver.wait_for(session, function()
                return calendar_month(session) == "2026-04"
            end, { timeout_ms = 10000 }))

            driver.keys(session, "[m")
            assert.is_true(driver.wait_for(session, function()
                return calendar_month(session) == "2026-03"
            end, { timeout_ms = 10000 }))
        end)
    end)
end)
