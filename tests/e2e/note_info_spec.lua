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
        driver.stop(session)
        error(err)
    end
    driver.stop(session)
end

describe("vault.e2e note info commands", function()
    local source_root
    before_each(function()
        source_root = make_vault("vault-e2e-note-info", {
            ["Inbox/info-note.md"] = {
                "---",
                'title: "info note"',
                "tags:",
                "  - alpha",
                "  - beta",
                "---",
                "",
                "# Info note",
                "See [[Inbox/linked-note]].",
            },
            ["Inbox/linked-note.md"] = {
                "---",
                'title: "linked note"',
                "---",
                "",
                "# Linked note",
                "Mentions [[Inbox/info-note]].",
            },
        })
    end)

    it("opens note inlinks picker", function()
        with_session(source_root, "note-inlinks", function(session)
            driver.command(session, "edit " .. vim.fn.fnameescape(session.root .. "/Inbox/info-note.md"))
            driver.command(session, "Vault note inlinks")
            assert.is_true(driver.wait_for(session, function()
                local ft = driver.expr(session, "&filetype")
                return ft == "TelescopePrompt"
            end, { timeout_ms = 8000 }))
            driver.keys(session, "<Esc>")
        end)
    end)

    it("opens note outlinks picker", function()
        with_session(source_root, "note-outlinks", function(session)
            driver.command(session, "edit " .. vim.fn.fnameescape(session.root .. "/Inbox/info-note.md"))
            driver.command(session, "Vault note outlinks")
            assert.is_true(driver.wait_for(session, function()
                local ft = driver.expr(session, "&filetype")
                return ft == "TelescopePrompt"
            end, { timeout_ms = 8000 }))
            driver.keys(session, "<Esc>")
        end)
    end)

    it("opens note tags picker", function()
        with_session(source_root, "note-tags", function(session)
            driver.command(session, "edit " .. vim.fn.fnameescape(session.root .. "/Inbox/info-note.md"))
            driver.command(session, "Vault note tags")
            assert.is_true(driver.wait_for(session, function()
                local ft = driver.expr(session, "&filetype")
                return ft == "TelescopePrompt"
            end, { timeout_ms = 8000 }))
            driver.keys(session, "<Esc>")
        end)
    end)
end)
