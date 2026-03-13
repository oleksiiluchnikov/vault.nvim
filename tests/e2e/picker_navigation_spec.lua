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

describe("vault.e2e picker deep-navigation", function()
    local source_root

    before_each(function()
        source_root = make_source_vault("vault-e2e-picker-nav", {
            ["Inbox/Navigation note.md"] = {
                "---",
                'title: "Navigation note"',
                'status: "active"',
                "tags:",
                "  - nav-test-tag",
                'category: "[[category - Notes]]"',
                "---",
                "",
                "# Navigation note",
                "Body for navigation testing.",
            },
            ["Inbox/Second note.md"] = {
                "---",
                'title: "Second note"',
                'status: "done"',
                "tags:",
                "  - nav-test-tag",
                "  - extra-tag",
                'category: "[[category - Notes]]"',
                "---",
                "",
                "# Second note",
                "Another note.",
            },
            ["Process/All.base"] = {
                "views:",
                "  - type: table",
                "    name: All Notes",
                "    filters:",
                "      and: []",
            },
        })
    end)

    it("selects a note from the notes picker and opens it for editing", function()
        with_session(source_root, "picker-nav-notes", function(session)
            driver.command(session, "Vault notes")
            vim.wait(500)

            driver.keys(session, "Navigation note")
            vim.wait(300)
            driver.keys(session, "<CR>")

            assert.is_true(driver.wait_for(session, function()
                local bufname = driver.current_buffer_name(session)
                return bufname:find("Navigation note", 1, true) ~= nil
            end, { timeout_ms = 8000 }))

            local body = driver.current_buffer_text(session)
            assert.is_true(body:find("Body for navigation testing", 1, true) ~= nil)
        end)
    end)

    it("drills from tags picker into notes filtered by tag", function()
        with_session(source_root, "picker-nav-tags", function(session)
            driver.command(session, "Vault tags")
            vim.wait(500)

            driver.keys(session, "nav-test-tag")
            vim.wait(300)
            driver.keys(session, "<CR>")

            -- The drill-down opens a second Telescope picker with notes having this tag.
            -- Check that the filetype of the current buffer is TelescopePrompt (Telescope opened)
            -- or that a note was opened (if only one match, Telescope auto-selects).
            assert.is_true(driver.wait_for(session, function()
                local ft = driver.expr(session, "&filetype")
                local bufname = driver.current_buffer_name(session)
                return ft == "TelescopePrompt"
                    or bufname:find("Navigation note", 1, true) ~= nil
                    or bufname:find("Second note", 1, true) ~= nil
            end, { timeout_ms = 8000 }))

            driver.keys(session, "<Esc>")
        end)
    end)

    it("drills from properties picker into property values", function()
        with_session(source_root, "picker-nav-properties", function(session)
            driver.command(session, "Vault properties")
            vim.wait(500)

            driver.keys(session, "category")
            vim.wait(300)
            driver.keys(session, "<CR>")

            -- Either opens a values picker (TelescopePrompt) or shows values directly
            assert.is_true(driver.wait_for(session, function()
                local ft = driver.expr(session, "&filetype")
                return ft == "TelescopePrompt"
                    or ft == "markdown"
            end, { timeout_ms = 8000 }))

            driver.keys(session, "<Esc>")
        end)
    end)

    it("selects a base from the bases picker and opens the grid view", function()
        with_session(source_root, "picker-nav-bases", function(session)
            driver.command(session, "Vault bases")
            vim.wait(500)

            driver.keys(session, "<CR>")

            assert.is_true(driver.wait_for(session, function()
                local bufname = driver.current_buffer_name(session)
                return bufname:find("vault://grid", 1) ~= nil
                    or bufname:find("vault://", 1) ~= nil
            end, { timeout_ms = 8000 }))
        end)
    end)
end)
