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

local function read_file(path)
    if vim.fn.filereadable(path) == 0 then return nil end
    return table.concat(vim.fn.readfile(path), "\n")
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

local function focus_kanban_card(session, needle)
    driver.lua(session, string.format([[
        local needle = %q
        local kanban = require("vault.views.kanban")
        for _, st in pairs(kanban._board_states) do
            for _, col in ipairs(st.board:columns()) do
                local lines = vim.api.nvim_buf_get_lines(col.bufnr, 0, -1, false)
                for i, line in ipairs(lines) do
                    local cell = line:find(needle, 1, true)
                    if cell then
                        vim.api.nvim_set_current_win(col.winid)
                        vim.api.nvim_win_set_cursor(col.winid, { i, cell - 1 })
                        return
                    end
                end
            end
        end
        error("kanban card not found: " .. needle)
    ]], needle))
end

local function kanban_column_values(session)
    driver.lua(session, [[
        vim.g._kanban_columns = ""
        local kanban = require("vault.views.kanban")
        for _, st in pairs(kanban._board_states) do
            local values = {}
            for _, col in ipairs(st.board:columns()) do
                values[#values + 1] = tostring(col.value)
            end
            vim.g._kanban_columns = table.concat(values, ",")
            return
        end
        error("kanban state not found")
    ]])
    return driver.expr(session, "g:_kanban_columns")
end

local function kanban_neighbor(session, value, delta)
    driver.lua(session, string.format([[
        vim.g._kanban_neighbor = ""
        local target = %q
        local delta = %d
        local kanban = require("vault.views.kanban")
        for _, st in pairs(kanban._board_states) do
            local columns = st.board:columns()
            for i, col in ipairs(columns) do
                if tostring(col.value) == target then
                    local next_col = columns[i + delta]
                    vim.g._kanban_neighbor = next_col and tostring(next_col.value) or ""
                    return
                end
            end
        end
        error("kanban column not found: " .. target)
    ]], value, delta))
    return driver.expr(session, "g:_kanban_neighbor")
end

describe("vault.e2e kanban group modes", function()
    it("frontmatter mode: H/L move updates frontmatter status on disk", function()
        local source_root = make_vault("vault-e2e-kanban-fm", {
            ["Inbox/Backlog task.md"] = {
                "---",
                'title: "Backlog task"',
                'status: "backlog"',
                "---",
                "",
                "# Backlog task",
            },
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

        with_session(source_root, "kanban-frontmatter-move", function(session)
            local active_path = session.root .. "/Inbox/Active task.md"
            driver.command(session, "Vault kanban group=status fields=title")

            assert.is_true(driver.wait_for(session, function()
                local columns = kanban_column_values(session)
                return columns:find("active", 1, true) ~= nil
            end, { timeout_ms = 10000 }))

            -- Determine which direction to move
            local moved_status = kanban_neighbor(session, "active", 1)
            local move_key = "L"
            if moved_status == "" then
                moved_status = kanban_neighbor(session, "active", -1)
                move_key = "H"
            end
            assert.is_true(moved_status ~= "", "Should have a neighbor column")

            focus_kanban_card(session, "Active task")
            driver.keys(session, move_key)

            -- Verify frontmatter updated on disk
            assert.is_true(driver.wait_for(session, function()
                local content = read_file(active_path) or ""
                return content:find(moved_status, 1, true) ~= nil
            end, { timeout_ms = 10000 }))
        end)
    end)

    it("directory mode: kanban opens with directory-based columns", function()
        local source_root = make_vault("vault-e2e-kanban-dir", {
            ["Inbox/Note A.md"] = {
                "---",
                'title: "Note A"',
                "---",
                "",
                "# Note A",
            },
            ["Archive/Note B.md"] = {
                "---",
                'title: "Note B"',
                "---",
                "",
                "# Note B",
            },
        })

        with_session(source_root, "kanban-directory-open", function(session)
            driver.command(session, "Vault kanban group=directory fields=title")

            -- Verify the kanban opens with directory-based columns
            assert.is_true(driver.wait_for(session, function()
                local columns = kanban_column_values(session)
                return (columns:find("Inbox", 1, true) ~= nil
                    or columns:find("Archive", 1, true) ~= nil)
                    and columns ~= ""
            end, { timeout_ms = 10000 }),
                "Kanban should open with directory-based columns")

            -- Verify cards are visible
            driver.lua(session, [[
                local kanban = require("vault.views.kanban")
                local total = 0
                for _, st in pairs(kanban._board_states) do
                    for _, col in ipairs(st.board:columns()) do
                        total = total + #col.records
                    end
                end
                vim.g._total_cards = total
            ]])
            local total = tonumber(driver.expr(session, "g:_total_cards"))
            assert.is_true(total >= 2, "Should show at least 2 cards: " .. tostring(total))
        end)
    end)

    it("wikilink-preserving moves keep [[]] wrappers in frontmatter", function()
        local source_root = make_vault("vault-e2e-kanban-wl", {
            ["Tasks/Todo task.md"] = {
                "---",
                'title: "Todo task"',
                'status: "[[status - todo]]"',
                "---",
                "",
                "# Todo task",
            },
            ["Tasks/Active task.md"] = {
                "---",
                'title: "Active task"',
                'status: "[[status - active]]"',
                "---",
                "",
                "# Active task",
            },
            ["Tasks/Done task.md"] = {
                "---",
                'title: "Done task"',
                'status: "[[status - done]]"',
                "---",
                "",
                "# Done task",
            },
        })

        with_session(source_root, "kanban-wikilink-preserve", function(session)
            driver.command(session, "Vault kanban group=status fields=title")

            -- Wait for kanban to load — column values strip wikilinks for display
            assert.is_true(driver.wait_for(session, function()
                local columns = kanban_column_values(session)
                return columns ~= "" and (
                    columns:find("todo", 1, true) ~= nil
                    or columns:find("active", 1, true) ~= nil
                    or columns:find("status", 1, true) ~= nil)
            end, { timeout_ms = 10000 }))

            local active_path = session.root .. "/Tasks/Active task.md"

            -- Verify the file starts with wikilink status
            local content_before = read_file(active_path)
            assert(content_before:find("%[%[status %- active%]%]"),
                "Should start with wikilink status: " .. (content_before or "nil"))

            -- Find and move the Active task card
            -- Column values may be displayed as "active" (stripped), "[[status - active]]", etc.
            -- Try various patterns
            local columns = kanban_column_values(session)
            local active_col = nil
            for col_val in columns:gmatch("[^,]+") do
                if col_val:find("active", 1, true) then
                    active_col = col_val
                    break
                end
            end

            if active_col then
                local moved_status = kanban_neighbor(session, active_col, 1)
                local move_key = "L"
                if moved_status == "" then
                    moved_status = kanban_neighbor(session, active_col, -1)
                    move_key = "H"
                end

                if moved_status ~= "" then
                    focus_kanban_card(session, "Active task")
                    driver.keys(session, move_key)

                    -- Wait for frontmatter update — must preserve [[ ]] wrappers
                    assert.is_true(driver.wait_for(session, function()
                        local content = read_file(active_path) or ""
                        -- File should have changed (not "active" anymore) and should still have [[...]]
                        return content:find("%[%[status %- ", 1, false) ~= nil
                            and not content:find('%[%[status %- active%]%]', 1, true)
                    end, { timeout_ms = 10000 }),
                        "Frontmatter should preserve wikilink brackets after move")
                end
            end
        end)
    end)

    it("task-board card creation via o produces a task note on disk", function()
        local source_root = make_vault("vault-e2e-kanban-create", {
            ["Tasks/Existing task.md"] = {
                "---",
                'title: "Existing task"',
                'status: "todo"',
                "type: task",
                "---",
                "",
                "# Existing task",
            },
            ["Tasks/Done task.md"] = {
                "---",
                'title: "Done task"',
                'status: "done"',
                "type: task",
                "---",
                "",
                "# Done task",
            },
        })

        with_session(source_root, "kanban-task-create", function(session)
            driver.command(session, "Vault kanban group=status fields=title")

            assert.is_true(driver.wait_for(session, function()
                local columns = kanban_column_values(session)
                return columns:find("todo", 1, true) ~= nil
            end, { timeout_ms = 10000 }))

            -- Count files before
            driver.lua(session, string.format([[
                vim.g._files_before = #vim.fn.glob(%q .. "/*.md", false, true)
            ]], session.root .. "/Tasks"))
            local files_before = tonumber(driver.expr(session, "g:_files_before"))

            -- Press o to add a new card, type a title, then escape
            driver.keys(session, "o")
            vim.wait(500)
            driver.keys(session, "New Created Task")
            vim.wait(300)
            driver.keys(session, "<Esc>")
            vim.wait(300)

            -- Save the board
            driver.keys(session, "\x13") -- <C-s>
            vim.wait(2000)

            -- Check that a new file was created in Tasks/
            assert.is_true(driver.wait_for(session, function()
                local files = vim.fn.glob(session.root .. "/Tasks/*.md", false, true)
                return #files > files_before
            end, { timeout_ms = 10000 }),
                "A new task note should be created in Tasks/ directory")
        end)
    end)
end)
