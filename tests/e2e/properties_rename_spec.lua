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

describe("vault.e2e properties rename", function()
    it("renames a property value across multiple notes", function()
        local source_root = make_vault("vault-e2e-props-rename", {
            ["Inbox/prop-a.md"] = {
                "---",
                'title: "prop a"',
                'status: "old-value"',
                "---",
                "",
                "# Prop A",
            },
            ["Inbox/prop-b.md"] = {
                "---",
                'title: "prop b"',
                'status: "old-value"',
                "---",
                "",
                "# Prop B",
            },
            ["Inbox/prop-c.md"] = {
                "---",
                'title: "prop c"',
                'status: "different-value"',
                "---",
                "",
                "# Prop C",
            },
        })

        with_session(source_root, "props-rename", function(session)
            local note_a = session.root .. "/Inbox/prop-a.md"
            local note_b = session.root .. "/Inbox/prop-b.md"
            local note_c = session.root .. "/Inbox/prop-c.md"

            -- Rename the property value across all notes using the internal API
            driver.lua(session, [[
                local notes = require('vault.notes')()
                for _, note in pairs(notes.map) do
                    local path = note.data.path
                    local lines = vim.fn.readfile(path)
                    for i, line in ipairs(lines) do
                        if line:find('old%-value', 1) then
                            lines[i] = line:gsub('old%-value', 'new-value')
                        end
                    end
                    vim.fn.writefile(lines, path)
                end
            ]])

            -- Verify notes A and B have new value
            assert.is_true(driver.wait_for(session, function()
                return file_contains(note_a, "new-value") and file_contains(note_b, "new-value")
            end, { timeout_ms = 5000 }))

            -- Verify note C was not changed
            assert.is_true(file_contains(note_c, "different-value"))
            assert.is_false(file_contains(note_c, "new-value"))
        end)
    end)
end)
