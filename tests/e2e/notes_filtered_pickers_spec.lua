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

describe("vault.e2e filtered notes pickers", function()
    local source_root
    before_each(function()
        source_root = make_vault("vault-e2e-filtered-pickers", {
            ["Inbox/orphan-note.md"] = {
                "---",
                'title: "orphan note"',
                "---",
                "",
                "# Orphan",
                "No links anywhere.",
            },
            ["Inbox/linked-note.md"] = {
                "---",
                'title: "linked note"',
                "---",
                "",
                "# Linked",
                "See [[Inbox/orphan-note]].",
            },
            ["Inbox/empty-note.md"] = {
                "---",
                'title: "empty note"',
                "---",
            },
            ["Inbox/no-frontmatter.md"] = {
                "# No frontmatter",
                "This note has no YAML frontmatter at all.",
            },
        })
    end)

    local function smoke_picker(cmd, scenario)
        with_session(source_root, scenario, function(session)
            driver.command(session, cmd)
            assert.is_true(driver.wait_for(session, function()
                local ft = driver.expr(session, "&filetype")
                return ft == "TelescopePrompt"
            end, { timeout_ms = 8000 }))
            driver.keys(session, "<Esc>")
        end)
    end

    it("opens notes orphans picker", function()
        smoke_picker("Vault notes orphans", "picker-orphans")
    end)

    it("opens notes leaves picker", function()
        smoke_picker("Vault notes leaves", "picker-leaves")
    end)

    it("opens notes empty picker or reports no results", function()
        with_session(source_root, "picker-empty", function(session)
            -- Empty notes picker may return 0 results — check it doesn't crash
            driver.lua(session, [[
                local ok, err = pcall(vim.cmd, 'Vault notes empty')
                vim.g._empty_picker_ok = ok
            ]])
            local ok = driver.expr(session, "g:_empty_picker_ok")
            assert.is_true(ok ~= "0" and ok ~= "v:false")
        end)
    end)

    it("opens notes no-frontmatter picker", function()
        smoke_picker("Vault notes no-frontmatter", "picker-no-fm")
    end)
end)
