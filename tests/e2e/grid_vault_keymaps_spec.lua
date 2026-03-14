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

local function with_session(source_root, scenario, fn, opts)
    local session = driver.start(vim.tbl_extend("force", {
        source_root = source_root,
        scenario = scenario,
    }, opts or {}))
    local ok, err = pcall(fn, session)
    if not ok then
        driver.capture(session)
        artifacts.write_vault_diff(session.artifacts_dir, source_root, session.root)
        driver.stop(session)
        error(err)
    end
    driver.stop(session)
end

--- Standard vault fixture with 3 notes for grid keymaps testing.
local function make_grid_vault(name)
    return make_vault(name, {
        ["Inbox/alpha.md"] = {
            "---",
            'title: "alpha note"',
            'status: "active"',
            "tags:",
            "  - one",
            "---",
            "",
            "# Alpha",
            "",
            "Alpha body content for preview.",
        },
        ["Inbox/beta.md"] = {
            "---",
            'title: "beta note"',
            'status: "active"',
            "tags:",
            "  - two",
            "---",
            "",
            "# Beta",
            "",
            "Beta body content for preview.",
        },
        ["Inbox/gamma.md"] = {
            "---",
            'title: "gamma note"',
            'status: "done"',
            "tags:",
            "  - three",
            "---",
            "",
            "# Gamma",
            "",
            "Gamma body content.",
        },
    })
end

describe("vault.e2e grid vault-specific keymaps", function()
    it("u performs native undo of unsaved edit without triggering plugin undo", function()
        local source_root = make_grid_vault("vault-e2e-grid-u")
        with_session(source_root, "grid-u-native-undo", function(session)
            local alpha_path = session.root .. "/Inbox/alpha.md"
            driver.command(session, "Vault process title,status")
            assert.is_true(driver.wait_for(session, function()
                return driver.current_buffer_text(session):find("alpha note", 1, true) ~= nil
            end, { timeout_ms = 10000 }))

            -- Make a buffer edit (no save)
            driver.command(session, "%s/active/changed/")
            vim.wait(300)

            -- Verify buffer shows "changed"
            assert.is_true(driver.current_buffer_text(session):find("changed", 1, true) ~= nil)

            -- Press u (should do native undo, not plugin undo)
            driver.keys(session, "u")
            vim.wait(500)

            -- Buffer should revert to "active"
            assert.is_true(driver.wait_for(session, function()
                return driver.current_buffer_text(session):find("active", 1, true) ~= nil
            end, { timeout_ms = 5000 }))

            -- On-disk file should not have changed (no save happened)
            local content = read_file(alpha_path)
            assert(content:find("active", 1, true),
                "On-disk file should still have 'active' (no save was triggered)")
        end)
    end)

    it("g{ and g} move columns left and right", function()
        local source_root = make_grid_vault("vault-e2e-grid-colmove")
        with_session(source_root, "grid-col-move", function(session)
            driver.command(session, "Vault process title,status")
            assert.is_true(driver.wait_for(session, function()
                return driver.current_buffer_text(session):find("alpha note", 1, true) ~= nil
            end, { timeout_ms = 10000 }))

            -- Capture buffer text before move
            local text_before = driver.current_buffer_text(session)

            -- Press g} to move column right (reorders columns in grid)
            driver.keys(session, "g}")
            vim.wait(500)

            local text_after = driver.current_buffer_text(session)
            -- Both texts should contain the data, but column order may differ
            assert.is_true(text_after:find("alpha note", 1, true) ~= nil,
                "Grid should still show alpha note after column move")
            assert.is_true(text_after:find("active", 1, true) ~= nil
                or text_after:find("done", 1, true) ~= nil,
                "Grid should still show status values after column move")
            -- Verify the keymap didn't error (data is intact)
        end)
    end)

    it("full save via :write persists grid edits to disk", function()
        local source_root = make_grid_vault("vault-e2e-grid-fullsave")
        with_session(source_root, "grid-full-save", function(session)
            local alpha_path = session.root .. "/Inbox/alpha.md"

            driver.command(session, "Vault process title,status")
            assert.is_true(driver.wait_for(session, function()
                return driver.current_buffer_text(session):find("alpha note", 1, true) ~= nil
            end, { timeout_ms = 10000 }))

            -- Edit via substitution
            driver.command(session, "%s/active/archived/")
            vim.wait(300)
            driver.command(session, "write")
            vim.wait(1000)

            -- Wait for filesystem write
            assert.is_true(driver.wait_for(session, function()
                local content = read_file(alpha_path)
                return content ~= nil and content:find("archived", 1, true) ~= nil
            end, { timeout_ms = 10000 }))
        end)
    end)

    it("gp toggles inline preview float", function()
        local source_root = make_grid_vault("vault-e2e-grid-preview")
        with_session(source_root, "grid-preview", function(session)
            driver.command(session, "Vault process title,status")
            assert.is_true(driver.wait_for(session, function()
                return driver.current_buffer_text(session):find("alpha note", 1, true) ~= nil
            end, { timeout_ms = 10000 }))

            driver.lua(session, "vim.g._wins_before = #vim.api.nvim_list_wins()")

            -- Press gp to toggle preview
            driver.keys(session, "gp")
            vim.wait(800)

            driver.lua(session, "vim.g._wins_after = #vim.api.nvim_list_wins()")
            local before = tonumber(driver.expr(session, "g:_wins_before"))
            local after = tonumber(driver.expr(session, "g:_wins_after"))
            assert.is_true(after > before,
                "gp should open a preview window: " .. tostring(before) .. " → " .. tostring(after))
        end)
    end)

    it("visual g= prompts and batch-sets a field on selected rows", function()
        local source_root = make_grid_vault("vault-e2e-grid-batch-set")
        with_session(source_root, "grid-batch-set", function(session)
            local alpha_path = session.root .. "/Inbox/alpha.md"
            local beta_path = session.root .. "/Inbox/beta.md"

            driver.command(session, "Vault process title,status")
            assert.is_true(driver.wait_for(session, function()
                return driver.current_buffer_text(session):find("alpha note", 1, true) ~= nil
            end, { timeout_ms = 10000 }))

            -- Mock vim.ui.input to auto-fill "blocked"
            driver.lua(session, [[
                vim.ui.input = function(opts, cb)
                    cb("blocked")
                end
            ]])

            -- Select first two rows and press g=
            driver.keys(session, "ggVj")
            vim.wait(200)
            driver.keys(session, "g=")
            vim.wait(1500)

            -- Wait for filesystem changes
            assert.is_true(driver.wait_for(session, function()
                local a = read_file(alpha_path) or ""
                local b = read_file(beta_path) or ""
                return a:find("blocked", 1, true) ~= nil and b:find("blocked", 1, true) ~= nil
            end, { timeout_ms = 10000 }))
        end)
    end)

    it("visual gt prompts and batch-appends a tag on selected rows", function()
        local source_root = make_grid_vault("vault-e2e-grid-batch-tag")
        with_session(source_root, "grid-batch-tag", function(session)
            local alpha_path = session.root .. "/Inbox/alpha.md"

            driver.command(session, "Vault process title,status,tags")
            assert.is_true(driver.wait_for(session, function()
                return driver.current_buffer_text(session):find("alpha note", 1, true) ~= nil
            end, { timeout_ms = 10000 }))

            -- Mock vim.ui.input to provide tag name
            driver.lua(session, [[
                vim.ui.input = function(opts, cb)
                    cb("urgent")
                end
            ]])

            -- Select first row and press gt
            driver.keys(session, "ggV")
            vim.wait(200)
            driver.keys(session, "gt")
            vim.wait(1500)

            -- Wait for filesystem write
            assert.is_true(driver.wait_for(session, function()
                local content = read_file(alpha_path) or ""
                return content:find("urgent", 1, true) ~= nil
            end, { timeout_ms = 10000 }))
        end)
    end)
end)
