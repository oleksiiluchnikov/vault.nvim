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

describe("vault.e2e note move", function()
    it("moves a note to a different directory and rewrites wikilinks", function()
        local source_root = make_vault("vault-e2e-note-move", {
            ["Inbox/movable-note.md"] = {
                "---",
                'title: "movable note"',
                "---",
                "",
                "# Movable note",
                "Content to move.",
            },
            ["Inbox/linker.md"] = {
                "---",
                'title: "linker"',
                "---",
                "",
                "See [[Inbox/movable-note]].",
            },
        })
        vim.fn.mkdir(source_root .. "/Reference", "p")

        with_session(source_root, "note-move", function(session)
            local old_path = session.root .. "/Inbox/movable-note.md"
            local new_path = session.root .. "/Reference/movable-note.md"
            local linker_path = session.root .. "/Inbox/linker.md"

            -- Open the note to move
            driver.command(session, "edit " .. vim.fn.fnameescape(old_path))

            -- Move via Note:move API (bypasses Telescope picker)
            driver.lua(session, string.format([[
                local Note = require('vault.notes.note')
                local note = Note(vim.fn.expand('%%:p'))
                note:move('%s')
            ]], new_path:gsub("'", "\\'")))

            -- Wait for the move to complete
            assert.is_true(driver.wait_for(session, function()
                return vim.fn.filereadable(new_path) == 1
                    and vim.fn.filereadable(old_path) == 0
            end, { timeout_ms = 8000 }))

            -- Verify wikilinks in other notes were rewritten
            local linker_content = table.concat(vim.fn.readfile(linker_path), "\n")
            assert.is_true(
                linker_content:find("Reference/movable%-note", 1) ~= nil,
                "Wikilinks should be rewritten to new path"
            )
        end)
    end)
end)
