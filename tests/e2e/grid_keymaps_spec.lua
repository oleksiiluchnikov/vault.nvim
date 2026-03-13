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

describe("vault.e2e grid keymaps", function()
    it("exercises gu (plugin undo) after a grid edit and save", function()
        local source_root = make_vault("vault-e2e-grid-keys", {
            ["Inbox/undo-target.md"] = {
                "---",
                'title: "undo target"',
                'status: "active"',
                "---",
                "",
                "# Undo target",
            },
            ["Inbox/other-note.md"] = {
                "---",
                'title: "other note"',
                'status: "done"',
                "---",
                "",
                "# Other note",
            },
        })

        with_session(source_root, "grid-keymaps-undo", function(session)
            local target_path = session.root .. "/Inbox/undo-target.md"

            -- Open process buffer with status column
            driver.command(session, "Vault process title,status")

            -- Wait for grid to load
            assert.is_true(driver.wait_for(session, function()
                local body = driver.current_buffer_text(session)
                return body:find("undo target", 1, true) ~= nil
            end, { timeout_ms = 10000 }))

            -- Edit the status via substitution
            driver.command(session, "%s/active/archived/")
            vim.wait(300)

            -- Save the grid
            driver.command(session, "write")

            -- Wait for save to complete
            assert.is_true(driver.wait_for(session, function()
                local content = table.concat(vim.fn.readfile(target_path), "\n")
                return content:find("archived", 1, true) ~= nil
            end, { timeout_ms = 8000 }))

            -- Now undo with gu
            driver.keys(session, "gu")

            -- Wait for undo to restore
            assert.is_true(driver.wait_for(session, function()
                local content = table.concat(vim.fn.readfile(target_path), "\n")
                return content:find("active", 1, true) ~= nil
            end, { timeout_ms = 8000 }))
        end)
    end)
end)
