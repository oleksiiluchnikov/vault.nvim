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

describe("vault.e2e list view variants", function()
    local source_root

    before_each(function()
        source_root = make_vault("vault-e2e-list-view-variants", {
            ["Inbox/inbox-orphan.md"] = {
                "---",
                'title: "inbox orphan"',
                'status: "active"',
                "---",
                "",
                "# Inbox orphan",
            },
            ["Projects/linked-note.md"] = {
                "---",
                'title: "linked note"',
                'status: "active"',
                "---",
                "",
                "# Linked note",
                "Points to [[Projects/linked-target]].",
            },
            ["Projects/linked-target.md"] = {
                "---",
                'title: "linked target"',
                'status: "done"',
                "---",
                "",
                "# Linked target",
            },
        })
    end)

    it("opens the default list view", function()
        with_session(source_root, "list-view-variants-default", function(session)
            driver.command(session, "Vault list")

            assert.is_true(driver.wait_for(session, function()
                local body = driver.current_buffer_text(session)
                return body:find("inbox orphan", 1, true) ~= nil
                    and body:find("linked note", 1, true) ~= nil
                    and body:find("linked target", 1, true) ~= nil
            end, { timeout_ms = 10000 }))
        end)
    end)

    it("opens the orphan-only list view", function()
        with_session(source_root, "list-view-variants-orphans", function(session)
            driver.command(session, "Vault list orphans")

            assert.is_true(driver.wait_for(session, function()
                local body = driver.current_buffer_text(session)
                return body:find("inbox orphan", 1, true) ~= nil
                    and body:find("linked note", 1, true) == nil
                    and body:find("linked target", 1, true) == nil
            end, { timeout_ms = 10000 }))
        end)
    end)

    it("opens the Inbox directory list view", function()
        with_session(source_root, "list-view-variants-dir", function(session)
            driver.command(session, "Vault list dir Inbox")

            assert.is_true(driver.wait_for(session, function()
                local body = driver.current_buffer_text(session)
                return body:find("inbox orphan", 1, true) ~= nil
                    and body:find("linked note", 1, true) == nil
                    and body:find("linked target", 1, true) == nil
            end, { timeout_ms = 10000 }))
        end)
    end)

    it("toggles status with x and persists on write", function()
        with_session(source_root, "list-view-toggle-save", function(session)
            driver.command(session, "Vault list title,status")

            assert.is_true(driver.wait_for(session, function()
                return driver.current_buffer_text(session):find("inbox orphan", 1, true) ~= nil
            end, { timeout_ms = 10000 }))

            driver.lua(
                session,
                [[
                local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
                for i, line in ipairs(lines) do
                    if line:find("inbox orphan", 1, true) then
                        vim.api.nvim_win_set_cursor(0, { i, 0 })
                        break
                    end
                end
            ]]
            )
            driver.keys(session, "x")
            driver.command(session, "write")

            assert.is_true(driver.wait_for(session, function()
                local content =
                    table.concat(vim.fn.readfile(session.root .. "/Inbox/inbox-orphan.md"), "\n")
                return content:find('status: "done"', 1, true) ~= nil
                    or content:find("status: done", 1, true) ~= nil
            end, { timeout_ms = 10000 }))
        end)
    end)

    it("reload keeps directory filter and includes newly matching files", function()
        with_session(source_root, "list-view-filtered-reload", function(session)
            driver.command(session, "Vault list dir Inbox")

            assert.is_true(driver.wait_for(session, function()
                return driver.current_buffer_text(session):find("inbox orphan", 1, true) ~= nil
            end, { timeout_ms = 10000 }))

            driver.lua(
                session,
                [[
                local path = vim.env.VAULT_TEST_ROOT .. "/Inbox/new-inbox.md"
                vim.fn.writefile({ "---", 'title: "new inbox"', 'status: "active"', "---", "", "# New inbox" }, path)
                require("vault.scanner").invalidate_notes_cache()
            ]]
            )
            driver.keys(session, "<C-r>")

            assert.is_true(driver.wait_for(session, function()
                local body = driver.current_buffer_text(session)
                return body:find("new inbox", 1, true) ~= nil
                    and body:find("linked note", 1, true) == nil
            end, { timeout_ms = 10000 }))
        end)
    end)

    it("ignores readonly file columns on save", function()
        with_session(source_root, "list-view-readonly-ignored", function(session)
            driver.command(session, "Vault list title,file.name")

            assert.is_true(driver.wait_for(session, function()
                return driver.current_buffer_text(session):find("inbox orphan", 1, true) ~= nil
            end, { timeout_ms = 10000 }))

            driver.replace_in_current_buffer(session, "inbox-orphan", "renamed-by-list")
            driver.command(session, "write")

            assert.is_true(driver.wait_for(session, function()
                local original_exists = vim.fn.filereadable(
                    session.root .. "/Inbox/inbox-orphan.md"
                ) == 1
                local renamed_exists = vim.fn.filereadable(
                    session.root .. "/Inbox/renamed-by-list.md"
                ) == 1
                local content =
                    table.concat(vim.fn.readfile(session.root .. "/Inbox/inbox-orphan.md"), "\n")
                return original_exists
                    and not renamed_exists
                    and content:find("file.name", 1, true) == nil
            end, { timeout_ms = 10000 }))
        end)
    end)
end)
