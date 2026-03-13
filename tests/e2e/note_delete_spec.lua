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

describe("vault.e2e note delete", function()
    it("deletes a note to .trash via the Note:delete API", function()
        local source_root = make_vault("vault-e2e-note-delete", {
            ["Inbox/doomed-note.md"] = {
                "---",
                'title: "doomed note"',
                "---",
                "",
                "# Doomed note",
                "This note will be deleted.",
            },
            ["Inbox/survivor.md"] = {
                "---",
                'title: "survivor"',
                "---",
                "",
                "See also [[Inbox/doomed-note]].",
            },
        })

        with_session(source_root, "note-delete", function(session)
            local doomed_path = session.root .. "/Inbox/doomed-note.md"

            -- Open the note
            driver.command(session, "edit " .. vim.fn.fnameescape(doomed_path))

            -- Delete via API (bypassing confirm dialog which blocks RPC)
            driver.lua(session, [[
                local Note = require('vault.notes.note')
                local note = Note(vim.fn.expand('%:p'))
                note:delete(false, true)
            ]])

            -- Verify the note is gone from original location
            assert.is_true(driver.wait_for(session, function()
                return vim.fn.filereadable(doomed_path) == 0
            end, { timeout_ms = 5000 }))

            -- Verify it's in .trash
            local trash_files = vim.fn.glob(session.root .. "/.trash/doomed-note*.md", false, true)
            assert.is_true(#trash_files >= 1)

            -- Verify the survivor still references the old slug (now broken)
            local survivor = table.concat(vim.fn.readfile(session.root .. "/Inbox/survivor.md"), "\n")
            assert.is_true(survivor:find("doomed%-note", 1) ~= nil)
        end)
    end)
end)
