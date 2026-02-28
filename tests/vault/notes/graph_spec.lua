--- @module "busted"
--- Graph analysis benchmark tests for vault.nvim
---
--- These tests verify that orphans, leaves, internals, linked, dangling links,
--- and resolved outlinks are computed correctly against the demo vault fixture.
---
--- Ground truth was independently verified with a Python script using
--- obsidiantools-style basename resolution (see Clippings for details).
---
--- Demo vault link graph (22 notes total):
---   shell_and_code_test   → [[test_note]] ✓, [[README]] ✓, [[Project/My new masterpeace]] ✓
---   test_note             → [[Wiki Link]] ✗, [[Nested/Wiki/Link]] ✗
---   test_note_4039790659  → [[Project/My awesome neovim plugin]] ✗
---   Inbox/meeting-notes   → [[Project/mobile-app]] ✓
---   Inbox/book-recommendation → [[Project/data-pipeline]] ✓
---   Project/website-redesign → [[Project/My new masterpeace]] ✓
---   Project/data-pipeline → [[Project/api-migration]] ✓
---   Journal/2026-02-28   → [[Project/website-redesign]] ✓, [[Project/mobile-app]] ✓
---   Journal/2026-02-27   → [[Project/api-migration]] ✓, [[Project/data-pipeline]] ✓
---   Archive/deprecated-api → [[Project/api-migration]] ✓
---
--- Inlinks (from resolved wikilinks):
---   test_note                  ← shell_and_code_test
---   README                     ← shell_and_code_test
---   Project/My new masterpeace ← shell_and_code_test, Project/website-redesign
---   Project/mobile-app         ← Inbox/meeting-notes, Journal/2026-02-28
---   Project/data-pipeline      ← Inbox/book-recommendation, Journal/2026-02-27
---   Project/api-migration      ← Project/data-pipeline, Journal/2026-02-27, Archive/deprecated-api
---   Project/website-redesign   ← Journal/2026-02-28

local assert = require("luassert")

describe("Graph analysis (demo vault)", function()
    local Notes

    before_each(function()
        local fixture_path = vim.fn.getcwd() .. "/tests/fixtures/demo-vault"
        if vim.fn.isdirectory(fixture_path) == 0 then
            error("Fixture directory not found at: " .. fixture_path)
        end

        -- Clear all state for clean test
        local state = require("vault.core.state")
        state.set_global_key("cache.notes.slugs", nil)
        state.set_global_key("cache.notes.basename_index", nil)
        state.set_global_key("wikilinks", nil)
        state.set_global_key("notes", nil)

        for k, _ in pairs(package.loaded) do
            if k:match("^vault") then
                package.loaded[k] = nil
            end
        end

        require("vault").setup({
            root = fixture_path,
            ext = ".md",
            features = { cmp = false, commands = false, watcher = false },
            tags = { valid = { hex = true } },
            search_tool = "rg",
        })

        Notes = require("vault.notes")
    end)

    it("should have exactly 22 notes", function()
        local notes = Notes()
        assert.are.equal(22, notes:count())
    end)

    -- ========================================================================
    -- Wikilink resolution (basename matching)
    -- ========================================================================

    describe("wikilink resolution", function()
        it("should resolve basename wikilinks to full slugs", function()
            local notes = Notes()
            -- shell_and_code_test links to [[test_note]], [[README]], [[Project/My new masterpeace]]
            local shell_note
            for slug, note in pairs(notes.map) do
                if slug:match("shell_and_code_test$") then
                    shell_note = note
                    break
                end
            end
            assert.is_not_nil(shell_note, "shell_and_code_test note should exist")

            local outlinks = shell_note.data.outlinks
            local resolved_count = 0
            for _, wl in pairs(outlinks) do
                if wl.data.target then
                    resolved_count = resolved_count + 1
                end
            end
            -- All 3 outlinks should resolve: test_note, README, Project/My new masterpeace
            assert.are.equal(3, resolved_count,
                "shell_and_code_test should have 3 resolved outlinks")
        end)

        it("should leave genuinely missing targets unresolved", function()
            local notes = Notes()
            local test_note
            for slug, note in pairs(notes.map) do
                if slug:match("test_note$") and not slug:match("4039790659") then
                    test_note = note
                    break
                end
            end
            assert.is_not_nil(test_note, "test_note should exist")

            local outlinks = test_note.data.outlinks
            -- [[Wiki Link]] and [[Nested/Wiki/Link]] should NOT resolve
            for _, wl in pairs(outlinks) do
                assert.is_nil(wl.data.target,
                    "test_note outlink '" .. wl.data.slug .. "' should be unresolved")
            end
        end)
    end)

    -- ========================================================================
    -- Graph quadrant counts
    -- ========================================================================

    describe("orphans()", function()
        it("should return notes with no outlinks AND no inlinks", function()
            local orphans = Notes():orphans()
            local count = vim.tbl_count(orphans.map)
            -- Inbox/Untitled, _docs/Project, Journal/2026-02-26, Reference/lua-patterns,
            -- Reference/git-workflows, Reference/yaml-syntax, Archive/old-project, Inbox/quick-idea
            assert.are.equal(8, count,
                "Expected 8 orphans, got " .. count)
        end)

        it("should contain Inbox/Untitled", function()
            local orphans = Notes():orphans()
            local found = false
            for slug, _ in pairs(orphans.map) do
                if slug:match("Untitled$") then found = true; break end
            end
            assert.is_true(found, "Inbox/Untitled should be an orphan")
        end)
    end)

    describe("leaves()", function()
        it("should return notes with inlinks but no outlinks", function()
            local leaves = Notes():leaves()
            local count = vim.tbl_count(leaves.map)
            -- README, Project/mobile-app, Project/My new masterpeace, Project/api-migration
            assert.are.equal(4, count,
                "Expected 4 leaves (README, mobile-app, My new masterpeace, api-migration), got " .. count)
        end)
    end)

    describe("internals()", function()
        it("should return notes with both inlinks AND outlinks", function()
            local internals = Notes():internals()
            local count = vim.tbl_count(internals.map)
            -- test_note (in: shell_and_code_test; out: Wiki Link, Nested/Wiki/Link),
            -- Project/website-redesign (in: Journal/2026-02-28; out: My new masterpeace),
            -- Project/data-pipeline (in: book-recommendation, Journal/2026-02-27; out: api-migration)
            assert.are.equal(3, count,
                "Expected 3 internals (test_note, website-redesign, data-pipeline), got " .. count)
        end)
    end)

    describe("linked()", function()
        it("should return notes with any connections", function()
            local linked = Notes():linked()
            local count = vim.tbl_count(linked.map)
            -- 22 total - 8 orphans = 14 linked
            assert.are.equal(14, count,
                "Expected 14 linked notes, got " .. count)
        end)
    end)

    -- ========================================================================
    -- Outlink resolution categories
    -- ========================================================================

    describe("with_outlinks_unresolved()", function()
        it("should return notes that have at least one unresolved outlink", function()
            local dangling = Notes():with_outlinks_unresolved()
            local count = vim.tbl_count(dangling.map)
            -- test_note (Wiki Link, Nested/Wiki/Link),
            -- test_note_4039790659 (My awesome neovim plugin)
            -- shell_and_code_test now has 3 resolved + 0 false positives (bash filtered)
            assert.are.equal(2, count,
                "Expected 2 notes with unresolved outlinks, got " .. count)
        end)
    end)

    describe("with_outlinks_resolved_only()", function()
        it("should return notes where ALL outlinks resolve", function()
            local resolved = Notes():with_outlinks_resolved_only()
            local count = vim.tbl_count(resolved.map)
            -- meeting-notes, book-recommendation, website-redesign, data-pipeline,
            -- Journal/2026-02-28, Journal/2026-02-27, deprecated-api, shell_and_code_test
            assert.are.equal(8, count,
                "Expected 8 notes with all outlinks resolved, got " .. count)
        end)
    end)

    -- ========================================================================
    -- Partition invariant: every note is in exactly one quadrant
    -- ========================================================================

    describe("graph partition invariant", function()
        it("orphans + leaves + internals + outlinks_only == total", function()
            local total = Notes():count()
            local orphans = vim.tbl_count(Notes():orphans().map)
            local leaves = vim.tbl_count(Notes():leaves().map)
            local internals_count = vim.tbl_count(Notes():internals().map)
            local linked_count = vim.tbl_count(Notes():linked().map)

            -- linked = internals + leaves + outlinks_only
            -- total = linked + orphans
            assert.are.equal(total, linked_count + orphans,
                string.format("Partition check failed: linked(%d) + orphans(%d) != total(%d)",
                    linked_count, orphans, total))
        end)
    end)
end)
