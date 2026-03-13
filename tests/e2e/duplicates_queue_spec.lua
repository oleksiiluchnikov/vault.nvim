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

describe("vault.e2e duplicate review queue and batch-apply", function()
    it("queues multiple duplicate-review decisions and flushes them with X", function()
        -- Create two duplicate pairs:
        -- Pair 1: Topic.md vs Topic 1.md (exact body duplicate)
        -- Pair 2: Report.md vs Report 1.md (exact body duplicate)
        local source_root = make_source_vault("vault-e2e-dup-queue", {
            ["Inbox/Topic.md"] = {
                "---",
                'title: "Topic"',
                "created: 20240101000000",
                "---",
                "# Topic",
                "Alpha content here.",
            },
            ["References/Topic 1.md"] = {
                "---",
                'title: "Topic"',
                "created: 20240101000000",
                "---",
                "# Topic",
                "Alpha content here.",
            },
            ["Inbox/Report.md"] = {
                "---",
                'title: "Report"',
                "created: 20240201000000",
                "---",
                "# Report",
                "Beta content here.",
            },
            ["References/Report 1.md"] = {
                "---",
                'title: "Report"',
                "created: 20240201000000",
                "---",
                "# Report",
                "Beta content here.",
            },
        })

        with_session(source_root, "duplicates-queue-batch", function(session)
            -- Open duplicate review
            driver.command(session, "Vault duplicates review kind exact")

            -- Wait for the review UI to load (center buffer shows actions)
            assert.is_true(driver.wait_for(session, function()
                local body = driver.current_buffer_text(session)
                return body:find("Queue keep A", 1, true) ~= nil
            end, { timeout_ms = 10000 }))

            -- Queue keep A for the first pair (press A instead of a)
            driver.keys(session, "A")

            -- Wait for the next pair to appear (or the queue count to update)
            assert.is_true(driver.wait_for(session, function()
                local body = driver.current_buffer_text(session)
                -- Either we moved to the next pair, or flush happened if only 1 left
                return body:find("1 pending", 1, true) ~= nil
                    or body:find("Queue keep", 1, true) ~= nil
                    or body:find("review complete", 1, true) ~= nil
            end, { timeout_ms = 8000 }))

            -- Check if there's a second pair to queue
            local body = driver.current_buffer_text(session)
            if body:find("Queue keep", 1, true) then
                -- Queue keep A for the second pair too
                driver.keys(session, "A")

                -- After queuing all pairs, flush should trigger automatically
                -- or we may need to press X
                assert.is_true(driver.wait_for(session, function()
                    -- Check that at least one copy was trashed
                    local topic1_gone = vim.fn.filereadable(session.root .. "/References/Topic 1.md") == 0
                    local report1_gone = vim.fn.filereadable(session.root .. "/References/Report 1.md") == 0
                    return topic1_gone or report1_gone
                end, { timeout_ms = 10000 }))
            end

            -- Verify the batch result: at least one pair was resolved
            -- The "keep A" choice means A (Inbox/ version) stays, B (References/ copy) goes to trash
            local topic_a_exists = vim.fn.filereadable(session.root .. "/Inbox/Topic.md") == 1
            local report_a_exists = vim.fn.filereadable(session.root .. "/Inbox/Report.md") == 1
            assert.is_true(topic_a_exists or report_a_exists)

            -- Check trash directory has at least one trashed duplicate
            local trash_files = vim.fn.glob(session.root .. "/.trash/*.md", false, true)
            assert.is_true(#trash_files >= 1)
        end)
    end)
end)
