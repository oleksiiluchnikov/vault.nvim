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

describe("vault.e2e taxonomy and process journeys", function()
    it("covers :Vault process edit, save, reload, and undo on a cloned vault", function()
        local source_root = make_source_vault("vault-e2e-process-source", {
            ["Inbox/Process Note.md"] = {
                "---",
                'status: "[[Status - Todo]]"',
                'title: "Process Note"',
                "---",
                "",
                "# Process Note",
            },
        })

        with_session(source_root, "process-edit-save-undo", function(session)
            driver.command(session, "Vault process title,status")
            assert.is_true(driver.wait_for(session, function()
                return driver.current_buffer_name(session):find("vault://grid%-process", 1) ~= nil
            end))

            local before = driver.current_buffer_text(session)
            assert.is_true(before:find("Process Note", 1, true) ~= nil)
            assert.is_true(before:find("Status - Todo", 1, true) ~= nil)

            driver.command(session, [[%s/Status - Todo/Status - Done/]])
            assert.is_true(driver.wait_for(session, function()
                return driver.current_buffer_text(session):find("Status - Done", 1, true) ~= nil
            end))
            driver.command(session, "write")

            local clone_file = session.root .. "/Inbox/Process Note.md"
            assert.is_true(driver.wait_for(session, function()
                return file_contains(clone_file, "Status - Done")
            end))

            driver.command(session, "Vault process undo")
            assert.is_true(driver.wait_for(session, function()
                return file_contains(clone_file, "Status - Todo")
            end))
        end)
    end)

    it("covers :Vault classify edit and persisted taxonomy mutation", function()
        local source_root = make_source_vault("vault-e2e-classify-source", {
            ["Inbox/Needs Kind.md"] = {
                "---",
                "categories:",
                '  - "[[category - Notes]]"',
                'title: "Needs Kind"',
                "---",
                "",
                "# Needs Kind",
            },
        })

        with_session(source_root, "classify-edit-save", function(session)
            driver.command(session, "Vault classify")
            assert.is_true(driver.wait_for(session, function()
                return driver.current_buffer_name(session):find("vault://grid%-process", 1) ~= nil
            end))

            local before = driver.current_buffer_text(session)
            assert.is_true(before:find("Needs Kind", 1, true) ~= nil)

            driver.command(session, "%s/category - Notes/category - person/")
            assert.is_true(driver.wait_for(session, function()
                return driver.current_buffer_text(session):find("category - person", 1, true) ~= nil
            end))
            driver.command(session, "write")

            local clone_file = session.root .. "/Inbox/Needs Kind.md"
            assert.is_true(driver.wait_for(session, function()
                return file_contains(clone_file, "[[category - person]]")
            end))
        end)
    end)

    it("covers :Vault taxonomy preview, apply, and undo-last", function()
        local source_root = make_source_vault("vault-e2e-taxonomy-source", {
            ["Inbox/Foo.md"] = {
                "---",
                "categories:",
                '  - "[[category - person]]"',
                'title: "Foo"',
                "---",
                "",
                "# Foo",
            },
        })

        with_session(source_root, "taxonomy-preview-apply-undo", function(session)
            driver.command(session, "Vault taxonomy preview")
            assert.is_true(driver.wait_for(session, function()
                return driver.current_buffer_name(session):find("vault://taxonomy%-preview", 1) ~= nil
            end))

            local preview = driver.current_buffer_text(session)
            assert.is_true(preview:find("Inbox/person - Foo", 1, true) ~= nil)

            driver.command(session, "Vault taxonomy apply")
            assert.is_true(driver.wait_for(session, function()
                return vim.fn.filereadable(session.root .. "/Inbox/person - Foo.md") == 1
            end, { timeout_ms = 8000 }))

            driver.command(session, "Vault taxonomy undo-last")
            assert.is_true(driver.wait_for(session, function()
                return vim.fn.filereadable(session.root .. "/Inbox/Foo.md") == 1
            end, { timeout_ms = 8000 }))
        end)
    end)
end)
