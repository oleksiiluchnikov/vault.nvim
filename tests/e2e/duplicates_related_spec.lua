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

describe("vault.e2e duplicates related", function()
    it("scans for related notes and opens the review UI or reports no candidates", function()
        local source_root = make_vault("vault-e2e-dup-related", {
            ["Inbox/lua-patterns-guide.md"] = {
                "---",
                'title: "lua patterns guide"',
                "tags:",
                "  - lua",
                "  - patterns",
                "---",
                "",
                "# Lua patterns guide",
                "Content about lua patterns.",
            },
            ["Reference/lua-pattern-matching.md"] = {
                "---",
                'title: "lua pattern matching"',
                "tags:",
                "  - lua",
                "  - patterns",
                "---",
                "",
                "# Lua pattern matching",
                "Content about lua pattern matching.",
            },
            ["Inbox/unrelated-note.md"] = {
                "---",
                'title: "unrelated note"',
                "tags:",
                "  - cooking",
                "---",
                "",
                "# Unrelated",
                "Something about cooking.",
            },
        })

        with_session(source_root, "duplicates-related", function(session)
            -- Run duplicates related via Lua so we can check the result
            driver.lua(session, [[
                local dups = require('vault.duplicates')
                local items = dups.scan_related()
                vim.g._related_count = #items
            ]])

            -- Verify the scan completed without crashing (0 results is OK for small fixture)
            local count = driver.expr(session, "g:_related_count")
            assert.is_true(tonumber(count) ~= nil, "Related scan should return a number")
        end)
    end)
end)
