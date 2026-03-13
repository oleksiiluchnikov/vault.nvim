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

describe("vault.e2e conflicts review", function()
    it("scans for copy-suffix conflicts and opens the review UI", function()
        -- Create a note and its "copy" variant (Obsidian conflict pattern)
        local source_root = make_vault("vault-e2e-conflicts", {
            ["Inbox/important-note.md"] = {
                "---",
                'title: "important note"',
                'status: "active"',
                "---",
                "",
                "# Important note",
                "Original content.",
            },
            ["Inbox/important-note 1.md"] = {
                "---",
                'title: "important note 1"',
                'status: "active"',
                "---",
                "",
                "# Important note",
                "Original content.",
            },
        })

        with_session(source_root, "conflicts-review", function(session)
            -- Run conflicts review via the API (the command expects a report file path)
            -- Instead, use the conflicts module directly
            driver.lua(session, [[
                local conflicts = require('vault.conflicts')
                local cfg = require('vault.config')
                conflicts.review(vim.fn.expand(cfg.options.root))
            ]])

            -- Wait for the review UI or a log message
            assert.is_true(driver.wait_for(session, function()
                local body = driver.current_buffer_text(session)
                -- The resolver UI shows wikilinks or the conflict log message
                return body:find("important", 1, true) ~= nil
                    or body:find("Conflict", 1, true) ~= nil
                    or body:find("review complete", 1, true) ~= nil
            end, { timeout_ms = 10000 }))
        end)
    end)
end)
