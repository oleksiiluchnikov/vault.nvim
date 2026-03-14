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
    if vim.fn.filereadable(path) == 0 then
        return nil
    end
    return table.concat(vim.fn.readfile(path), "\n")
end

local function frontmatter_status(path)
    local content = read_file(path)
    if not content then
        return nil
    end
    local value = content:match("\nstatus:%s*([^\n]+)") or content:match("^status:%s*([^\n]+)")
    if not value then
        return nil
    end
    value = vim.trim(value)
    value = value:gsub('^"', ""):gsub('"$', "")
    return value
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
    driver.lua(
        session,
        string.format(
            [[
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
    ]],
            needle
        )
    )
end

local function kanban_column_values(session)
    driver.lua(
        session,
        [[
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
    ]]
    )
    return driver.expr(session, "g:_kanban_columns")
end

local function kanban_neighbor(session, value, delta)
    driver.lua(
        session,
        string.format(
            [[ 
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
    ]],
            value,
            delta
        )
    )
    return driver.expr(session, "g:_kanban_neighbor")
end

describe("vault.e2e kanban keymaps full", function()
    it("opens the board with the expected columns", function()
        local source_root = make_vault("vault-e2e-kanban-keymaps-columns", {
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

        with_session(source_root, "kanban-keymaps-full-columns", function(session)
            driver.command(session, "Vault kanban group=status fields=title")

            assert.is_true(driver.wait_for(session, function()
                local columns = kanban_column_values(session)
                return columns:find("backlog", 1, true) ~= nil
                    and columns:find("active", 1, true) ~= nil
                    and columns:find("done", 1, true) ~= nil
            end, { timeout_ms = 10000 }))
        end)
    end)

    it("moves a card between groups with H and L and persists the frontmatter field", function()
        local source_root = make_vault("vault-e2e-kanban-keymaps-move", {
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

        with_session(source_root, "kanban-keymaps-full-move", function(session)
            local active_path = session.root .. "/Inbox/Active task.md"
            local move_key
            local reverse_key
            local moved_status

            driver.command(session, "Vault kanban group=status fields=title")

            assert.is_true(driver.wait_for(session, function()
                local body = driver.current_buffer_text(session)
                return body:find("Active task", 1, true) ~= nil
                    or kanban_column_values(session):find("active", 1, true) ~= nil
            end, { timeout_ms = 10000 }))

            moved_status = kanban_neighbor(session, "active", 1)
            if moved_status ~= "" then
                move_key = "L"
                reverse_key = "H"
            else
                moved_status = kanban_neighbor(session, "active", -1)
                move_key = "H"
                reverse_key = "L"
            end

            assert.is_true(moved_status ~= "")

            focus_kanban_card(session, "Active task")
            driver.keys(session, move_key)

            assert.is_true(driver.wait_for(session, function()
                return frontmatter_status(active_path) == moved_status
            end, { timeout_ms = 10000 }))

            focus_kanban_card(session, "Active task")
            driver.keys(session, reverse_key)

            assert.is_true(driver.wait_for(session, function()
                return frontmatter_status(active_path) == "active"
            end, { timeout_ms = 10000 }))
        end)
    end)
end)
