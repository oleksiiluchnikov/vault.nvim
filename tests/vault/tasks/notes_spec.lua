describe("vault.tasks.notes", function()
    local Config
    local task_notes
    local tmp_root

    local function clear_modules()
        package.loaded["vault.tasks.notes"] = nil
        package.loaded["vault.config"] = nil
        package.loaded["vault.bases.views.shared"] = nil
    end

    local function setup_root()
        tmp_root = vim.fn.tempname() .. "_vault_tasks_notes"
        vim.fn.mkdir(tmp_root .. "/Tasks", "p")
        Config = require("vault.config")
        Config.reset()
        Config.setup({
            root = tmp_root,
            ext = ".md",
            features = {
                cmp = false,
                commands = false,
                watcher = false,
            },
        })
        task_notes = require("vault.tasks.notes")
    end

    local function write_file(path, lines)
        vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
        vim.fn.writefile(lines, path)
    end

    before_each(function()
        clear_modules()
        setup_root()
    end)

    after_each(function()
        if tmp_root and tmp_root ~= "" then
            vim.fn.delete(tmp_root, "rf")
        end
        clear_modules()
    end)

    it("creates a timestamped task note with frontmatter defaults", function()
        local orig_date = os.date
        os.date = function(fmt)
            if fmt == "%Y%m%d%H%M%S" then
                return "20260306123456"
            end
            return orig_date(fmt)
        end

        local path = task_notes.create("Implement fast task capture")

        os.date = orig_date

        assert.is_not_nil(path)
        assert.is_true(path:match("T%-20260306123456 Implement fast task capture%.md$") ~= nil)
        assert.are.equal(1, vim.fn.filereadable(path))

        local lines = vim.fn.readfile(path)
        local text = table.concat(lines, "\n")
        assert.is_true(text:find('status: "[[Status - Backlog]]"', 1, true) ~= nil)
        assert.is_true(text:find('priority: "[[Priority - Medium]]"', 1, true) ~= nil)
        assert.is_true(text:find('title: "Implement fast task capture"', 1, true) ~= nil)
    end)

    it("updates status only for valid transitions", function()
        local path = tmp_root .. "/Tasks/T-20260306120000 Transition test.md"
        write_file(path, {
            "---",
            'status: "[[Status - Backlog]]"',
            'priority: "[[Priority - Medium]]"',
            'title: "Transition test"',
            "modified: 20260306120000",
            "---",
            "",
            "# Transition test",
        })

        local ok1, err1 = task_notes.set_status(path, "Status - Todo")
        assert.is_true(ok1)
        assert.is_nil(err1)

        local data1 = task_notes.read_task(path)
        assert.are.equal("Status - Todo", data1.status)

        local ok2, err2 = task_notes.set_status(path, "Status - Done")
        assert.is_false(ok2)
        assert.is_true(type(err2) == "string" and err2:find("Invalid transition", 1, true) ~= nil)

        local data2 = task_notes.read_task(path)
        assert.are.equal("Status - Todo", data2.status)
    end)

    it("pick-next excludes blocked tasks and sorts by priority", function()
        write_file(tmp_root .. "/Tasks/T-20260306120001 Blocker done.md", {
            "---",
            'status: "[[Status - Done]]"',
            'priority: "[[Priority - Low]]"',
            'title: "Blocker done"',
            "blocked_by: []",
            "---",
            "",
            "# Blocker done",
        })

        write_file(tmp_root .. "/Tasks/T-20260306120002 High unblocked.md", {
            "---",
            'status: "[[Status - Todo]]"',
            'priority: "[[Priority - High]]"',
            'title: "High unblocked"',
            "blocked_by: []",
            "---",
            "",
            "# High unblocked",
        })

        write_file(tmp_root .. "/Tasks/T-20260306120003 Critical blocked.md", {
            "---",
            'status: "[[Status - Todo]]"',
            'priority: "[[Priority - Critical]]"',
            'title: "Critical blocked"',
            "blocked_by:",
            "  - \"[[T-20260306120099 Missing blocker]]\"",
            "---",
            "",
            "# Critical blocked",
        })

        local picked = task_notes.pick_candidates()
        assert.are.equal(1, #picked)
        assert.are.equal("High unblocked", picked[1].title)
    end)

    it("doctor reports missing, unknown, and non-wikilink statuses", function()
        write_file(tmp_root .. "/Tasks/T-20260306121001 Missing status.md", {
            "---",
            'title: "Missing status"',
            "---",
            "",
            "# Missing status",
        })

        write_file(tmp_root .. "/Tasks/T-20260306121002 Unknown status.md", {
            "---",
            'title: "Unknown status"',
            'status: "[[Status - Weird]]"',
            "---",
            "",
            "# Unknown status",
        })

        write_file(tmp_root .. "/Tasks/T-20260306121003 Plain status.md", {
            "---",
            'title: "Plain status"',
            'status: "Status - Todo"',
            "---",
            "",
            "# Plain status",
        })

        local report = task_notes.doctor({ fix = false })
        assert.are.equal(3, report.scanned)
        assert.are.equal(3, #report.issues)
        assert.are.equal(0, report.fixed)

        local kinds = {}
        for _, issue in ipairs(report.issues) do
            kinds[issue.kind] = true
        end
        assert.is_true(kinds["missing-status"])
        assert.is_true(kinds["unknown-status"])
        assert.is_true(kinds["non-wikilink-status"])
    end)

    it("doctor fix mode repairs missing and non-wikilink statuses", function()
        local missing = tmp_root .. "/Tasks/T-20260306122001 Missing status.md"
        local plain = tmp_root .. "/Tasks/T-20260306122002 Plain status.md"

        write_file(missing, {
            "---",
            'title: "Missing status"',
            "---",
            "",
            "# Missing status",
        })

        write_file(plain, {
            "---",
            'title: "Plain status"',
            'status: "Status - Todo"',
            "---",
            "",
            "# Plain status",
        })

        local report = task_notes.doctor({ fix = true })
        assert.are.equal(2, report.scanned)
        assert.are.equal(2, report.fixed)

        local lines_missing = table.concat(vim.fn.readfile(missing), "\n")
        local lines_plain = table.concat(vim.fn.readfile(plain), "\n")

        assert.is_true(lines_missing:find('status: "[[Status - Backlog]]"', 1, true) ~= nil)
        assert.is_true(lines_plain:find('status: "[[Status - Todo]]"', 1, true) ~= nil)
    end)
end)
