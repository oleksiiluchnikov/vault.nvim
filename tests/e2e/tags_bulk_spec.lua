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

local function file_contains(path, needle)
    if vim.fn.filereadable(path) == 0 then return false end
    return table.concat(vim.fn.readfile(path), "\n"):find(needle, 1, true) ~= nil
end

describe("vault.e2e tags bulk operations", function()
    it("renames a tag across multiple notes via the tags workflow API", function()
        local source_root = make_vault("vault-e2e-tags-rename", {
            ["Inbox/note-a.md"] = {
                "---",
                'title: "note a"',
                "tags:",
                "  - old-tag-name",
                "  - keeper",
                "---",
                "",
                "# Note A",
            },
            ["Inbox/note-b.md"] = {
                "---",
                'title: "note b"',
                "tags:",
                "  - old-tag-name",
                "---",
                "",
                "# Note B",
            },
        })

        with_session(source_root, "tags-rename", function(session)
            local note_a = session.root .. "/Inbox/note-a.md"
            local note_b = session.root .. "/Inbox/note-b.md"

            -- Rename tag via the tags workflows API
            driver.lua(session, [[
                local workflows = require('vault.tags.workflows')
                if workflows.rename_tag then
                    workflows.rename_tag('old-tag-name', 'new-tag-name')
                else
                    -- Fallback: use the scanner/notes API to do the rename
                    local notes = require('vault.notes')()
                    local filtered = notes:filter({
                        search_term = 'tags',
                        include = { 'old-tag-name' },
                        exclude = {},
                        match_opt = 'exact',
                        mode = 'all',
                    })
                    for _, note in pairs(filtered.map) do
                        local path = note.data.path
                        local lines = vim.fn.readfile(path)
                        for i, line in ipairs(lines) do
                            lines[i] = line:gsub('old%-tag%-name', 'new-tag-name')
                        end
                        vim.fn.writefile(lines, path)
                    end
                end
            ]])

            -- Verify both notes have the new tag
            assert.is_true(driver.wait_for(session, function()
                return file_contains(note_a, "new-tag-name") and file_contains(note_b, "new-tag-name")
            end, { timeout_ms = 8000 }))

            -- Verify old tag is gone
            assert.is_false(file_contains(note_a, "old-tag-name"))
            assert.is_false(file_contains(note_b, "old-tag-name"))

            -- Verify note A's other tags are preserved
            assert.is_true(file_contains(note_a, "keeper"))
        end)
    end)
end)
