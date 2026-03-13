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

describe("vault.e2e fleeting note", function()
    it("opens the fleeting note popup without error", function()
        local source_root = make_vault("vault-e2e-fleeting", {
            ["Inbox/placeholder.md"] = {
                "---",
                'title: "placeholder"',
                "---",
                "",
                "Placeholder.",
            },
        })

        with_session(source_root, "fleeting", function(session)
            driver.command(session, "Vault fleeting")

            -- Wait for the floating popup to appear
            assert.is_true(driver.wait_for(session, function()
                -- Check if a floating window appeared
                local win_count = driver.expr(session, "luaeval('#vim.api.nvim_list_wins()')")
                return tonumber(win_count) and tonumber(win_count) >= 2
            end, { timeout_ms = 8000 }))

            -- Close with Esc
            driver.keys(session, "<Esc>")
        end)
    end)
end)
