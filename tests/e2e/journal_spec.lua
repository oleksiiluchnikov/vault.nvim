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

describe("vault.e2e journal commands", function()
    local source_root
    before_each(function()
        source_root = make_vault("vault-e2e-journal", {
            ["Inbox/placeholder.md"] = {
                "---",
                'title: "placeholder"',
                "---",
                "",
                "Placeholder.",
            },
        })
        vim.fn.mkdir(source_root .. "/Journal/Daily", "p")
    end)

    it("opens today's journal note", function()
        with_session(source_root, "journal-today", function(session)
            -- Configure journal daily directory
            driver.lua(
                session,
                [[
                local config = require('vault.config')
                config.options.dirs = config.options.dirs or {}
                config.options.dirs.journal = config.options.dirs.journal or {}
                config.options.dirs.journal.daily = 'Journal/Daily'
            ]]
            )
            driver.command(session, "Vault today")
            assert.is_true(driver.wait_for(session, function()
                local bufname = driver.current_buffer_name(session)
                local today = os.date("%Y-%m-%d")
                return bufname:find(today, 1, true) ~= nil
            end, { timeout_ms = 8000 }))
        end)
    end)

    it("opens yesterday's journal note", function()
        with_session(source_root, "journal-yesterday", function(session)
            driver.lua(
                session,
                [[
                local config = require('vault.config')
                config.options.dirs = config.options.dirs or {}
                config.options.dirs.journal = config.options.dirs.journal or {}
                config.options.dirs.journal.daily = 'Journal/Daily'
            ]]
            )
            driver.command(session, "Vault yesterday")
            assert.is_true(driver.wait_for(session, function()
                local bufname = driver.current_buffer_name(session)
                local yesterday = os.date("%Y-%m-%d", os.time() - 86400)
                return bufname:find(yesterday, 1, true) ~= nil
            end, { timeout_ms = 8000 }))
        end)
    end)

    it("prefers Obsidian daily note format over legacy journal path", function()
        write(source_root .. "/.obsidian/daily-notes.json", {
            "{",
            '  "format": "[journal] - YYYY-MM-DD dddd",',
            '  "folder": "/"',
            "}",
        })

        with_session(source_root, "journal-obsidian-format", function(session)
            driver.lua(
                session,
                [[
                local config = require('vault.config')
                config.options.dirs = config.options.dirs or {}
                config.options.dirs.journal = config.options.dirs.journal or {}
                config.options.dirs.journal.daily = 'Journal/Daily'
            ]]
            )
            driver.command(session, "Vault today")
            assert.is_true(driver.wait_for(session, function()
                local bufname = driver.current_buffer_name(session)
                local expected = os.date("journal - %Y-%m-%d %A") .. ".md"
                return vim.fn.fnamemodify(bufname, ":t") == expected
            end, { timeout_ms = 8000 }))
        end)
    end)

    it("creates today's journal from the Obsidian daily note template", function()
        write(source_root .. "/.obsidian/daily-notes.json", {
            "{",
            '  "format": "[journal] - YYYY-MM-DD dddd",',
            '  "folder": "/",',
            '  "template": "template - journal"',
            "}",
        })
        write(source_root .. "/.obsidian/templates.json", {
            "{",
            '  "timeFormat": "HH:mm:ss",',
            '  "dateFormat": "YYYY-MM-DD dddd",',
            '  "folder": ""',
            "}",
        })
        write(source_root .. "/template - journal.md", {
            "# {{title}}",
            "- {{date}}",
            "- {{time}}",
            "{{cursor}}",
        })

        with_session(source_root, "journal-template", function(session)
            driver.command(session, "Vault today")
            assert.is_true(driver.wait_for(session, function()
                local today = os.date("%Y-%m-%d")
                local path = session.root .. "/" .. os.date("journal - %Y-%m-%d %A") .. ".md"
                if vim.fn.filereadable(path) == 0 then
                    return false
                end
                local lines = vim.fn.readfile(path)
                return lines[1] == "# journal - " .. os.date("%Y-%m-%d %A")
                    and lines[2] == "- " .. os.date("%Y-%m-%d %A")
                    and lines[3] ~= nil
                    and lines[3]:match("^%- %d%d:%d%d:%d%d$") ~= nil
            end, { timeout_ms = 8000 }))
        end)
    end)
end)
