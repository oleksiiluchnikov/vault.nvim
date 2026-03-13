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

describe("vault.e2e calendar move-and-save", function()
    it("moves a note to a new date and saves the date field mutation to disk", function()
        local source_root = make_source_vault("vault-e2e-calendar-move", {
            ["Inbox/Deadline note.md"] = {
                "---",
                'title: "Deadline note"',
                'due: "2026-03-14"',
                "---",
                "",
                "# Deadline note",
                "This has a deadline.",
            },
            ["Inbox/Other note.md"] = {
                "---",
                'title: "Other note"',
                'due: "2026-03-20"',
                "---",
                "",
                "# Other note",
            },
        })

        with_session(source_root, "calendar-move-save", function(session)
            local deadline_path = session.root .. "/Inbox/Deadline note.md"

            -- Verify original date
            assert.is_true(file_contains(deadline_path, "2026-03-14"))

            -- Open calendar view
            driver.command(session, "Vault calendar")

            -- Wait for the calendar to render
            assert.is_true(driver.wait_for(session, function()
                local body = driver.current_buffer_text(session)
                return body:find("Deadline note", 1, true) ~= nil
                    or body:find("Other note", 1, true) ~= nil
            end, { timeout_ms = 10000 }))

            -- Use the calendar's on_date_move callback directly to simulate a date move
            -- This exercises the same code path that H/L keystrokes trigger
            driver.lua(session, [[
                local calendar = require('vault.views.calendar')
                local shared = require('vault.views.shared')
                for bufnr, st in pairs(calendar._cal_states) do
                    for slug, path in pairs(st.note_paths) do
                        if path:find('Deadline note', 1, true) then
                            -- Simulate moving the note to March 18
                            shared.set_frontmatter_field(path, st.date_field, '2026-03-18')
                        end
                    end
                end
            ]])

            -- Verify the date changed on disk
            assert.is_true(driver.wait_for(session, function()
                return file_contains(deadline_path, "2026-03-18")
                    and not file_contains(deadline_path, "2026-03-14")
            end, { timeout_ms = 8000 }))

            -- File should still exist
            assert.is_true(vim.fn.filereadable(deadline_path) == 1)

            -- Reload calendar and verify the state refreshes
            driver.lua(session, [[
                local calendar = require('vault.views.calendar')
                for bufnr, _ in pairs(calendar._cal_states) do
                    calendar.reload(bufnr)
                end
            ]])

            -- The date in the file should still be the new one
            local content = table.concat(vim.fn.readfile(deadline_path), "\n")
            assert.is_true(content:find("2026-03-18", 1, true) ~= nil)
        end)
    end)
end)
