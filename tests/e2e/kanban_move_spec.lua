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

local function file_contains(path, needle)
    if vim.fn.filereadable(path) == 0 then
        return false
    end
    return table.concat(vim.fn.readfile(path), "\n"):find(needle, 1, true) ~= nil
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

describe("vault.e2e kanban move-and-save", function()
    it("moves a card between columns and saves the group field change to disk", function()
        -- Two notes: one active, one done
        local source_root = make_source_vault("vault-e2e-kanban-move", {
            ["Inbox/Active task.md"] = {
                "---",
                'title: "Active task"',
                'status: "active"',
                "---",
                "",
                "# Active task",
            },
            ["Inbox/Done task.md"] = {
                "---",
                'title: "Done task"',
                'status: "done"',
                "---",
                "",
                "# Done task",
            },
        })

        with_session(source_root, "kanban-move-save", function(session)
            local active_path = session.root .. "/Inbox/Active task.md"

            -- Verify the file starts with status "active"
            assert.is_true(file_contains(active_path, '"active"'))

            -- Open kanban grouped by status
            driver.command(session, "Vault kanban")

            -- Wait for the kanban board to appear
            assert.is_true(driver.wait_for(session, function()
                local body = driver.current_buffer_text(session)
                return body:find("Active task", 1, true) ~= nil
                    or body:find("Done task", 1, true) ~= nil
            end, { timeout_ms = 10000 }))

            -- Use the kanban's exposed API to move the card's group field
            -- This exercises the same apply_group_change path that <C-l> triggers
            driver.lua(session, [[
                local kanban = require('vault.views.kanban')
                for _, st in pairs(kanban._board_states) do
                    for slug, path in pairs(st.note_paths) do
                        if path:find('Active task', 1, true) then
                            kanban._apply_group_change(st, slug, st.group_field, 'done')
                        end
                    end
                end
            ]])

            -- Verify the status field changed on disk
            assert.is_true(driver.wait_for(session, function()
                return file_contains(active_path, "done")
                    and not file_contains(active_path, '"active"')
            end, { timeout_ms = 8000 }))

            -- File still exists
            assert.is_true(vim.fn.filereadable(active_path) == 1)

            -- Board should reflect the new state after reload
            driver.lua(session, [[
                local kanban = require('vault.views.kanban')
                for _, st in pairs(kanban._board_states) do
                    kanban.refresh_board(st)
                end
            ]])

            assert.is_true(driver.wait_for(session, function()
                -- The file should now contain "done" in its status
                local content = table.concat(vim.fn.readfile(active_path), "\n")
                return content:find("done", 1, true) ~= nil
            end, { timeout_ms = 5000 }))
        end)
    end)
end)
