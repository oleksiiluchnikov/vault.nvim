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

describe("vault.e2e note commands", function()
    local source_root

    before_each(function()
        source_root = make_vault("vault-e2e-note-commands", {
            ["Inbox/alpha-note.md"] = {
                "---",
                'title: "alpha note"',
                'tags: [alpha]',
                "---",
                "",
                "# Alpha note",
            },
            ["Inbox/delete-me.md"] = {
                "---",
                'title: "delete me"',
                'tags: [delete]',
                "---",
                "",
                "# Delete me",
            },
            ["Projects/preview-note.md"] = {
                "---",
                'title: "preview note"',
                'tags: [preview]',
                "---",
                "",
                "# Preview note",
                "Has enough body text for preview.",
            },
        })
    end)

    it("deletes a note after confirmation", function()
        with_session(source_root, "note-commands-delete", function(session)
            local doomed_path = session.root .. "/Inbox/delete-me.md"

            driver.command(session, "edit " .. vim.fn.fnameescape(doomed_path))
            driver.lua(session, [[
                vim.ui.select = function(items, opts, on_choice)
                    on_choice("Yes", 1)
                end

                require("vault.ui.confirm").confirm = function(opts)
                    vim.ui.select({ "Yes", "No" }, { prompt = opts.message }, function(choice)
                        if choice == "Yes" then
                            opts.on_yes()
                            return
                        end
                        if opts.on_no then
                            opts.on_no()
                        end
                    end)
                end
            ]])

            driver.command(session, "Vault note delete")

            assert.is_true(driver.wait_for(session, function()
                return vim.fn.filereadable(doomed_path) == 0
            end, { timeout_ms = 10000 }))

            local trash_files = vim.fn.glob(session.root .. "/.trash/delete-me*.md", false, true)
            assert.is_true(#trash_files >= 1)
        end)
    end)

    it("opens a preview window for the current note", function()
        with_session(source_root, "note-commands-preview", function(session)
            local note_path = session.root .. "/Projects/preview-note.md"

            driver.command(session, "edit " .. vim.fn.fnameescape(note_path))
            driver.lua(session, [[
                vim.cmd("command! -nargs=1 Glow split | execute 'edit ' .. <q-args>")
            ]])
            driver.lua(session, "vim.g._wins_before = #vim.api.nvim_list_wins()")

            driver.command(session, "Vault note preview")

            assert.is_true(driver.wait_for(session, function()
                local before = tonumber(driver.expr(session, "g:_wins_before")) or 0
                local after = tonumber(driver.expr(session, "luaeval('#vim.api.nvim_list_wins()')")) or 0
                return after > before
            end, { timeout_ms = 10000 }))
        end)
    end)

    it("opens note properties without error", function()
        with_session(source_root, "note-commands-properties", function(session)
            local note_path = session.root .. "/Inbox/alpha-note.md"

            driver.command(session, "edit " .. vim.fn.fnameescape(note_path))
            driver.lua(session, [[
                local ok, err = pcall(vim.cmd, "Vault note properties")
                vim.g._note_properties_ok = ok and "1" or "0"
                vim.g._note_properties_err = tostring(err or "")
            ]])

            assert.is_true(driver.wait_for(session, function()
                local ok = driver.expr(session, "g:_note_properties_ok")
                local ft = driver.expr(session, "&filetype")
                return ok == "1" and ft == "TelescopePrompt"
            end, { timeout_ms = 10000 }))

            driver.keys(session, "<Esc>")
        end)
    end)
end)
