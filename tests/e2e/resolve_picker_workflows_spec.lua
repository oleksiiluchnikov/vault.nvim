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

describe("vault.e2e resolve-picker workflows", function()
    it("covers :Vault note merge through the resolve picker", function()
        local source_root = make_source_vault("vault-e2e-note-merge", {
            ["Inbox/source.md"] = {
                "---",
                'title: "source"',
                "---",
                "",
                "# source",
                "source body",
            },
            ["Reference/target.md"] = {
                "---",
                'title: "target"',
                "---",
                "",
                "# target",
                "target body",
            },
        })

        with_session(source_root, "resolve-merge", function(session)
            local source_path = session.root .. "/Inbox/source.md"
            local target_path = session.root .. "/Reference/target.md"
            driver.command(session, "edit " .. vim.fn.fnameescape(source_path))
            driver.command(session, "Vault note merge")
            driver.keys(session, "Reference/target<CR>")
            assert.is_true(driver.wait_for(session, function()
                return driver.current_buffer_text(session):find("Merge:", 1, true) ~= nil
            end, { timeout_ms = 8000 }))
            driver.keys(session, "<CR>")

            assert.is_true(driver.wait_for(session, function()
                return vim.fn.filereadable(source_path) == 0 and vim.fn.filereadable(target_path) == 1
            end, { timeout_ms = 8000 }))
            assert.is_true(vim.fn.filereadable(session.root .. "/.trash/source.md") == 1)
        end)
    end)

    it("covers note retarget create through the resolve picker", function()
        local source_root = make_source_vault("vault-e2e-note-retarget", {
            ["Inbox/source.md"] = {
                "---",
                'title: "source"',
                "---",
                "",
                "# source",
            },
        })

        with_session(source_root, "resolve-retarget-create", function(session)
            local source_path = session.root .. "/Inbox/source.md"
            local renamed_path = session.root .. "/retargeted-note.md"
            driver.command(session, "edit " .. vim.fn.fnameescape(source_path))
            driver.lua(session, "require('vault.notes.workflows').open_retarget_picker()")
            driver.keys(session, "retargeted-note")
            driver.keys(session, "<C-n>")

            assert.is_true(driver.wait_for(session, function()
                return vim.fn.filereadable(renamed_path) == 1 and vim.fn.filereadable(source_path) == 0
            end, { timeout_ms = 8000 }))
        end)
    end)

    it("covers :Vault tags promote through the resolve picker", function()
        local source_root = make_source_vault("vault-e2e-tag-promote", {
            ["Inbox/tag-source.md"] = {
                "---",
                "tags:",
                "  - wash-face",
                "---",
                "# tag source",
                "Do #wash-face now.",
            },
        })

        with_session(source_root, "resolve-tag-promote", function(session)
            local source_path = session.root .. "/Inbox/tag-source.md"
            driver.command(session, "edit " .. vim.fn.fnameescape(source_path))
            driver.command(session, "Vault tags promote wash-face")
            driver.keys(session, "wash-face-canonical")
            driver.keys(session, "<C-n>")

            assert.is_true(driver.wait_for(session, function()
                return table.concat(vim.fn.readfile(source_path), "\n"):find("[[wash-face-canonical|wash-face]]", 1, true) ~= nil
            end, { timeout_ms = 8000 }))
            assert.is_true(vim.fn.filereadable(session.root .. "/wash-face-canonical.md") == 1)
        end)
    end)
end)
