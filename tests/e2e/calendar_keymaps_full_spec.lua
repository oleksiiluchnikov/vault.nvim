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

local function read_file(path)
    if vim.fn.filereadable(path) == 0 then
        return nil
    end
    return table.concat(vim.fn.readfile(path), "\n")
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

local function focus_calendar_text(session, needle)
    driver.lua(
        session,
        string.format(
            [[ 
        local needle = %q
        local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
        for i, line in ipairs(lines) do
            local col = line:find(needle, 1, true)
            if col then
                vim.api.nvim_win_set_cursor(0, { i, col - 1 })
                return
            end
        end
        error("calendar text not found: " .. needle)
    ]],
            needle
        )
    )
end

local function calendar_month(session)
    driver.lua(
        session,
        [[
        vim.g._calendar_month = ""
        local calendar = require("vault.views.calendar")
        for _, st in pairs(calendar._cal_states) do
            if st.cal and st.cal._st then
                vim.g._calendar_month = string.format("%04d-%02d", st.cal._st.year, st.cal._st.month)
                return
            end
        end
        error("calendar state not found")
    ]]
    )
    return driver.expr(session, "g:_calendar_month")
end

describe("vault.e2e calendar keymaps full", function()
    it("moves a note date with H and L and persists the frontmatter date", function()
        local source_root = make_vault("vault-e2e-calendar-keymaps-full", {
            ["Inbox/Alpha note.md"] = {
                "---",
                'title: "Alpha note"',
                'due: "2026-03-14"',
                "---",
                "",
                "# Alpha note",
            },
            ["Inbox/Beta note.md"] = {
                "---",
                'title: "Beta note"',
                'due: "2026-03-18"',
                "---",
                "",
                "# Beta note",
            },
            ["Inbox/Gamma note.md"] = {
                "---",
                'title: "Gamma note"',
                'due: "2026-03-25"',
                "---",
                "",
                "# Gamma note",
            },
        })

        with_session(source_root, "calendar-keymaps-full-move", function(session)
            local alpha_path = session.root .. "/Inbox/Alpha note.md"

            driver.command(session, "Vault calendar date=due primary=title")

            assert.is_true(driver.wait_for(session, function()
                local body = driver.current_buffer_text(session)
                return body:find("Alpha note", 1, true) ~= nil
            end, { timeout_ms = 10000 }))

            focus_calendar_text(session, "Alpha note")
            driver.keys(session, "L")

            assert.is_true(driver.wait_for(session, function()
                local content = read_file(alpha_path)
                return content ~= nil
                    and content:find("2026-03-15", 1, true) ~= nil
                    and content:find("2026-03-14", 1, true) == nil
            end, { timeout_ms = 10000 }))

            focus_calendar_text(session, "Alpha note")
            driver.keys(session, "H")

            assert.is_true(driver.wait_for(session, function()
                local content = read_file(alpha_path)
                return content ~= nil
                    and content:find("2026-03-14", 1, true) ~= nil
                    and content:find("2026-03-15", 1, true) == nil
            end, { timeout_ms = 10000 }))
        end)
    end)

    it("navigates months with ]m and [m", function()
        local source_root = make_vault("vault-e2e-calendar-keymaps-nav", {
            ["Inbox/March note.md"] = {
                "---",
                'title: "March note"',
                'due: "2026-03-14"',
                "---",
                "",
                "# March note",
            },
            ["Inbox/April note.md"] = {
                "---",
                'title: "April note"',
                'due: "2026-04-07"',
                "---",
                "",
                "# April note",
            },
        })

        with_session(source_root, "calendar-keymaps-full-nav", function(session)
            driver.command(session, "Vault calendar date=due primary=title")

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
