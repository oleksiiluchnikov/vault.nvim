-- Watcher integration E2E — gated behind VAULT_TEST_WATCHER=1
-- These tests are slower due to libuv polling delays.
if os.getenv("VAULT_TEST_WATCHER") ~= "1" then
    describe("vault.e2e watcher integration (SKIPPED)", function()
        it("skipped — set VAULT_TEST_WATCHER=1 to run", function()
            assert.is_true(true)
        end)
    end)
    return
end

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

describe("vault.e2e watcher integration", function()
    it("detects a new file created externally", function()
        local source_root = make_vault("vault-e2e-watcher", {
            ["Inbox/existing.md"] = {
                "---",
                'title: "existing"',
                "---",
                "",
                "# Existing",
            },
        })

        with_session(source_root, "watcher-create", function(session)
            -- Start the watcher
            driver.command(session, "Vault watcher start")
            vim.wait(1000)

            -- Create a new file externally
            write(session.root .. "/Inbox/watcher-created.md", {
                "---",
                'title: "watcher created"',
                "---",
                "",
                "# Watcher created",
            })

            -- Wait for the scanner to pick up the new file
            assert.is_true(driver.wait_for(session, function()
                local scanner_count = driver.expr(session, "luaeval('vim.tbl_count(require(\"vault.scanner\").paths())')")
                return tonumber(scanner_count) and tonumber(scanner_count) >= 2
            end, { timeout_ms = 10000 }))

            -- Stop watcher
            driver.command(session, "Vault watcher stop")
        end)
    end)

    it("detects a file deleted externally", function()
        local source_root = make_vault("vault-e2e-watcher-del", {
            ["Inbox/will-delete.md"] = {
                "---",
                'title: "will delete"',
                "---",
                "",
                "# Will delete",
            },
            ["Inbox/will-stay.md"] = {
                "---",
                'title: "will stay"',
                "---",
                "",
                "# Will stay",
            },
        })

        with_session(source_root, "watcher-delete", function(session)
            -- Start the watcher
            driver.command(session, "Vault watcher start")
            vim.wait(1000)

            -- Delete a file externally
            os.remove(session.root .. "/Inbox/will-delete.md")

            -- Wait for scanner to drop it
            assert.is_true(driver.wait_for(session, function()
                local scanner_count = driver.expr(session, "luaeval('vim.tbl_count(require(\"vault.scanner\").paths())')")
                return tonumber(scanner_count) and tonumber(scanner_count) <= 1
            end, { timeout_ms = 10000 }))

            -- Stop watcher
            driver.command(session, "Vault watcher stop")
        end)
    end)
end)
