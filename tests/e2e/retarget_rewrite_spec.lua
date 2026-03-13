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

describe("vault.e2e retarget rewrite-path", function()
    it("retargets a note into an existing target via the resolve picker merge path", function()
        local source_root = make_source_vault("vault-e2e-retarget-rewrite", {
            ["Inbox/source-note.md"] = {
                "---",
                'title: "source note"',
                "tags:",
                "  - alpha",
                "---",
                "",
                "# source note",
                "Source body content.",
            },
            ["Reference/target-note.md"] = {
                "---",
                'title: "target note"',
                "tags:",
                "  - beta",
                "---",
                "",
                "# target note",
                "Target body content.",
            },
        })

        with_session(source_root, "retarget-rewrite", function(session)
            local source_path = session.root .. "/Inbox/source-note.md"
            local target_path = session.root .. "/Reference/target-note.md"

            -- Open the source note
            driver.command(session, "edit " .. vim.fn.fnameescape(source_path))

            -- Open the retarget picker
            driver.lua(session, "require('vault.notes.workflows').open_retarget_picker()")

            -- Type the target name to filter and select it with <CR>
            -- This triggers the "rewrite" action (merge into existing target)
            driver.keys(session, "Reference/target-note<CR>")

            -- The merge UI should appear — confirm the merge
            assert.is_true(driver.wait_for(session, function()
                local body = driver.current_buffer_text(session)
                return body:find("Merge:", 1, true) ~= nil
                    or body:find("merge", 1, true) ~= nil
            end, { timeout_ms = 8000 }))
            driver.keys(session, "<CR>")

            -- Wait for merge to complete: source should be trashed, target should still exist
            assert.is_true(driver.wait_for(session, function()
                return vim.fn.filereadable(source_path) == 0
                    and vim.fn.filereadable(target_path) == 1
            end, { timeout_ms = 8000 }))

            -- Source should be in .trash
            assert.is_true(
                vim.fn.filereadable(session.root .. "/.trash/source-note.md") == 1
            )

            -- Target should contain merged content (source body appended or metadata merged)
            local target_content = table.concat(vim.fn.readfile(target_path), "\n")
            -- The target should retain its own body
            assert.is_true(target_content:find("Target body content", 1, true) ~= nil)
            -- And should have absorbed source tags (alpha tag merged into target)
            assert.is_true(
                target_content:find("alpha", 1, true) ~= nil
                    or target_content:find("source", 1, true) ~= nil
            )
        end)
    end)
end)
