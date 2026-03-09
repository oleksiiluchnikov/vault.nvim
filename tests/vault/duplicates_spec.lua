local config = require("vault.config")
local state = require("vault.core.state")

local tmp_root = vim.fn.getcwd() .. "/tests/tmp_duplicates_vault"

local function reset_modules()
    package.loaded["vault.duplicates"] = nil
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

describe("vault.duplicates.scan", function()
    before_each(function()
        rm_rf(tmp_root)
        vim.fn.mkdir(tmp_root, "p")

        write(tmp_root .. "/Inbox/Build Keyboard Centric Software Environment.md", {
            "---",
            "title: Build Keyboard Centric Software Environment",
            "created: 20240101000000",
            "---",
            "# Build Keyboard Centric Software Environment",
            "I want keyboard centric software.",
        })
        write(tmp_root .. "/References/Build Keyboard Centric Software Environment 1.md", {
            "---",
            "title: Build Keyboard Centric Software Environment 1",
            "created: 20250101000000",
            "score: 0",
            "---",
            "# Build Keyboard Centric Software Environment 1",
            "I want keyboard centric software.",
            "And I want less mouse use.",
        })
        write(tmp_root .. "/Research/Build Keyboard Centric Software Setup.md", {
            "---",
            "title: Build Keyboard Centric Software Setup",
            "tags:",
            "  - dev",
            "---",
            "# Build Keyboard Centric Software Setup",
            "I want keyboard centric software.",
            "And I want faster editing.",
        })

        write(tmp_root .. "/Daily/2024-01-01 Monday.md", {
            "---",
            "title: 2024-01-01 Monday",
            "created: 20240101000000",
            "---",
            "# 2024-01-01 Monday",
            "alpha",
        })
        write(tmp_root .. "/Daily/2024-01-01 Monday 1.md", {
            "---",
            "title: 2024-01-01 Monday 1",
            "created: 20250101000000",
            "---",
            "# 2024-01-01 Monday 1",
            "alpha",
        })

        config.setup({
            root = tmp_root,
            ext = ".md",
            features = { watcher = false, commands = true },
        })

        state.clear_all()
        reset_modules()
    end)

    after_each(function()
        rm_rf(tmp_root)
        state.clear_all()
        reset_modules()
    end)

    it("finds same-name duplicates across directories and suffix copies", function()
        local duplicates = require("vault.duplicates")
        local items = duplicates.scan("vault")

        assert.are.equal(2, #items)
        assert.are.equal("metadata", items[1].kind)
        assert.are.equal("Daily/2024-01-01 Monday.md", items[1].a_rel)
        assert.are.equal("a_subset", items[2].kind)
        assert.are.equal("Inbox/Build Keyboard Centric Software Environment.md", items[2].a_rel)
        assert.are.equal(
            "References/Build Keyboard Centric Software Environment 1.md",
            items[2].b_rel
        )
    end)

    it("uses configured preferred directory order for recommendations", function()
        config.setup({
            root = tmp_root,
            ext = ".md",
            features = { watcher = false, commands = true },
            duplicates = {
                preferred_dirs = { "References", "Inbox", "Daily" },
            },
        })
        reset_modules()

        local duplicates = require("vault.duplicates")
        local items = duplicates.scan("vault")

        assert.are.equal("b", items[2].recommended)
        assert.are.equal("B is in the preferred folder", items[2].recommended_reason)
    end)

    it("can scan from a precomputed path index", function()
        local duplicates = require("vault.duplicates")
        local items = duplicates.scan("vault", {
            one = { path = tmp_root .. "/Inbox/Build Keyboard Centric Software Environment.md" },
            two = {
                path = tmp_root .. "/References/Build Keyboard Centric Software Environment 1.md",
            },
            three = { path = tmp_root .. "/Daily/2024-01-01 Monday.md" },
            four = { path = tmp_root .. "/Daily/2024-01-01 Monday 1.md" },
        })

        assert.are.equal(2, #items)
        assert.are.equal("metadata", items[1].kind)
        assert.are.equal("a_subset", items[2].kind)
    end)

    it("reuses cached file analysis for repeated pair evaluation", function()
        local duplicates = require("vault.duplicates")
        local cache = {}
        local path = tmp_root .. "/Inbox/Build Keyboard Centric Software Environment.md"

        local first = duplicates._analyze_file(path, cache)
        local second = duplicates._analyze_file(path, cache)

        assert.is_not_nil(first)
        assert.is_true(first == second)
        assert.are.equal(1, vim.tbl_count(cache))
    end)

    it("can filter duplicate review sets by kind aliases", function()
        local duplicates = require("vault.duplicates")
        local kinds = assert(duplicates.resolve_kind_filter({ "metadata", "body" }))
        local items = duplicates.scan("vault", nil, { kinds = kinds })

        assert.are.equal(2, #items)
        assert.are.equal("metadata", items[1].kind)
        assert.are.equal("a_subset", items[2].kind)
    end)

    it("can filter duplicate review sets by allowed paths while keeping cross-dir pairs", function()
        local duplicates = require("vault.duplicates")
        local items = duplicates.scan("vault", nil, {
            allowed_paths = {
                [tmp_root .. "/Inbox/Build Keyboard Centric Software Environment.md"] = true,
            },
        })

        assert.are.equal(1, #items)
        assert.are.equal("Inbox/Build Keyboard Centric Software Environment.md", items[1].a_rel)
        assert.are.equal(
            "References/Build Keyboard Centric Software Environment 1.md",
            items[1].b_rel
        )
    end)

    it("treats different path filter groups as pair-level AND", function()
        local duplicates = require("vault.duplicates")
        local items = duplicates.scan("vault", nil, {
            path_filters = {
                dirs = {
                    [tmp_root .. "/Inbox/Build Keyboard Centric Software Environment.md"] = true,
                },
                tags = {
                    [tmp_root .. "/References/Build Keyboard Centric Software Environment 1.md"] = true,
                },
            },
        })

        assert.are.equal(1, #items)
        assert.are.equal("a_subset", items[1].kind)
    end)

    it("finds related duplicate candidates with Rust-backed scoring", function()
        local duplicates = require("vault.duplicates")
        local buckets = assert(duplicates.resolve_related_filter({ "all" }))
        local items = duplicates.scan_related("vault", nil, { related_buckets = buckets })

        assert.is_true(#items >= 1)

        local found = false
        for _, item in ipairs(items) do
            if
                item.a_rel == "Inbox/Build Keyboard Centric Software Environment.md"
                and item.b_rel == "Research/Build Keyboard Centric Software Setup.md"
            then
                found = true
                assert.is_not_nil(item.related_bucket)
                assert.is_true((item.related_slug_sim or 0) >= 0.7)
                break
            end
        end

        assert.is_true(found)
    end)
end)
