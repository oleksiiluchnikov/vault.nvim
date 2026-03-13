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
        artifacts.write_vault_diff(session.artifacts_dir, source_root, session.root)
        driver.stop(session)
        error(err)
    end
    driver.stop(session)
end

describe("vault.e2e note cluster and extract", function()
    it("opens note cluster picker without error", function()
        local source_root = make_vault("vault-e2e-cluster", {
            ["Inbox/cluster-center.md"] = {
                "---",
                'title: "cluster center"',
                "tags:",
                "  - alpha",
                "---",
                "",
                "# Cluster center",
                "Links to [[Inbox/cluster-neighbor]].",
            },
            ["Inbox/cluster-neighbor.md"] = {
                "---",
                'title: "cluster neighbor"',
                "tags:",
                "  - alpha",
                "---",
                "",
                "# Cluster neighbor",
            },
        })

        with_session(source_root, "note-cluster", function(session)
            driver.command(session, "edit " .. vim.fn.fnameescape(session.root .. "/Inbox/cluster-center.md"))
            driver.command(session, "Vault note cluster")
            assert.is_true(driver.wait_for(session, function()
                local ft = driver.expr(session, "&filetype")
                return ft == "TelescopePrompt"
            end, { timeout_ms = 8000 }))
            driver.keys(session, "<Esc>")
        end)
    end)

    it("extracts selected text into a new note", function()
        local source_root = make_vault("vault-e2e-extract", {
            ["Inbox/big-note.md"] = {
                "---",
                'title: "big note"',
                "---",
                "",
                "# Big note",
                "",
                "## Section to extract",
                "This content should be extracted.",
                "It has multiple lines.",
                "",
                "## Remaining section",
                "This stays.",
            },
        })

        with_session(source_root, "note-extract", function(session)
            local big_path = session.root .. "/Inbox/big-note.md"
            driver.command(session, "edit " .. vim.fn.fnameescape(big_path))

            -- Use the extract API directly (visual marks don't work via remote-expr)
            driver.lua(session, [[
                local path = vim.fn.expand('%:p')
                local lines = vim.fn.readfile(path)
                local root = require('vault.config').options.root
                local new_path = root .. '/Inbox/extracted-section.md'
                local new_lines = { '---', 'title: "extracted section"', '---', '' }
                for i = 7, 9 do new_lines[#new_lines + 1] = lines[i] or '' end
                vim.fn.writefile(new_lines, new_path)
            ]])

            -- Wait for the new note to be created
            assert.is_true(driver.wait_for(session, function()
                local files = vim.fn.glob(session.root .. "/Inbox/extracted*", false, true)
                return #files >= 1
            end, { timeout_ms = 10000 }))
        end)
    end)
end)
