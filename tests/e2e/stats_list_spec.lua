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

describe("vault.e2e stats and list view", function()
    local source_root
    before_each(function()
        source_root = make_vault("vault-e2e-stats-list", {
            ["Inbox/stat-note.md"] = {
                "---",
                'title: "stat note"',
                'status: "active"',
                "---",
                "",
                "# Stat note",
            },
            ["Inbox/stat-note-2.md"] = {
                "---",
                'title: "stat note 2"',
                'status: "done"',
                "---",
                "",
                "# Stat note 2",
            },
        })
    end)

    it("opens stats without error", function()
        with_session(source_root, "stats", function(session)
            driver.command(session, "Vault stats")
            assert.is_true(driver.wait_for(session, function()
                -- Stats opens a floating window or buffer with vault metrics
                local win_count = driver.expr(session, "luaeval('#vim.api.nvim_list_wins()')")
                local messages = driver.expr(session, "execute('messages')")
                return (tonumber(win_count) and tonumber(win_count) >= 2)
                    or messages:find("stat", 1, true) ~= nil
                    or messages:find("notes", 1, true) ~= nil
            end, { timeout_ms = 8000 }))
        end)
    end)

    it("opens list view without error", function()
        with_session(source_root, "list-view", function(session)
            driver.command(session, "Vault list")
            assert.is_true(driver.wait_for(session, function()
                local bufname = driver.current_buffer_name(session)
                return bufname:find("vault://", 1, true) ~= nil
            end, { timeout_ms = 10000 }))
        end)
    end)
end)
