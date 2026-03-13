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

describe("vault.e2e note rename", function()
    it("renames a note and rewrites wikilinks in other notes", function()
        local source_root = make_vault("vault-e2e-note-rename", {
            ["Inbox/old-name.md"] = {
                "---",
                'title: "old name"',
                "---",
                "",
                "# Old name",
                "Original content.",
            },
            ["Inbox/referencing-note.md"] = {
                "---",
                'title: "referencing note"',
                "---",
                "",
                "See [[Inbox/old-name]] for details.",
            },
        })

        with_session(source_root, "note-rename", function(session)
            local old_path = session.root .. "/Inbox/old-name.md"
            local new_path = session.root .. "/Inbox/new-name.md"
            local ref_path = session.root .. "/Inbox/referencing-note.md"

            -- Open the note to rename
            driver.command(session, "edit " .. vim.fn.fnameescape(old_path))

            -- Rename via command with explicit new slug
            driver.command(session, "Vault note rename Inbox/new-name")

            -- Wait for the rename to complete
            assert.is_true(driver.wait_for(session, function()
                return vim.fn.filereadable(new_path) == 1
                    and vim.fn.filereadable(old_path) == 0
            end, { timeout_ms = 8000 }))

            -- Verify wikilinks in other notes were rewritten
            local ref_content = table.concat(vim.fn.readfile(ref_path), "\n")
            assert.is_true(
                ref_content:find("new%-name", 1) ~= nil,
                "Expected referencing note to contain 'new-name' wikilink"
            )
            assert.is_true(
                ref_content:find("old%-name", 1) == nil,
                "Expected referencing note to NOT contain 'old-name' wikilink"
            )
        end)
    end)
end)
