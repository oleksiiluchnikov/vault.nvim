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

describe("vault.e2e filtered notes full", function()
    it("opens notes orphans without error even when empty", function()
        local source_root = make_vault("vault-e2e-notes-filtered-orphans", {
            ["Inbox/alpha.md"] = {
                "---",
                'title: "alpha"',
                "---",
                "",
                "[[Inbox/beta]]",
            },
            ["Inbox/beta.md"] = {
                "---",
                'title: "beta"',
                "---",
                "",
                "[[Inbox/alpha]]",
            },
        })

        with_session(source_root, "notes-filtered-orphans-full", function(session)
            driver.lua(session, [[
                local ok, err = pcall(vim.cmd, 'Vault notes orphans')
                vim.g._vault_picker_ok = ok
                vim.g._vault_picker_err = err
            ]])

            assert.are.equal("true", driver.expr(session, "g:_vault_picker_ok"))
        end)
    end)

    it("opens notes leaves without error even when empty", function()
        local source_root = make_vault("vault-e2e-notes-filtered-leaves", {
            ["Inbox/alpha.md"] = {
                "---",
                'title: "alpha"',
                "---",
                "",
                "[[Inbox/beta]]",
            },
            ["Inbox/beta.md"] = {
                "---",
                'title: "beta"',
                "---",
                "",
                "[[Inbox/alpha]]",
            },
        })

        with_session(source_root, "notes-filtered-leaves-full", function(session)
            driver.lua(session, [[
                local ok, err = pcall(vim.cmd, 'Vault notes leaves')
                vim.g._vault_picker_ok = ok
                vim.g._vault_picker_err = err
            ]])

            assert.are.equal("true", driver.expr(session, "g:_vault_picker_ok"))
        end)
    end)
end)
