local config = require("vault.config")
local state = require("vault.core.state")

local tmp_root = vim.fn.getcwd() .. "/tests/tmp_merge_plan_vault"

local function reset_modules()
    package.loaded["vault.merge"] = nil
    package.loaded["vault.merge_biases"] = nil
end

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

describe("vault.merge.plan", function()
    before_each(function()
        rm_rf(tmp_root)
        vim.fn.mkdir(tmp_root, "p")

        config.setup({
            root = tmp_root,
            ext = ".md",
            features = { watcher = false },
            merge = {
                learned_conflict_biases = {
                    enabled = true,
                    path = tmp_root .. "/state/merge_conflict_biases.lua",
                },
            },
        })

        state.clear_all()
        reset_modules()
    end)

    after_each(function()
        rm_rf(tmp_root)
        state.clear_all()
        reset_modules()
    end)

    it("keeps loser-only metadata, ignores noisy timestamps, and flags real conflicts", function()
        write(tmp_root .. "/Inbox/a.md", {
            "---",
            "title: sample",
            "created: 20240101000000",
            "modified: 20240101000000",
            'assignee: "[[People/alice]]"',
            "tags:",
            "  - one",
            "---",
            "body",
        })
        write(tmp_root .. "/References/b.md", {
            "---",
            "title: sample",
            "created: 20240101000000",
            "modified: 20250101000000",
            "committed: 20250102000000",
            "stage: backlog",
            "score: 0",
            'assignee: "[[People/bob]]"',
            "tags:",
            "  - one",
            "  - two",
            "---",
            "body",
        })

        local merge = require("vault.merge")
        local plan = assert(merge.plan(tmp_root .. "/Inbox/a.md", tmp_root .. "/References/b.md", {
            body_strategy = "keep_target",
        }))

        assert.same({ "score", "stage" }, plan.added_fields)
        assert.same({ "tags" }, plan.extended_fields)
        assert.same({ "committed", "modified" }, plan.ignored_fields)
        assert.are.equal(1, #plan.conflicts)
        assert.are.equal("assignee", plan.conflicts[1].field)
        assert.are.equal("backlog", plan.merged_fields.stage)
        assert.are.equal("0", tostring(plan.merged_fields.score))
        assert.are.equal("keep_target", plan.body_strategy)
    end)

    it("builds merged lines without appending source body when keep_target is used", function()
        write(tmp_root .. "/Inbox/a.md", {
            "---",
            "title: sample",
            "---",
            "alpha",
        })
        write(tmp_root .. "/Inbox/b.md", {
            "---",
            "title: sample",
            "stage: backlog",
            "---",
            "alpha",
            "beta",
        })

        local merge = require("vault.merge")
        local plan = assert(merge.plan(tmp_root .. "/Inbox/a.md", tmp_root .. "/Inbox/b.md", {
            body_strategy = "keep_target",
        }))

        local merged = table.concat(plan.merged_lines, "\n")
        assert.is_truthy(merged:match("stage:%s*backlog"))
        assert.is_truthy(merged:match("\nalpha"))
        assert.is_nil(merged:match("merged from"))
        assert.is_nil(merged:match("\nbeta"))
    end)

    it("uses configurable field normalizers and ignored conflict fields", function()
        config.setup({
            root = tmp_root,
            ext = ".md",
            features = { watcher = false },
            merge = {
                ignored_conflict_fields = { "modified", "created" },
                field_normalizers = {
                    assignee = function(value)
                        return tostring(value):gsub(
                            "_Legacy/_docs/person/alex_example",
                            "Person %- Alex Example"
                        )
                    end,
                },
            },
        })
        reset_modules()

        write(tmp_root .. "/Inbox/a.md", {
            "---",
            'assignee: "[[Person - Alex Example]]"',
            "created: 20240101000000",
            "modified: 1",
            "---",
            "body",
        })
        write(tmp_root .. "/References/b.md", {
            "---",
            'assignee: "[[_Legacy/_docs/person/alex_example]]"',
            "created: 20240102000000",
            "modified: 2",
            "stage: backlog",
            "---",
            "body",
        })

        local merge = require("vault.merge")
        local plan = assert(merge.plan(tmp_root .. "/Inbox/a.md", tmp_root .. "/References/b.md", {
            body_strategy = "keep_target",
        }))

        assert.same({ "created", "modified" }, plan.ignored_fields)
        assert.are.equal(0, #plan.conflicts)
        assert.are.equal("backlog", plan.merged_fields.stage)
    end)

    it("uses configurable conflict biases for preselected conflict choices", function()
        config.setup({
            root = tmp_root,
            ext = ".md",
            features = { watcher = false },
            merge = {
                conflict_biases = {
                    created = "earliest",
                    published = "latest",
                    stage = function(conflict)
                        if conflict.val_b == "done" then
                            return "b"
                        end
                        return "a"
                    end,
                },
            },
        })
        reset_modules()

        local merge = require("vault.merge")

        assert.are.equal(
            "a",
            merge._default_conflict_choice({
                field = "created",
                val_a = "20240101000000",
                val_b = "20250101000000",
            })
        )
        assert.are.equal(
            "b",
            merge._default_conflict_choice({
                field = "created",
                val_a = "20250101000000",
                val_b = "20240101000000",
            })
        )
        assert.are.equal(
            "b",
            merge._default_conflict_choice({
                field = "published",
                val_a = "20240101000000",
                val_b = "20250101000000",
            })
        )
        assert.are.equal(
            "b",
            merge._default_conflict_choice({
                field = "stage",
                val_a = "todo",
                val_b = "done",
            })
        )
        assert.are.equal(
            "a",
            merge._default_conflict_choice({
                field = "assignee",
                val_a = "alice",
                val_b = "bob",
            })
        )
    end)

    it("remembers learned conflict biases for future prompts", function()
        local merge = require("vault.merge")
        local store = require("vault.merge_biases")

        assert.is_nil(store.get("stage"))
        assert.are.equal(
            "a",
            merge._default_conflict_choice({
                field = "stage",
                val_a = "todo",
                val_b = "done",
            })
        )
        assert.is_nil(store.get("stage"))

        merge._remember_conflict_choices({
            {
                field = "stage",
                val_a = "todo",
                val_b = "done",
            },
            {
                field = "published",
                val_a = "20240101000000",
                val_b = "20250101000000",
            },
        }, { "b", "a" })

        assert.are.equal("b", store.get("stage"))
        assert.are.equal("earliest", store.get("published"))
        assert.are.equal(
            "b",
            merge._default_conflict_choice({
                field = "stage",
                val_a = "todo",
                val_b = "done",
            })
        )
        assert.are.equal(
            "a",
            merge._default_conflict_choice({
                field = "published",
                val_a = "20240101000000",
                val_b = "20250101000000",
            })
        )

        local resolved, unresolved = merge.resolve_conflicts_with_biases({
            {
                field = "stage",
                val_a = "todo",
                val_b = "done",
            },
            {
                field = "published",
                val_a = "20240101000000",
                val_b = "20250101000000",
            },
            {
                field = "assignee",
                val_a = "alice",
                val_b = "bob",
            },
        })
        assert.same({ published = "20240101000000", stage = "done" }, resolved)
        assert.are.equal(1, #unresolved)
        assert.are.equal("assignee", unresolved[1].field)
    end)

    it("can keep configured and learned biases as preselect-only", function()
        config.setup({
            root = tmp_root,
            ext = ".md",
            features = { watcher = false },
            merge = {
                conflict_biases = {
                    created = "earliest",
                },
                conflict_bias_behavior = "preselect",
                learned_conflict_biases = {
                    enabled = true,
                    path = tmp_root .. "/state/merge_conflict_biases.lua",
                    behavior = "preselect",
                },
            },
        })
        reset_modules()

        local merge = require("vault.merge")
        local store = require("vault.merge_biases")
        store.remember("project", "b")

        assert.are.equal(
            "a",
            merge._default_conflict_choice({
                field = "created",
                val_a = "20240101000000",
                val_b = "20250101000000",
            })
        )
        assert.are.equal(
            "b",
            merge._default_conflict_choice({
                field = "project",
                val_a = "alpha",
                val_b = "beta",
            })
        )

        local resolved, unresolved = merge.resolve_conflicts_with_biases({
            {
                field = "created",
                val_a = "20240101000000",
                val_b = "20250101000000",
            },
            {
                field = "project",
                val_a = "alpha",
                val_b = "beta",
            },
        })
        assert.same({}, resolved)
        assert.are.equal(2, #unresolved)
        assert.are.equal("created", unresolved[1].field)
        assert.are.equal("project", unresolved[2].field)
    end)
end)
