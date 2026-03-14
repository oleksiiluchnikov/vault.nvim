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
end)
