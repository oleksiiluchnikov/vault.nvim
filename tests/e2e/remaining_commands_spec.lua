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

local function run_command(session, command, prefix)
    driver.lua(
        session,
        string.format(
            [[
        vim.g.%s_ok = "0"
        vim.g.%s_err = ""
        local ok, err = pcall(vim.cmd, %q)
        vim.g.%s_ok = ok and "1" or "0"
        vim.g.%s_err = tostring(err or "")
    ]],
            prefix,
            prefix,
            command,
            prefix,
            prefix
        )
    )
end

describe("vault.e2e remaining commands", function()
    local source_root

    before_each(function()
        source_root = make_vault("vault-e2e-remaining-commands", {
            ["Inbox/seed.md"] = {
                "---",
                'title: "seed"',
                "---",
                "",
                "# Seed",
            },
        })
        vim.fn.mkdir(source_root .. "/Journal/Daily", "p")
    end)

    it("opens or creates today's daily note", function()
        with_session(source_root, "remaining-commands-today", function(session)
            local today = os.date("%Y-%m-%d %A")

            driver.lua(session, string.format([[ 
                local config = require('vault.config')
                config.options.root = %q
                config.options.dirs = config.options.dirs or {}
                config.options.dirs.journal = config.options.dirs.journal or {}
                config.options.dirs.journal.daily = %q
            ]], session.root, session.root .. '/Journal/Daily'))
            driver.command(session, "Vault today")

            assert.is_true(driver.wait_for(session, function()
                local bufname = driver.expr(session, "expand('%:p')")
                return bufname:find(today, 1, true) ~= nil
            end, { timeout_ms = 10000 }))
        end)
    end)

    it("shows stats without error", function()
        with_session(source_root, "remaining-commands-stats", function(session)
            run_command(session, "Vault stats", "_remaining_stats")

            assert.is_true(driver.wait_for(session, function()
                local ok = driver.expr(session, "g:_remaining_stats_ok")
                if ok ~= "1" then
                    return false
                end
                local win_count = tonumber(driver.expr(session, "luaeval('#vim.api.nvim_list_wins()')")) or 0
                local messages = driver.expr(session, "execute('messages')")
                return win_count >= 2
                    or messages:find("notes", 1, true) ~= nil
                    or messages:find("Vault", 1, true) ~= nil
            end, { timeout_ms = 8000 }))
        end)
    end)
end)
