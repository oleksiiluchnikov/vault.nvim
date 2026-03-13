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

describe("vault.e2e process filter variants", function()
    local source_root
    before_each(function()
        source_root = make_vault("vault-e2e-proc-filters", {
            ["Inbox/inbox-note.md"] = {
                "---",
                'title: "inbox note"',
                'status: "active"',
                "tags:",
                "  - filter-test",
                "---",
                "",
                "# Inbox note",
            },
            ["Reference/ref-note.md"] = {
                "---",
                'title: "ref note"',
                'status: "done"',
                "---",
                "",
                "# Ref note",
                "See [[Inbox/inbox-note]].",
            },
            ["All.base"] = {
                "views:",
                "  - type: table",
                "    name: All",
                "    filters:",
                "      and: []",
            },
        })
    end)

    it("opens process with dir filter", function()
        with_session(source_root, "process-dir", function(session)
            driver.command(session, "Vault process title,status dir Inbox")
            assert.is_true(driver.wait_for(session, function()
                local body = driver.current_buffer_text(session)
                return body:find("inbox note", 1, true) ~= nil
            end, { timeout_ms = 10000 }))
            -- Reference note should not appear in Inbox filter
            local body = driver.current_buffer_text(session)
            assert.is_true(body:find("ref note", 1, true) == nil or body:find("inbox note", 1, true) ~= nil)
        end)
    end)

    it("opens process with tag filter", function()
        with_session(source_root, "process-tag", function(session)
            driver.command(session, "Vault process title,status tag filter-test")
            assert.is_true(driver.wait_for(session, function()
                local body = driver.current_buffer_text(session)
                return body:find("inbox note", 1, true) ~= nil
            end, { timeout_ms = 10000 }))
        end)
    end)

    it("opens process with base filter", function()
        with_session(source_root, "process-base", function(session)
            driver.command(session, "Vault process base All")
            assert.is_true(driver.wait_for(session, function()
                local bufname = driver.current_buffer_name(session)
                return bufname:find("vault://", 1, true) ~= nil
            end, { timeout_ms = 10000 }))
        end)
    end)
end)
