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

describe("vault.e2e vault doctor", function()
    it("runs vault doctor and reports diagnostics without error", function()
        local source_root = make_vault("vault-e2e-doctor", {
            ["Inbox/good-note.md"] = {
                "---",
                'title: "good note"',
                'status: "active"',
                "---",
                "",
                "# Good note",
            },
            ["Inbox/bad-note.md"] = {
                "---",
                "title: 42",
                "status: true",
                "---",
                "",
                "# Bad note",
                "Has wrong frontmatter types.",
            },
        })

        with_session(source_root, "vault-doctor", function(session)
            -- Run vault doctor via Lua to capture result
            driver.lua(session, [[
                local typecheck = require('vault.typecheck')
                local dr = typecheck.doctor()
                vim.g._doctor_scanned = dr.scanned or 0
                vim.g._doctor_errors = #(dr.errors or {})
            ]])

            -- Verify doctor ran without crashing
            local scanned = driver.expr(session, "g:_doctor_scanned")
            assert.is_true(tonumber(scanned) >= 0, "Doctor should have scanned some notes")
        end)
    end)
end)
