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

describe("vault.e2e duplicate review", function()
    it("covers open, preview, and apply through :Vault duplicates review", function()
        local source_root = make_source_vault("vault-e2e-duplicates", {
            ["Inbox/Topic.md"] = {
                "---",
                'title: "Topic"',
                "created: 20240101000000",
                "---",
                "# Topic",
                "alpha",
            },
            ["References/Topic 1.md"] = {
                "---",
                'title: "Topic"',
                "created: 20240101000000",
                "---",
                "# Topic",
                "alpha",
                "beta",
            },
        })

        with_session(source_root, "duplicates-review", function(session)
            local a_path = session.root .. "/Inbox/Topic.md"
            local b_path = session.root .. "/References/Topic 1.md"
            driver.command(session, "Vault duplicates review kind subset")

            assert.is_true(driver.wait_for(session, function()
                local body = driver.current_buffer_text(session)
                return body:find("Apply keep A", 1, true) ~= nil and body:find("Apply keep B", 1, true) ~= nil
            end, { timeout_ms = 8000 }))

            driver.keys(session, "pa")
            assert.is_true(driver.wait_for(session, function()
                return driver.current_buffer_name(session):find("vault://duplicates/merge%-preview", 1) ~= nil
            end, { timeout_ms = 8000 }))

            driver.keys(session, "q")
            assert.is_true(driver.wait_for(session, function()
                return driver.current_buffer_name(session):find("vault://duplicates/center", 1) ~= nil
            end, { timeout_ms = 8000 }))

            driver.keys(session, "<CR>")
            assert.is_true(driver.wait_for(session, function()
                return (vim.fn.filereadable(a_path) == 0 or vim.fn.filereadable(b_path) == 0)
                    and (vim.fn.filereadable(session.root .. "/.trash/Topic.md") == 1 or vim.fn.filereadable(session.root .. "/.trash/Topic 1.md") == 1)
            end, { timeout_ms = 8000 }))
        end)
    end)
end)
