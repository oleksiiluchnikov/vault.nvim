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

local function file_contains(path, needle)
    if vim.fn.filereadable(path) == 0 then return false end
    return table.concat(vim.fn.readfile(path), "\n"):find(needle, 1, true) ~= nil
end

describe("vault.e2e tags and properties commands", function()
    local source_root

    before_each(function()
        source_root = make_vault("vault-e2e-tags-properties", {
            ["Inbox/note-a.md"] = {
                "---",
                'title: "note a"',
                "tags:",
                "  - old_tag",
                'old_prop: "value-a"',
                "---",
                "",
                "# Note A",
            },
            ["Inbox/note-b.md"] = {
                "---",
                'title: "note b"',
                "tags:",
                "  - keep_tag",
                "  - old_tag",
                'old_prop: "value-b"',
                "---",
                "",
                "# Note B",
            },
        })
    end)

    it("renames tags on disk via the command", function()
        with_session(source_root, "tags-properties-tags-rename", function(session)
            local note_a = session.root .. "/Inbox/note-a.md"
            local note_b = session.root .. "/Inbox/note-b.md"

            driver.lua(session, string.format(
                [[
                    local actions = require('vault.tags.actions')
                    local root = %q
                    actions.rename = function(from_tag_name, to_tag_name)
                        for _, path in ipairs(vim.fn.globpath(root, '**/*.md', false, true)) do
                            local lines = vim.fn.readfile(path)
                            for i, line in ipairs(lines) do
                                lines[i] = line:gsub(from_tag_name, to_tag_name)
                            end
                            vim.fn.writefile(lines, path)
                        end
                    end
                ]],
                session.root
            ))
            driver.command(session, "Vault tags rename old_tag new_tag")

            assert.is_true(driver.wait_for(session, function()
                return file_contains(note_a, "new_tag") and file_contains(note_b, "new_tag")
            end, { timeout_ms = 10000 }))
            assert.is_false(file_contains(note_a, "old_tag"))
            assert.is_false(file_contains(note_b, "old_tag"))
            assert.is_true(file_contains(note_b, "keep_tag"))
        end)
    end)

    it("renames properties on disk via the command", function()
        with_session(source_root, "tags-properties-properties-rename", function(session)
            local note_a = session.root .. "/Inbox/note-a.md"
            local note_b = session.root .. "/Inbox/note-b.md"

            driver.lua(session, string.format(
                [[
                    package.loaded['vault.properties'] = function()
                        local root = %q
                        return {
                            map = {
                                old_prop = {
                                    rename = function(_, new_name)
                                        for _, path in ipairs(vim.fn.globpath(root, '**/*.md', false, true)) do
                                            local lines = vim.fn.readfile(path)
                                            for i, line in ipairs(lines) do
                                                lines[i] = line:gsub('^old_prop:', new_name .. ':')
                                            end
                                            vim.fn.writefile(lines, path)
                                        end
                                    end,
                                },
                            },
                        }
                    end
                ]],
                session.root
            ))
            driver.command(session, "Vault properties rename old_prop new_prop")

            assert.is_true(driver.wait_for(session, function()
                return file_contains(note_a, "new_prop") and file_contains(note_b, "new_prop")
            end, { timeout_ms = 10000 }))
            assert.is_false(file_contains(note_a, "old_prop"))
            assert.is_false(file_contains(note_b, "old_prop"))
        end)
    end)
end)
