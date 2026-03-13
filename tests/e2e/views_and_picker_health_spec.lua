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

describe("vault.e2e views and picker health", function()
    it("opens notes, tags, properties, and bases pickers with highlight groups", function()
        local source_root = make_source_vault("vault-e2e-picker-health", {
            ["Inbox/Board note.md"] = {
                "---",
                'title: "Board note"',
                "status: active",
                'due: "[[2026-03-14 Saturday]]"',
                "tags:",
                "  - wash-face",
                'theme: "fast"',
                "---",
                "# Board note",
                "body body body body body body body body body body",
            },
            ["Process/Tasks.base"] = {
                "views:",
                "  - type: table",
                "    name: Tasks",
                "    filters:",
                "      and: []",
            },
        })

        with_session(source_root, "picker-health", function(session)
            driver.command(session, "Vault notes")
            assert.are.equal("1", driver.expr(session, "hlexists('VaultNoteContent1')"))
            driver.keys(session, "<Esc>")

            driver.command(session, "Vault tags")
            assert.are.equal("1", driver.expr(session, "hlexists('VaultTag1')"))
            driver.keys(session, "<Esc>")

            driver.command(session, "Vault properties")
            assert.are.equal("1", driver.expr(session, "hlexists('VaultProperty1')"))
            driver.keys(session, "<Esc>")

            driver.command(session, "Vault bases")
            assert.are.equal("1", driver.expr(session, "hlexists('VaultBase1')"))
            driver.keys(session, "<Esc>")
        end)
    end)

    it("opens kanban and calendar views on cloned data", function()
        local source_root = make_source_vault("vault-e2e-view-smoke", {
            ["Inbox/Board note.md"] = {
                "---",
                'title: "Board note"',
                "status: active",
                'due: "[[2026-03-14 Saturday]]"',
                "tags:",
                "  - wash-face",
                "---",
                "# Board note",
            },
            ["Inbox/Board note 1.md"] = {
                "---",
                'title: "Board note 1"',
                "status: done",
                'due: "[[2026-03-15 Sunday]]"',
                "---",
                "# Board note 1",
            },
        })

        with_session(source_root, "views-health", function(session)
            local before_files = vim.fn.glob(session.root .. "/**/*.md", false, true)

            driver.command(session, "Vault kanban")
            assert.is_true(driver.wait_for(session, function()
                return driver.current_buffer_text(session):find("Board note", 1, true) ~= nil
            end, { timeout_ms = 8000 }))
            driver.keys(session, "oKanban created<Esc>")
            driver.command(session, "write")
            assert.is_true(driver.wait_for(session, function()
                return #vim.fn.glob(session.root .. "/**/*.md", false, true) >= (#before_files + 1)
            end, { timeout_ms = 8000 }))
            driver.keys(session, "q")

            local after_kanban = vim.fn.glob(session.root .. "/**/*.md", false, true)
            driver.command(session, "Vault calendar")
            assert.is_true(driver.wait_for(session, function()
                return driver.current_buffer_text(session):find("Board note", 1, true) ~= nil
            end, { timeout_ms = 8000 }))
            driver.keys(session, "o")
            assert.is_true(driver.wait_for(session, function()
                return #vim.fn.glob(session.root .. "/**/*.md", false, true) >= (#after_kanban + 1)
            end, { timeout_ms = 8000 }))
            driver.keys(session, "q")
        end)
    end)
end)
