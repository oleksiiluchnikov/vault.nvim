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

describe("vault.e2e misc commands full", function()
    local source_root = make_vault("vault-e2e-misc-full", {
        ["Inbox/command-note.md"] = {
            "---",
            'title: "command note"',
            'status: "active"',
            "tags:",
            "  - smoke",
            "---",
            "",
            "# Command note",
        },
    })

    it("opens Vault stats without error", function()
        with_session(source_root, "misc-commands-full-stats", function(session)
            run_command(session, "Vault stats", "_stats_cmd")

            assert.is_true(driver.wait_for(session, function()
                local ok = driver.expr(session, "g:_stats_cmd_ok")
                if ok ~= "1" then
                    return false
                end
                local win_count = tonumber(
                    driver.expr(session, "luaeval('#vim.api.nvim_list_wins()')")
                ) or 0
                return win_count >= 2
            end, { timeout_ms = 8000 }))
        end)
    end)

    it("runs Vault doctor without error", function()
        with_session(source_root, "misc-commands-full-doctor", function(session)
            run_command(session, "Vault doctor", "_doctor_cmd")

            assert.is_true(driver.wait_for(session, function()
                local ok = driver.expr(session, "g:_doctor_cmd_ok")
                if ok ~= "1" then
                    return false
                end
                local qf_title = driver.expr(session, "getqflist({'title': 1}).title")
                return qf_title == "Vault Doctor" or qf_title == ""
            end, { timeout_ms = 8000 }))
        end)
    end)
end)
