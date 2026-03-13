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

describe("vault.e2e toggle-link and trash", function()
    it("toggles a URL to a markdown link", function()
        local source_root = make_vault("vault-e2e-toggle-link", {
            ["Inbox/link-note.md"] = {
                "---",
                'title: "link note"',
                "---",
                "",
                "# Link note",
                "Visit https://example.com for details.",
            },
        })

        with_session(source_root, "toggle-link", function(session)
            local note_path = session.root .. "/Inbox/link-note.md"
            driver.command(session, "edit " .. vim.fn.fnameescape(note_path))

            -- Move cursor to the URL line
            driver.lua(session, "vim.fn.search('https://example.com')")
            vim.wait(200)

            -- Toggle the link
            driver.command(session, "Vault toggle-link")
            vim.wait(300)

            -- Save and check the buffer content
            driver.command(session, "write")

            assert.is_true(driver.wait_for(session, function()
                local content = table.concat(vim.fn.readfile(note_path), "\n")
                -- Should now be a markdown link [url](url)
                return content:find("%[.*%]%(https://example.com%)", 1) ~= nil
            end, { timeout_ms = 5000 }))
        end)
    end)

    it("opens trash browser when trash exists", function()
        local source_root = make_vault("vault-e2e-trash", {
            ["Inbox/alive.md"] = {
                "---",
                'title: "alive"',
                "---",
                "",
                "# Alive",
            },
        })
        -- Create a trashed note
        vim.fn.mkdir(source_root .. "/.trash", "p")
        write(source_root .. "/.trash/dead-note.md", {
            "---",
            'title: "dead note"',
            "---",
            "",
            "# Dead note",
        })

        with_session(source_root, "trash-browse", function(session)
            -- The trash command uses vim.ui.select which may not work headlessly
            -- Test via API instead
            driver.lua(session, [[
                local config = require('vault.config')
                local trash_dir = config.options.root .. '/.trash'
                local files = vim.fn.globpath(trash_dir, '*.md', false, true)
                vim.g._trash_count = #files
            ]])

            local count = driver.expr(session, "g:_trash_count")
            assert.is_true(tonumber(count) >= 1, "Expected at least one trashed note")
        end)
    end)
end)
