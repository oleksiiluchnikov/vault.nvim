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
            driver.lua(session, [[
                local config = require('vault.config')
                config.options.dirs = config.options.dirs or {}
                config.options.dirs.journal = config.options.dirs.journal or {}
                config.options.dirs.journal.daily = 'Journal/Daily'
            ]])
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
            driver.lua(session, [[
                local config = require('vault.config')
                config.options.dirs = config.options.dirs or {}
                config.options.dirs.journal = config.options.dirs.journal or {}
                config.options.dirs.journal.daily = 'Journal/Daily'
            ]])
            driver.command(session, "Vault yesterday")
            assert.is_true(driver.wait_for(session, function()
                local bufname = driver.current_buffer_name(session)
                local yesterday = os.date("%Y-%m-%d", os.time() - 86400)
                return bufname:find(yesterday, 1, true) ~= nil
            end, { timeout_ms = 8000 }))
        end)
    end)
end)
