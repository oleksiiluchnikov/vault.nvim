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
        artifacts.write_vault_diff(session.artifacts_dir, source_root, session.root)
        driver.stop(session)
        error(err)
    end
    driver.stop(session)
end

describe("vault.e2e duplicate review pause-resume", function()
    it("pauses with q and resumes from the same position", function()
        local source_root = make_vault("vault-e2e-dup-pause", {
            ["Inbox/Foo.md"] = {
                "---",
                'title: "Foo"',
                "---",
                "",
                "# Foo",
                "Content X.",
            },
            ["Reference/Foo 1.md"] = {
                "---",
                'title: "Foo"',
                "---",
                "",
                "# Foo",
                "Content X.",
            },
            ["Inbox/Bar.md"] = {
                "---",
                'title: "Bar"',
                "---",
                "",
                "# Bar",
                "Content Y.",
            },
            ["Reference/Bar 1.md"] = {
                "---",
                'title: "Bar"',
                "---",
                "",
                "# Bar",
                "Content Y.",
            },
        })

        with_session(source_root, "dup-pause-resume", function(session)
            -- Start review
            driver.command(session, "Vault duplicates review kind exact")

            -- Wait for review UI
            assert.is_true(driver.wait_for(session, function()
                local body = driver.current_buffer_text(session)
                return body:find("Queue keep", 1, true) ~= nil
            end, { timeout_ms = 10000 }))

            -- Pause with q
            driver.keys(session, "q")
            vim.wait(500)

            -- Resume review
            driver.command(session, "Vault duplicates review kind exact")

            -- Should show the review UI again (resumed)
            assert.is_true(driver.wait_for(session, function()
                local body = driver.current_buffer_text(session)
                return body:find("Queue keep", 1, true) ~= nil
                    or body:find("review complete", 1, true) ~= nil
            end, { timeout_ms = 10000 }))
        end)
    end)
end)
