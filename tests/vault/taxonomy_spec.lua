local root_cwd = vim.fn.getcwd()
local tmp_root = root_cwd .. "/tests/tmp_taxonomy_vault"

local function rm_rf(path)
    if vim.fn.isdirectory(path) == 1 then
        vim.fn.delete(path, "rf")
    elseif vim.fn.filereadable(path) == 1 then
        vim.fn.delete(path)
    end
end

local function write(path, lines)
    local dir = vim.fn.fnamemodify(path, ":h")
    vim.fn.mkdir(dir, "p")
    vim.fn.writefile(lines, path)
end

local function setup_vault(taxonomy_opts)
    require("vault").setup({
        root = tmp_root,
        ext = ".md",
        features = {
            cmp = false,
            commands = true,
            watcher = false,
        },
        taxonomy = {
            field = "kind",
            classify = {
                dirs = { "Inbox" },
            },
            rename = {
                require_preview = true,
                update_links = false,
                chunk_size = 2,
            },
            mapping = {
                person = { prefix = "person - " },
                software = { prefix = "software - " },
            },
        },
    })
    if taxonomy_opts then
        require("vault.config").options.taxonomy = vim.tbl_deep_extend(
            "force",
            require("vault.config").options.taxonomy,
            taxonomy_opts
        )
    end
end

local function clear_modules()
    package.loaded["vault.notes"] = nil
    package.loaded["vault.taxonomy"] = nil
    package.loaded["vault.config"] = nil
    package.loaded["vault"] = nil
    local state = require("vault.core.state")
    state.set_global_key("cache.notes.paths", nil)
    state.set_global_key("cache.notes.slugs", nil)
    state.set_global_key("notes", nil)
end

describe("vault.taxonomy", function()
    local taxonomy

    before_each(function()
        rm_rf(tmp_root)
        vim.fn.mkdir(tmp_root, "p")

        write(tmp_root .. "/Inbox/Gameloft.md", {
            "---",
            "kind: software",
            "---",
            "",
            "# Gameloft",
        })
        write(tmp_root .. "/Inbox/person - Dmytro Nechai.md", {
            "---",
            "kind: person",
            "---",
            "",
            "# Dmytro Nechai",
        })
        write(tmp_root .. "/Inbox/Foo.md", {
            "---",
            "kind: person",
            "---",
            "",
            "# Foo",
        })
        write(tmp_root .. "/Inbox/Conflict.md", {
            "---",
            "kind: software",
            "---",
            "",
            "# Conflict",
        })
        write(tmp_root .. "/Inbox/software - Conflict.md", {
            "---",
            "kind: software",
            "---",
            "",
            "# Conflict canonical",
        })
        write(tmp_root .. "/Inbox/Needs Kind.md", {
            "---",
            "categories:",
            "  - \"[[category - Notes]]\"",
            "---",
            "",
            "# Needs Kind",
        })
        write(tmp_root .. "/Reference/Outside Inbox.md", {
            "---",
            "categories:",
            "  - \"[[category - Notes]]\"",
            "---",
            "",
            "# Outside Inbox",
        })

        clear_modules()
        setup_vault()
        taxonomy = require("vault.taxonomy")
        rm_rf(taxonomy._preview_manifest_path())
        rm_rf(taxonomy._last_apply_manifest_path())
    end)

    after_each(function()
        rm_rf(taxonomy and taxonomy._preview_manifest_path() or "")
        rm_rf(taxonomy and taxonomy._last_apply_manifest_path() or "")
        rm_rf(tmp_root)
    end)

    it("collects only notes missing the taxonomy field for classify", function()
        local notes = taxonomy.classify_notes()
        assert.are.equal(1, notes:count())
        assert.is_not_nil(notes.map["Inbox/Needs Kind"])
    end)

    it("can classify across the whole vault when scope is disabled", function()
        local notes = taxonomy.classify_notes({ dirs = false })
        assert.are.equal(2, notes:count())
        assert.is_not_nil(notes.map["Inbox/Needs Kind"])
        assert.is_not_nil(notes.map["Reference/Outside Inbox"])
    end)

    it("builds a rename plan from taxonomy kind", function()
        local plan = taxonomy.build_plan()
        assert.are.equal(2, #plan.moves)
        assert.are.equal(1, #plan.skipped)

        local targets = {}
        for _, move in ipairs(plan.moves) do
            targets[move.to_slug] = true
        end

        assert.is_true(targets["Inbox/software - Gameloft"])
        assert.is_true(targets["Inbox/person - Foo"])
        assert.are.equal("target-exists", plan.skipped[1].reason)
    end)

    it("supports taxonomy from categories wikilinks", function()
        write(tmp_root .. "/Inbox/Category Driven.md", {
            "---",
            "categories:",
            "  - \"[[category - person]]\"",
            "  - \"[[category - Notes]]\"",
            "---",
            "",
            "# Category Driven",
        })

        clear_modules()
        setup_vault({
            field = "categories",
            reference_prefix = "category - ",
            classify = { dirs = { "Inbox" } },
        })
        taxonomy = require("vault.taxonomy")

        local plan = taxonomy.build_plan()
        local targets = {}
        for _, move in ipairs(plan.moves) do
            targets[move.to_slug] = true
        end
        assert.is_true(targets["Inbox/person - Category Driven"])

        local written = taxonomy.apply_choice_to_paths({ tmp_root .. "/Inbox/Needs Kind.md" }, "software")
        assert.are.equal(1, written)
        local lines = vim.fn.readfile(tmp_root .. "/Inbox/Needs Kind.md")
        assert.is_true(vim.tbl_contains(lines, "  - \"[[category - Notes]]\""))
        assert.is_true(vim.tbl_contains(lines, "  - \"[[category - software]]\""))
    end)

    it("applies and undoes taxonomy renames", function()
        local plan = taxonomy.preview()
        assert.are.equal(2, #plan.moves)

        local apply_report = taxonomy.apply()
        assert.is_not_nil(apply_report)
        assert.are.equal(2, apply_report.moved)
        assert.are.equal(1, vim.fn.filereadable(tmp_root .. "/Inbox/software - Gameloft.md"))
        assert.are.equal(1, vim.fn.filereadable(tmp_root .. "/Inbox/person - Foo.md"))
        assert.are.equal(0, vim.fn.filereadable(tmp_root .. "/Inbox/Gameloft.md"))
        assert.are.equal(0, vim.fn.filereadable(tmp_root .. "/Inbox/Foo.md"))

        local undo_report = taxonomy.undo_last()
        assert.is_not_nil(undo_report)
        assert.are.equal(2, undo_report.moved)
        assert.are.equal(1, vim.fn.filereadable(tmp_root .. "/Inbox/Gameloft.md"))
        assert.are.equal(1, vim.fn.filereadable(tmp_root .. "/Inbox/Foo.md"))
        assert.are.equal(0, vim.fn.filereadable(tmp_root .. "/Inbox/software - Gameloft.md"))
        assert.are.equal(0, vim.fn.filereadable(tmp_root .. "/Inbox/person - Foo.md"))
    end)
end)
