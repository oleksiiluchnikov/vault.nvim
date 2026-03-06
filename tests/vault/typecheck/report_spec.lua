describe("vault.typecheck.report", function()
    local report
    local Config
    local tmp_root

    local function wl(name)
        return "[[" .. name .. "]]"
    end

    local function write_file(rel_path, lines)
        local path = tmp_root .. "/" .. rel_path
        vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
        vim.fn.writefile(lines, path)
        return path
    end

    local function setup_vault()
        tmp_root = vim.fn.tempname() .. "_vault_report"
        vim.fn.mkdir(tmp_root .. "/Templates", "p")
        vim.fn.mkdir(tmp_root .. "/Tasks", "p")
        vim.fn.mkdir(tmp_root .. "/References", "p")

        -- Category note with template field
        write_file("Tasks.md", {
            "---",
            'template: "' .. wl("task-template") .. '"',
            "---",
        })

        -- Template
        write_file("Templates/task-template.md", {
            "---",
            'type: "task"',
            'status: "' .. wl("Status - Backlog") .. '"',
            'title: "{{title}}"',
            'due: ""',
            "blocked_by: []",
            "---",
        })

        -- Status reference notes
        write_file("References/Status - Backlog.md", { "---", "---" })
        write_file("References/Status - Done.md", { "---", "---" })

        -- Config
        package.loaded["vault.config"] = nil
        package.loaded["vault.typecheck.report"] = nil
        package.loaded["vault.typecheck.resolve"] = nil
        package.loaded["vault.typecheck.frontmatter"] = nil
        package.loaded["vault.typecheck.infer"] = nil
        package.loaded["vault.typecheck.validate"] = nil

        Config = require("vault.config")
        Config.reset()
        Config.setup({
            root = tmp_root,
            ext = ".md",
            features = { cmp = false, commands = false, watcher = false },
        })
        report = require("vault.typecheck.report")
        report.clear_cache()
    end

    before_each(function()
        setup_vault()
    end)

    after_each(function()
        if tmp_root then
            vim.fn.delete(tmp_root, "rf")
        end
    end)

    describe("validate_file()", function()
        it("returns no errors for valid task note", function()
            local path = write_file("Tasks/T-001 Test task.md", {
                "---",
                "categories:",
                '  - "' .. wl("Tasks") .. '"',
                'type: "task"',
                'status: "' .. wl("Status - Done") .. '"',
                'title: "Test task"',
                'due: ""',
                "blocked_by: []",
                "---",
            })

            local errors, resolve_err = report.validate_file(path)
            assert.is_nil(resolve_err)
            assert.equals(0, #errors)
        end)

        it("returns error for missing required field", function()
            local path = write_file("Tasks/T-002 Missing type.md", {
                "---",
                "categories:",
                '  - "' .. wl("Tasks") .. '"',
                'status: "' .. wl("Status - Backlog") .. '"',
                "---",
            })

            local errors, resolve_err = report.validate_file(path)
            assert.is_nil(resolve_err)
            assert.truthy(#errors > 0)
            local found = false
            for _, e in ipairs(errors) do
                if e.field == "type" then found = true end
            end
            assert.is_true(found)
        end)

        it("returns resolve_err for note without categories", function()
            local path = write_file("orphan.md", {
                "---",
                'title: "orphan"',
                "---",
            })

            local errors, resolve_err = report.validate_file(path)
            assert.truthy(resolve_err)
            assert.equals(0, #errors)
        end)
    end)

    describe("doctor()", function()
        it("scans vault and reports errors", function()
            write_file("Tasks/T-003 Good.md", {
                "---",
                "categories:",
                '  - "' .. wl("Tasks") .. '"',
                'type: "task"',
                'status: "' .. wl("Status - Backlog") .. '"',
                'title: "Good"',
                "---",
            })
            write_file("Tasks/T-004 Bad status.md", {
                "---",
                "categories:",
                '  - "' .. wl("Tasks") .. '"',
                'type: "task"',
                'status: "plain text"',
                'title: "Bad"',
                "---",
            })
            write_file("orphan.md", {
                "---",
                'title: "no category"',
                "---",
            })

            local dr = report.doctor()
            assert.truthy(dr.scanned > 0)
            assert.truthy(#dr.errors > 0)
            assert.truthy(#dr.untyped > 0)
        end)
    end)
end)
