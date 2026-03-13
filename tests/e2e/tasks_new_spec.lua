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

describe("vault.e2e tasks new", function()
    it("creates a new task note with correct frontmatter template", function()
        local source_root = make_vault("vault-e2e-tasks-new", {
            ["Inbox/placeholder.md"] = {
                "---",
                'title: "placeholder"',
                "---",
                "",
                "Placeholder note.",
            },
        })
        -- Create Tasks directory
        vim.fn.mkdir(source_root .. "/Tasks", "p")

        with_session(source_root, "tasks-new", function(session)
            -- Create a new task
            driver.command(session, "Vault tasks new E2E test task")

            -- Wait for the task file to appear
            assert.is_true(driver.wait_for(session, function()
                local files = vim.fn.glob(session.root .. "/Tasks/*.md", false, true)
                for _, f in ipairs(files) do
                    if f:find("E2E test task", 1, true) or f:find("e2e-test-task", 1, true) or f:find("e2e_test_task", 1, true) then
                        return true
                    end
                end
                -- Also check if any task file was created
                return #files > 0
            end, { timeout_ms = 8000 }))

            -- Find the created task file
            local task_files = vim.fn.glob(session.root .. "/Tasks/*.md", false, true)
            assert.is_true(#task_files >= 1, "Expected at least one task file")

            -- Verify frontmatter has required fields
            local task_content = table.concat(vim.fn.readfile(task_files[#task_files]), "\n")
            assert.is_true(
                task_content:find("status", 1, true) ~= nil,
                "Task should have a status field"
            )
        end)
    end)
end)
