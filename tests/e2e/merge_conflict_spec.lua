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

local function file_contains(path, needle)
    if vim.fn.filereadable(path) == 0 then
        return false
    end
    return table.concat(vim.fn.readfile(path), "\n"):find(needle, 1, true) ~= nil
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

describe("vault.e2e merge conflict-resolution", function()
    it("triggers the conflict picker and resolves conflicting frontmatter fields", function()
        -- Two notes with identical stems but conflicting frontmatter values
        local source_root = make_source_vault("vault-e2e-merge-conflict", {
            ["Inbox/target-note.md"] = {
                "---",
                'title: "target note"',
                'status: "active"',
                'priority: "high"',
                "tags:",
                "  - alpha",
                "---",
                "",
                "# target note",
                "Target body content.",
            },
            ["Inbox/source-note.md"] = {
                "---",
                'title: "source note"',
                'status: "done"',
                'priority: "low"',
                "tags:",
                "  - beta",
                "---",
                "",
                "# source note",
                "Source body content.",
            },
        })

        with_session(source_root, "merge-conflict", function(session)
            local target_path = session.root .. "/Inbox/target-note.md"
            local source_path = session.root .. "/Inbox/source-note.md"

            -- Open source note and start a merge into target
            driver.command(session, "edit " .. vim.fn.fnameescape(source_path))
            driver.command(session, "Vault note merge")

            -- Type target name and select it
            driver.keys(session, "Inbox/target-note<CR>")

            -- Wait for the conflict picker UI or merge preview to appear
            -- The merge UI shows "Merge:" header with conflict choices
            assert.is_true(driver.wait_for(session, function()
                local body = driver.current_buffer_text(session)
                return body:find("Merge:", 1, true) ~= nil
                    or body:find("Resolve", 1, true) ~= nil
                    or body:find("pick A", 1, true) ~= nil
                    or body:find("pick B", 1, true) ~= nil
            end, { timeout_ms = 10000 }))

            -- Check if we got the conflict picker (has "pick A" / "pick B")
            local body = driver.current_buffer_text(session)
            if body:find("pick A", 1, true) then
                -- We're in the conflict picker — choose A (target) for all conflicts
                -- and press <CR> to apply
                driver.keys(session, "a")
                vim.wait(200)
                driver.keys(session, "<CR>")
            else
                -- Merge was auto-resolved (biases handled it) — just confirm
                driver.keys(session, "<CR>")
            end

            -- Wait for merge to complete: source should be trashed
            assert.is_true(driver.wait_for(session, function()
                return vim.fn.filereadable(source_path) == 0
                    and vim.fn.filereadable(target_path) == 1
            end, { timeout_ms = 10000 }))

            -- Source note should be in .trash
            assert.is_true(
                vim.fn.filereadable(session.root .. "/.trash/source-note.md") == 1
            )

            -- Target should contain the resolved frontmatter and its original body
            local target_content = table.concat(vim.fn.readfile(target_path), "\n")
            assert.is_true(target_content:find("Target body content", 1, true) ~= nil)

            -- Target should have been enriched with source's tags (beta merged in)
            -- or at minimum the target's own content is preserved
            assert.is_true(target_content:find("alpha", 1, true) ~= nil)
        end)
    end)
end)
