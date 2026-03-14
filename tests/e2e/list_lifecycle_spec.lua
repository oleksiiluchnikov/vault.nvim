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
    vim.wait(1100)
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

local function read_text(path)
    return table.concat(vim.fn.readfile(path), "\n")
end

local function move_cursor_to_line_containing(session, needle)
    driver.lua(session, string.format(
        [[
            local needle = %q
            local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
            for idx, line in ipairs(lines) do
                if line:find(needle, 1, true) then
                    vim.api.nvim_win_set_cursor(0, { idx, 0 })
                    return
                end
            end
            error("needle not found: " .. needle)
        ]],
        needle
    ))
end

describe("vault.e2e list lifecycle", function()
    it("opens list view with rendered notes", function()
        local source_root = make_vault("vault-e2e-list-open", {
            ["Inbox/list-alpha.md"] = {
                "---",
                'title: "list alpha"',
                'status: "active"',
                "---",
                "",
                "# List alpha",
            },
            ["Inbox/list-beta.md"] = {
                "---",
                'title: "list beta"',
                'status: "done"',
                "---",
                "",
                "# List beta",
            },
        })

        with_session(source_root, "list-lifecycle-open", function(session)
            driver.command(session, "Vault list")

            assert.is_true(driver.wait_for(session, function()
                local body = driver.current_buffer_text(session)
                return driver.current_buffer_name(session):find("vault://list-process/", 1, true) ~= nil
                    and body:find("list alpha", 1, true) ~= nil
                    and body:find("list beta", 1, true) ~= nil
            end, { timeout_ms = 10000 }))
        end)
    end)

    it("toggles status with x and writes it to disk", function()
        local source_root = make_vault("vault-e2e-list-toggle", {
            ["Inbox/toggle-me.md"] = {
                "---",
                'title: "toggle me"',
                'status: "active"',
                "---",
                "",
                "# Toggle me",
            },
            ["Inbox/stay-done.md"] = {
                "---",
                'title: "stay done"',
                'status: "done"',
                "---",
                "",
                "# Stay done",
            },
        })

        with_session(source_root, "list-lifecycle-toggle", function(session)
            local note_path = session.root .. "/Inbox/toggle-me.md"

            driver.command(session, "Vault list")

            assert.is_true(driver.wait_for(session, function()
                return driver.current_buffer_text(session):find("toggle me", 1, true) ~= nil
            end, { timeout_ms = 10000 }))

            move_cursor_to_line_containing(session, "toggle me")
            driver.keys(session, "<Esc>x")

            assert.is_true(driver.wait_for(session, function()
                return read_text(note_path):find("status: done", 1, true) ~= nil
            end, { timeout_ms = 10000 }))
        end)
    end)

    it("writes edited list fields back to frontmatter", function()
        local source_root = make_vault("vault-e2e-list-edit", {
            ["Inbox/edit-me.md"] = {
                "---",
                'title: "edit me"',
                'status: "active"',
                "---",
                "",
                "# Edit me",
            },
            ["Inbox/other-row.md"] = {
                "---",
                'title: "other row"',
                'status: "done"',
                "---",
                "",
                "# Other row",
            },
        })

        with_session(source_root, "list-lifecycle-edit", function(session)
            local note_path = session.root .. "/Inbox/edit-me.md"

            driver.command(session, "Vault list")

            assert.is_true(driver.wait_for(session, function()
                return driver.current_buffer_text(session):find("edit me", 1, true) ~= nil
            end, { timeout_ms = 10000 }))

            driver.command(session, "%s/edit me/edited title/")
            driver.command(session, "write")

            assert.is_true(driver.wait_for(session, function()
                return read_text(note_path):find("title: edited title", 1, true) ~= nil
            end, { timeout_ms = 10000 }))
        end)
    end)
end)
