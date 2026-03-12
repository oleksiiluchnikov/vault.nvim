local artifacts = require("tests.e2e.helpers.artifacts")
local driver = require("tests.e2e.helpers.driver")
local fixture = require("tests.e2e.helpers.fixture")

describe("vault.e2e foundation", function()
    it("launches a fresh Neovim against a cloned vault and mutates only the clone", function()
        local source_root = fixture.default_source_vault()
        local session = driver.start({
            source_root = source_root,
            scenario = "foundation-note-create",
        })

        local ok, err = pcall(function()
            assert.is_true(session.root ~= source_root)
            assert.is_true(vim.fn.isdirectory(session.root) == 1)

            local configured_root = driver.expr(session, "luaeval('require(\"vault.config\").options.root')")
            assert.are.equal(session.root, configured_root)

            driver.command(session, "Vault note new e2e-foundation-note")
            assert.is_true(driver.wait_for(session, function()
                return vim.fn.filereadable(session.root .. "/e2e-foundation-note.md") == 1
            end, { timeout_ms = 5000 }))

            assert.is_true(vim.fn.filereadable(session.root .. "/e2e-foundation-note.md") == 1)
            assert.is_true(vim.fn.filereadable(source_root .. "/e2e-foundation-note.md") == 0)

            artifacts.write_vault_diff(session.artifacts_dir, source_root, session.root)
            assert.is_true(vim.fn.filereadable(session.artifacts_dir .. "/vault-diff.txt") == 1)
        end)

        if not ok then
            driver.capture(session)
            artifacts.write_vault_diff(session.artifacts_dir, source_root, session.root)
            driver.stop(session)
            error(err)
        end

        driver.stop(session)
    end)

    it("refuses to target the live knowledge vault directly", function()
        assert.has_error(function()
            fixture.assert_not_live_target(vim.fn.expand("~/knowledge"))
        end)
    end)
end)
