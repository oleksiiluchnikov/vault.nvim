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
    vim.wait(1100)
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

describe("vault.e2e note lifecycle", function()
    it("opens the requested note through the note command path", function()
        local source_root = make_vault("vault-e2e-note-lifecycle-open", {
            ["Inbox/focus-note.md"] = {
                "---",
                'title: "focus note"',
                "---",
                "",
                "# Focus note",
            },
            ["Inbox/other-note.md"] = {
                "---",
                'title: "other note"',
                "---",
                "",
                "# Other note",
            },
        })

        with_session(source_root, "note-lifecycle-open", function(session)
            driver.command(session, "Vault note new Inbox/focus-note")

            assert.is_true(driver.wait_for(session, function()
                local bufname = driver.current_buffer_name(session)
                return bufname == session.root .. "/Inbox/focus-note.md"
            end, { timeout_ms = 10000 }))
        end)
    end)

    it("opens a valid note buffer for random note", function()
        local source_root = make_vault("vault-e2e-note-lifecycle-random", {
            ["Inbox/random-one.md"] = {
                "---",
                'title: "random one"',
                "---",
                "",
                "# Random one",
            },
            ["Inbox/random-two.md"] = {
                "---",
                'title: "random two"',
                "---",
                "",
                "# Random two",
            },
            ["Inbox/random-three.md"] = {
                "---",
                'title: "random three"',
                "---",
                "",
                "# Random three",
            },
        })

        with_session(source_root, "note-lifecycle-random", function(session)
            driver.command(session, "Vault note random")

            assert.is_true(driver.wait_for(session, function()
                local bufname = driver.current_buffer_name(session)
                return bufname:find(session.root, 1, true) == 1 and bufname:match("%.md$") ~= nil
            end, { timeout_ms = 10000 }))
        end)
    end)

    it("creates new notes in Obsidian's configured new file folder", function()
        local source_root = make_vault("vault-e2e-note-lifecycle-folder", {
            [".obsidian/app.json"] = {
                "{",
                '  "newFileLocation": "folder",',
                '  "newFileFolderPath": "Inbox"',
                "}",
            },
        })

        with_session(source_root, "note-lifecycle-folder", function(session)
            driver.command(session, "Vault note new app-folder-note")

            assert.is_true(driver.wait_for(session, function()
                local path = session.root .. "/Inbox/app-folder-note.md"
                local bufname = driver.current_buffer_name(session)
                return vim.fn.filereadable(path) == 1 and bufname == path
            end, { timeout_ms = 10000 }))
        end)
    end)
end)
