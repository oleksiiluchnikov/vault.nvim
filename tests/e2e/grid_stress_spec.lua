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

local function replace_in_current_line(session, before, after)
    driver.lua(session, string.format(
        [[
            local before = %q
            local after = %q
            local row = vim.api.nvim_win_get_cursor(0)[1] - 1
            local line = vim.api.nvim_buf_get_lines(0, row, row + 1, false)[1]
            if not line or not line:find(before, 1, true) then
                error("current line missing text: " .. before)
            end
            line = line:gsub(before, after, 1)
            vim.api.nvim_buf_set_lines(0, row, row + 1, false, { line })
        ]],
        before,
        after
    ))
end

describe("vault.e2e grid stress", function()
    it("trashes a deleted row on write", function()
        local source_root = make_vault("vault-e2e-grid-stress-delete", {
            ["Inbox/delete-target.md"] = {
                "---",
                'title: "delete target"',
                'status: "active"',
                "---",
                "",
                "# Delete target",
            },
            ["Inbox/rename-source.md"] = {
                "---",
                'title: "rename source"',
                'status: "active"',
                "---",
                "",
                "# Rename source",
            },
            ["Inbox/status-target.md"] = {
                "---",
                'title: "status target"',
                'status: "active"',
                "---",
                "",
                "# Status target",
            },
        })

        with_session(source_root, "grid-stress-delete", function(session)
            local deleted_path = session.root .. "/Inbox/delete-target.md"

            driver.command(session, "Vault process file.name,status")

            assert.is_true(driver.wait_for(session, function()
                local body = driver.current_buffer_text(session)
                return body:find("delete%-target") ~= nil
            end, { timeout_ms = 10000 }))

            move_cursor_to_line_containing(session, "delete-target")
            driver.keys(session, "<Esc>dd")
            driver.command(session, "write")
            driver.keys(session, "y")

            assert.is_true(driver.wait_for(session, function()
                local trash_files = vim.fn.glob(session.root .. "/.trash/delete-target*.md", false, true)
                return vim.fn.filereadable(deleted_path) == 0 and #trash_files >= 1
            end, { timeout_ms = 10000 }))
        end)
    end)

    it("renames files on disk after a bulk substitute", function()
        local source_root = make_vault("vault-e2e-grid-stress-rename", {
            ["Inbox/old-title.md"] = {
                "---",
                'title: "rename note"',
                'status: "active"',
                "---",
                "",
                "# Rename note",
            },
            ["Inbox/keep-note.md"] = {
                "---",
                'title: "keep note"',
                'status: "done"',
                "---",
                "",
                "# Keep note",
            },
        })

        with_session(source_root, "grid-stress-rename", function(session)
            local old_path = session.root .. "/Inbox/old-title.md"
            local new_path = session.root .. "/Inbox/new-title.md"

            driver.command(session, "Vault process file.name,status")

            assert.is_true(driver.wait_for(session, function()
                return driver.current_buffer_text(session):find("old%-title") ~= nil
            end, { timeout_ms = 10000 }))

            driver.command(session, "%s/old-title/new-title/")
            driver.command(session, "write")

            assert.is_true(driver.wait_for(session, function()
                return vim.fn.filereadable(old_path) == 0 and vim.fn.filereadable(new_path) == 1
            end, { timeout_ms = 10000 }))
        end)
    end)

    it("writes edited status fields back to frontmatter", function()
        local source_root = make_vault("vault-e2e-grid-stress-status", {
            ["Inbox/status-note.md"] = {
                "---",
                'title: "status note"',
                'status: "active"',
                "---",
                "",
                "# Status note",
            },
            ["Inbox/other-note.md"] = {
                "---",
                'title: "other note"',
                'status: "done"',
                "---",
                "",
                "# Other note",
            },
        })

        with_session(source_root, "grid-stress-status", function(session)
            local status_path = session.root .. "/Inbox/status-note.md"

            driver.command(session, "Vault process title,status")

            assert.is_true(driver.wait_for(session, function()
                return driver.current_buffer_text(session):find("active", 1, true) ~= nil
            end, { timeout_ms = 10000 }))

            driver.command(session, "%s/active/archived/")
            driver.command(session, "write")

            assert.is_true(driver.wait_for(session, function()
                return read_text(status_path):find("status: archived", 1, true) ~= nil
            end, { timeout_ms = 10000 }))
        end)
    end)

    it("applies edits and deletes together in one write", function()
        local source_root = make_vault("vault-e2e-grid-stress-mixed", {
            ["Inbox/mixed-edit.md"] = {
                "---",
                'title: "mixed edit"',
                'status: "active"',
                "---",
                "",
                "# Mixed edit",
            },
            ["Inbox/mixed-delete.md"] = {
                "---",
                'title: "mixed delete"',
                'status: "done"',
                "---",
                "",
                "# Mixed delete",
            },
            ["Inbox/mixed-keep.md"] = {
                "---",
                'title: "mixed keep"',
                'status: "active"',
                "---",
                "",
                "# Mixed keep",
            },
        })

        with_session(source_root, "grid-stress-mixed", function(session)
            local edit_path = session.root .. "/Inbox/mixed-edit.md"
            local delete_path = session.root .. "/Inbox/mixed-delete.md"

            driver.command(session, "Vault process file.name,status")

            assert.is_true(driver.wait_for(session, function()
                local body = driver.current_buffer_text(session)
                return body:find("mixed%-edit") ~= nil and body:find("mixed%-delete") ~= nil
            end, { timeout_ms = 10000 }))

            move_cursor_to_line_containing(session, "mixed-edit")
            replace_in_current_line(session, "active", "archived")
            move_cursor_to_line_containing(session, "mixed-delete")
            driver.keys(session, "<Esc>dd")
            driver.command(session, "write")
            driver.keys(session, "y")

            assert.is_true(driver.wait_for(session, function()
                local trash_files = vim.fn.glob(session.root .. "/.trash/mixed-delete*.md", false, true)
                return vim.fn.filereadable(edit_path) == 1
                    and read_text(edit_path):find("status: archived", 1, true) ~= nil
                    and vim.fn.filereadable(delete_path) == 0
                    and #trash_files >= 1
            end, { timeout_ms = 10000 }))
        end)
    end)
end)
