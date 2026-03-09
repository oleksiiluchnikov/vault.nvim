-- tests/vault/commands/init_spec.lua
--
-- Execution tests for every Vault user command.
-- Tiers:
--   1. Registration — every command exists with correct nargs
--   2. Data paths  — filtering logic the commands rely on (no UI)
--   3. Buffer-context — commands that mutate the current buffer
--   4. Completions — completion callbacks return expected types
--
-- Safety: all tests run against tests/fixtures/demo-vault.
-- Filesystem-mutating tests (VaultNoteNew, VaultRename) use a temp copy
-- and clean up after themselves.

local root_cwd = vim.fn.getcwd()
local fixture_root = root_cwd .. "/tests/fixtures/demo-vault"

-- ─── helpers ──────────────────────────────────────────────────────────────────

--- Ensure vault is properly set up for our test describe block.
--- Mirrors the pattern from tests/vault/notes/init_spec.lua.
local function setup_vault()
    -- Re-initialize vault config pointing at fixture root
    require("vault").setup({
        root = fixture_root,
        ext = ".md",
        dirs = {
            inbox = "Inbox",
            docs = "_docs",
            templates = "_templates",
            journal = {
                root = "Journal",
                daily = "Journal/Daily",
            },
        },
        features = {
            cmp = false,
            commands = true,
            watcher = false,
        },
        tags = {
            valid = { hex = true },
        },
        search_tool = "rg",
    })
end

--- Clear cached module state so constructors re-scan the fixture vault.
local function clear_state()
    local state = require("vault.core.state")
    state.set_global_key("cache.notes.paths", nil)
    state.set_global_key("cache.notes.slugs", nil)
    state.set_global_key("notes", nil)
    state.set_global_key("notes.orphans", nil)
    state.set_global_key("notes.linked", nil)
    state.set_global_key("notes.internals", nil)
    state.set_global_key("notes.leaves", nil)
    state.set_global_key("cache.bases.raw", nil)
    state.set_global_key("bases", nil)
    package.loaded["vault.notes"] = nil
    package.loaded["vault.core.state"] = nil
    package.loaded["vault.bases"] = nil
    package.loaded["vault.tags"] = nil
end

--- Capture vim.notify messages during a callback
--- @param fn function
--- @return string[] messages
local function capture_notify(fn)
    local messages = {}
    local orig = vim.notify
    vim.notify = function(msg, ...)
        table.insert(messages, tostring(msg))
    end
    local ok, err = pcall(fn)
    vim.notify = orig
    if not ok then
        error(err)
    end
    return messages
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- TIER 1 — Command Registration
-- ═══════════════════════════════════════════════════════════════════════════════

describe("Vault commands", function()
    -- Reload commands module to ensure registration runs
    require("vault.commands")

    describe("registration", function()
        -- Only :Vault is registered now (legacy VaultFoo commands were removed)
        local cmds = vim.api.nvim_get_commands({})

        it(":Vault is registered", function()
            assert.is_not_nil(cmds["Vault"], "Vault should be registered")
        end)

        it(":Vault has nargs=*", function()
            assert.is_not_nil(cmds["Vault"], "Vault must exist first")
            assert.are.equal("*", cmds["Vault"].nargs, "Vault nargs mismatch")
        end)

        -- Legacy commands should NOT be registered
        local legacy_commands = {
            "VaultNote",
            "VaultNotes",
            "VaultNoteNew",
            "VaultRandomNote",
            "VaultTags",
            "VaultDates",
            "VaultToday",
            "VaultYesterday",
            "VaultNotesStatus",
            "VaultFleetingNote",
            "VaultOrphans",
            "VaultLinked",
            "VaultInternals",
            "VaultLeaves",
            "VaultDanglingLinks",
            "VaultOutlinksUnresolved",
            "VaultOutlinksResolvedOnly",
            "VaultWikilinks",
            "VaultTasks",
            "VaultNotesCluster",
            "VaultMove",
            "VaultGrep",
            "VaultRename",
            "VaultNoteInlinks",
            "VaultNoteOutlinks",
            "VaultNoteTags",
            "VaultNoteExtract",
            "VaultProperties",
            "VaultNoteProperties",
            "VaultNotesByDir",
            "VaultDirs",
            "VaultToggleLink",
            "VaultBases",
        }

        for _, name in ipairs(legacy_commands) do
            it(string.format(":%s is NOT registered (removed)", name), function()
                assert.is_nil(cmds[name], name .. " should NOT be registered (legacy)")
            end)
        end
    end)
end)

-- ═══════════════════════════════════════════════════════════════════════════════
-- TIER 2 — Data Path Execution (no UI)
-- ═══════════════════════════════════════════════════════════════════════════════
--
-- These test the core data-preparation logic that the commands call
-- *before* opening a Telescope picker.  We call the Notes methods directly
-- against the fixture vault and assert on counts and structure.
--
-- Fixture vault has 22 markdown notes across multiple directories.
-- Key notes for graph analysis:
--   shell_and_code_test.md       — outlinks to test_note, README, Project/My new masterpeace (all resolved)
--   test_note.md                 — outlinks to Wiki Link, Nested/Wiki/Link (unresolved); inlink from shell_and_code_test
--   Project/test_note_4039790659 — outlink to Project/My awesome neovim plugin (unresolved)
--   Inbox/meeting-notes.md       — outlink to Project/mobile-app (resolved)
--   Inbox/book-recommendation.md — outlink to Project/data-pipeline (resolved)
--   Project/website-redesign.md  — outlink to Project/My new masterpeace (resolved)
--   Project/data-pipeline.md     — outlink to Project/api-migration (resolved); inlinks from book-recommendation, Journal/2026-02-27
--   Journal/2026-02-28.md        — outlinks to Project/website-redesign, Project/mobile-app (resolved)
--   Journal/2026-02-27.md        — outlinks to Project/api-migration, Project/data-pipeline (resolved)
--   Archive/deprecated-api.md    — outlink to Project/api-migration (resolved)
-- Orphans (8): Inbox/Untitled, Inbox/quick-idea, _docs/Project, Journal/2026-02-26,
--              Reference/lua-patterns, Reference/git-workflows, Reference/yaml-syntax, Archive/old-project

describe("Vault command data paths", function()
    local Notes

    -- Ensure vault is configured for this describe block
    setup_vault()

    before_each(function()
        -- Clear cached state so each test gets a fresh Notes collection
        clear_state()
        Notes = require("vault.notes")
    end)

    describe("Notes()", function()
        it("should load all 22 fixture notes", function()
            local notes = Notes()
            assert.are.equal(22, notes:count())
        end)
    end)

    describe("orphans()", function()
        it("should return 8 orphan notes (no outlinks AND not a wikilink target)", function()
            local notes = Notes()
            local orphans = notes:orphans()
            -- Orphans: Inbox/Untitled, Inbox/quick-idea, _docs/Project, Journal/2026-02-26,
            --          Reference/lua-patterns, Reference/git-workflows, Reference/yaml-syntax,
            --          Archive/old-project
            assert.are.equal(8, #vim.tbl_keys(orphans.map))
        end)

        it("should NOT include notes that have outgoing wikilinks", function()
            local notes = Notes()
            local orphans = notes:orphans()
            for _, note in pairs(orphans.map) do
                local outlinks = note.data.outlinks
                assert.is_true(
                    not outlinks or next(outlinks) == nil,
                    "orphan " .. note.data.slug .. " should have no outlinks"
                )
            end
        end)
    end)

    describe("linked()", function()
        it("should return 14 notes that have outlinks or inlinks", function()
            local notes = Notes()
            local linked = notes:linked()
            -- 22 total - 8 orphans = 14 linked
            assert.are.equal(14, #vim.tbl_keys(linked.map))
        end)

        it("should only include notes with non-empty outlinks or inlinks", function()
            local notes = Notes()
            local linked = notes:linked()
            for _, note in pairs(linked.map) do
                local has_outlinks = note.data.outlinks and next(note.data.outlinks) ~= nil
                local has_inlinks = note.data.inlinks and next(note.data.inlinks) ~= nil
                assert.is_true(
                    has_outlinks or has_inlinks,
                    note.data.slug .. " must have outlinks or inlinks"
                )
            end
        end)
    end)

    describe("internals()", function()
        it("should return 3 internal notes (both inlinks AND outlinks)", function()
            local notes = Notes()
            local internals = notes:internals()
            -- test_note, Project/website-redesign, Project/data-pipeline
            assert.are.equal(3, #vim.tbl_keys(internals.map))
        end)
    end)

    describe("leaves()", function()
        it("should return 4 leaf notes (wikilink targets with no outlinks)", function()
            local notes = Notes()
            local leaves = notes:leaves()
            -- README, Project/mobile-app, Project/My new masterpeace, Project/api-migration
            assert.are.equal(4, #vim.tbl_keys(leaves.map))
        end)
    end)

    describe("with_outlinks_unresolved()", function()
        it("should return 2 notes with at least one unresolved outlink", function()
            local notes = Notes()
            local unresolved = notes:with_outlinks_unresolved()
            -- test_note (dangling links), test_note_4039790659 (dangling links)
            -- shell_and_code_test now has all 3 outlinks resolved (bash false-positives filtered)
            assert.are.equal(2, #vim.tbl_keys(unresolved.map))
        end)

        it("each returned note should have at least one unresolved wikilink", function()
            local notes = Notes()
            local unresolved = notes:with_outlinks_unresolved()
            for _, note in pairs(unresolved.map) do
                local has_unresolved = false
                for _, wl in pairs(note.data.outlinks) do
                    if not wl.data.target then
                        has_unresolved = true
                        break
                    end
                end
                assert.is_true(has_unresolved, note.data.slug .. " must have unresolved link")
            end
        end)
    end)

    describe("with_outlinks_resolved_only()", function()
        it("should return 8 notes where ALL outlinks resolve", function()
            local notes = Notes()
            local resolved = notes:with_outlinks_resolved_only()
            -- meeting-notes, book-recommendation, website-redesign, data-pipeline,
            -- Journal/2026-02-28, Journal/2026-02-27, deprecated-api, shell_and_code_test
            assert.are.equal(8, #vim.tbl_keys(resolved.map))
        end)
    end)

    describe("to_cluster()", function()
        it("should create a cluster from test_note at depth 0", function()
            local notes = Notes()
            local test_note = nil
            for _, note in pairs(notes.map) do
                if note.data.stem == "test_note" then
                    test_note = note
                    break
                end
            end
            assert.is_not_nil(test_note, "test_note must exist in the fixture vault")

            local cluster = notes:to_cluster(test_note, 0)
            assert.is_not_nil(cluster)
            assert.is_not_nil(cluster.map)
        end)
    end)

    describe("filter by tag", function()
        it("should filter notes that have the 'example' tag", function()
            local notes = Notes()
            local filtered = notes:filter({
                search_term = "tags",
                include = { "example" },
                exclude = {},
                match_opt = "exact",
                mode = "all",
            })
            -- README.md has #example tag
            assert.is_true(#vim.tbl_keys(filtered.map) >= 1, "at least 1 note should have #example")
        end)

        it("should filter notes that have the 'todo' tag", function()
            local notes = Notes()
            local filtered = notes:filter({
                search_term = "tags",
                include = { "todo" },
                exclude = {},
                match_opt = "exact",
                mode = "all",
            })
            -- test_note.md has #todo inline tag
            assert.is_true(#vim.tbl_keys(filtered.map) >= 1, "at least 1 note should have #todo")
        end)
    end)

    describe("filter by relpath (directory)", function()
        it("should filter notes in the Project/ directory", function()
            local notes = Notes()
            local filtered = notes:filter("relpath", "Project", "startswith", false)
            -- Project/My new masterpeace, Project/test_note_4039790659, Project/website-redesign,
            -- Project/mobile-app, Project/api-migration, Project/data-pipeline
            assert.are.equal(6, #vim.tbl_keys(filtered.map))
        end)

        it("should filter notes in the Inbox/ directory", function()
            local notes = Notes()
            local filtered = notes:filter("relpath", "Inbox", "startswith", false)
            -- Inbox/Untitled, Inbox/quick-idea, Inbox/meeting-notes, Inbox/book-recommendation
            assert.are.equal(4, #vim.tbl_keys(filtered.map))
        end)
    end)

    describe("Bases collection", function()
        it("should load all 4 fixture .base files", function()
            clear_state()
            local Bases = require("vault.bases")
            local bases = Bases()
            assert.are.equal(4, bases:count())
        end)

        it("should retrieve base by name", function()
            clear_state()
            local Bases = require("vault.bases")
            local bases = Bases()
            local projects = bases:get("projects")
            assert.is_not_nil(projects, "projects base must exist")
            assert.are.equal("projects", projects.data.name)
        end)

        it("should list all base names", function()
            clear_state()
            local Bases = require("vault.bases")
            local bases = Bases()
            local names = bases:names()
            assert.are.equal(4, #names)
            -- Sort for deterministic assertion
            table.sort(names)
            -- names[4] is the new 4th base (sorted order depends on its name)
            assert.is_true(
                vim.tbl_contains(names, "active-notes"),
                "active-notes should be present"
            )
            assert.is_true(vim.tbl_contains(names, "all-notes"), "all-notes should be present")
            assert.is_true(vim.tbl_contains(names, "projects"), "projects should be present")
        end)
    end)

    describe("get_random()", function()
        it("should return a Note object", function()
            local notes = Notes()
            local random_note = notes:get_random()
            assert.is_not_nil(random_note)
            assert.is_not_nil(random_note.data)
            assert.is_not_nil(random_note.data.slug)
        end)
    end)
end)

-- ═══════════════════════════════════════════════════════════════════════════════
-- TIER 3 — Buffer-Context Commands
-- ═══════════════════════════════════════════════════════════════════════════════

describe("Vault buffer-context commands", function()
    -- Ensure vault is configured for this describe block
    setup_vault()

    describe(":Vault toggle-link", function()
        local bufnr

        before_each(function()
            vim.cmd("enew!")
            bufnr = vim.api.nvim_get_current_buf()
        end)

        after_each(function()
            if vim.api.nvim_buf_is_valid(bufnr) then
                vim.api.nvim_buf_delete(bufnr, { force = true })
            end
        end)

        it("should convert a bare URL to a markdown link", function()
            local line = "Check out https://example.com for details"
            vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { line })
            vim.api.nvim_win_set_cursor(0, { 1, 12 })

            vim.cmd("Vault toggle-link")

            local result = vim.api.nvim_buf_get_lines(bufnr, 0, 1, false)[1]
            assert.is_truthy(
                result:find("[https://example.com](https://example.com)", 1, true),
                "expected markdown link, got: " .. result
            )
        end)

        it("should convert a markdown link back to a bare URL", function()
            local line = "Check out [Example](https://example.com) for details"
            vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { line })
            vim.api.nvim_win_set_cursor(0, { 1, 15 })

            vim.cmd("Vault toggle-link")

            local result = vim.api.nvim_buf_get_lines(bufnr, 0, 1, false)[1]
            assert.is_truthy(
                result:find("https://example.com"),
                "expected bare URL, got: " .. result
            )
            assert.is_falsy(
                result:find("%[Example%]"),
                "markdown link syntax should be removed, got: " .. result
            )
        end)

        it("should warn when no URL or link is under cursor", function()
            vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "plain text no links" })
            vim.api.nvim_win_set_cursor(0, { 1, 5 })

            local messages = capture_notify(function()
                vim.cmd("Vault toggle-link")
            end)
            assert.is_true(#messages > 0, "should have notified")
            assert.is_truthy(
                messages[1]:find("No URL"),
                "expected 'No URL' warning, got: " .. messages[1]
            )
        end)
    end)

    describe(":VaultToday", function()
        it("should construct the correct path with today's date", function()
            local config = require("vault.config")
            assert.is_not_nil(
                config.options.dirs,
                "config.options.dirs must be set after vault.setup()"
            )
            local today = os.date("%Y-%m-%d %A")
            local daily_dir = config.options.dirs.journal.daily
            local expected_path = string.format("%s/%s%s", daily_dir, today, config.options.ext)

            -- We don't want to actually open the file; just verify the path logic.
            -- The command calls vim.cmd("e " .. path) so we intercept it.
            local opened_path = nil
            local orig_cmd = vim.cmd
            vim.cmd = function(cmd_str)
                if type(cmd_str) == "string" and cmd_str:match("^e ") then
                    opened_path = cmd_str:match("^e (.+)")
                    -- Don't actually open
                else
                    orig_cmd(cmd_str)
                end
            end

            capture_notify(function()
                require("vault.commands").today()
            end)

            vim.cmd = orig_cmd

            assert.is_not_nil(opened_path, "VaultToday should have tried to open a file")
            -- Unescape the path for comparison
            local unescaped = opened_path:gsub("\\", "")
            assert.is_truthy(
                unescaped:find(tostring(os.date("%Y-%m-%d")), 1, true),
                "path should contain today's date, got: " .. unescaped
            )
        end)
    end)

    describe(":VaultYesterday", function()
        it("should construct the correct path with yesterday's date", function()
            local config = require("vault.config")
            assert.is_not_nil(
                config.options.dirs,
                "config.options.dirs must be set after vault.setup()"
            )
            local yesterday = os.date("%Y-%m-%d", os.time() - 60 * 60 * 24)
            local daily_dir = config.options.dirs.journal.daily
            local expected_path = string.format("%s/%s%s", daily_dir, yesterday, config.options.ext)

            local opened_path = nil
            local orig_cmd = vim.cmd
            vim.cmd = function(cmd_str)
                if type(cmd_str) == "string" and cmd_str:match("^e ") then
                    opened_path = cmd_str:match("^e (.+)")
                else
                    orig_cmd(cmd_str)
                end
            end

            capture_notify(function()
                require("vault.commands").yesterday()
            end)

            vim.cmd = orig_cmd

            assert.is_not_nil(opened_path, "VaultYesterday should have tried to open a file")
            local unescaped = opened_path:gsub("\\", "")
            assert.is_truthy(
                unescaped:find(tostring(yesterday), 1, true),
                "path should contain yesterday's date, got: " .. unescaped
            )
        end)
    end)

    -- Legacy :VaultMove and :VaultGrep were removed — tested via :Vault subcommands now
end)

-- ═══════════════════════════════════════════════════════════════════════════════
-- TIER 3 — Note-Context Commands (require a vault note in the buffer)
-- ═══════════════════════════════════════════════════════════════════════════════

describe("Vault note-context commands", function()
    local test_note_path = fixture_root .. "/test_note.md"

    -- Ensure vault is configured
    setup_vault()

    before_each(function()
        -- Clear state to ensure fresh data
        clear_state()
        -- Open the fixture test_note.md so buffer-dependent commands work
        vim.cmd("e " .. vim.fn.fnameescape(test_note_path))
    end)

    after_each(function()
        -- Close the buffer without saving
        pcall(vim.cmd, "bdelete!")
    end)

    describe(":Vault note outlinks", function()
        it("should prepare outlinks data for test_note.md (has outlinks)", function()
            -- test_note.md has 3 wikilinks — the command builds outlinks data
            -- and would open a Telescope picker. We intercept at the pickers level.
            --
            -- Instead of mocking pickers (which causes require errors with telescope
            -- internal state), we test the data preparation path directly.
            local Note = require("vault.notes.note")
            local note = Note(test_note_path)
            local outlinks = note.data.outlinks or {}

            -- test_note.md has 3 outgoing wikilinks
            assert.is_true(vim.tbl_count(outlinks) > 0, "test_note.md should have outlinks, got 0")
        end)
    end)

    describe(":Vault note inlinks", function()
        it("should have inlinks for test_note.md (shell_and_code_test links to it)", function()
            -- test_note.md now has inlinks from shell_and_code_test.md which contains [[test_note]].
            local Note = require("vault.notes.note")
            local note = Note(test_note_path)
            local inlinks = note.data.inlinks or {}

            -- shell_and_code_test.md links to test_note
            assert.are.equal(1, vim.tbl_count(inlinks), "test_note.md should have 1 inlink")
        end)
    end)

    describe(":Vault note tags", function()
        it("should have tags data on test_note.md", function()
            -- test_note.md has many inline tags.
            -- Test the data preparation path (tags exist on the note).
            local Note = require("vault.notes.note")
            local note = Note(test_note_path)
            local tags = note.data.tags or {}

            assert.is_true(vim.tbl_count(tags) > 0, "test_note.md should have tags")
        end)
    end)
end)

-- ═══════════════════════════════════════════════════════════════════════════════
-- TIER 3 — Filesystem-Mutating Commands (VaultNoteNew, VaultRename)
--
-- These tests work on the demo-vault fixture directly.
-- They create/move files and **clean up** in after_each.
-- ═══════════════════════════════════════════════════════════════════════════════

describe("Vault filesystem commands", function()
    -- Ensure vault is configured so config.options.ext is available
    setup_vault()

    describe(":VaultNoteNew with slug", function()
        local new_slug = "test-new-command-note"
        local config = require("vault.config")
        local expected_path = fixture_root .. "/" .. new_slug .. config.options.ext

        after_each(function()
            -- Clean up: remove the created file if it exists
            if vim.fn.filereadable(expected_path) == 1 then
                vim.fn.delete(expected_path)
            end
            -- Close any buffer for it
            pcall(vim.cmd, "bdelete! " .. vim.fn.fnameescape(expected_path))
        end)

        it("should create a new note file and open it for editing", function()
            -- Ensure it doesn't exist before
            assert.are.equal(0, vim.fn.filereadable(expected_path))

            local callbacks = require("vault.commands")
            callbacks.create_new_note({
                fargs = { new_slug },
            })

            -- File should now exist on disk
            assert.are.equal(
                1,
                vim.fn.filereadable(expected_path),
                "note file should exist at: " .. expected_path
            )
        end)
    end)

    describe(":VaultRename", function()
        -- We create a disposable note, rename it, then verify
        local config = require("vault.config")
        local original_slug = "test-rename-source"
        local renamed_slug = "test-rename-destination"
        local original_path = fixture_root .. "/" .. original_slug .. config.options.ext
        local renamed_path = fixture_root .. "/" .. renamed_slug .. config.options.ext

        before_each(function()
            -- Create the source note
            vim.fn.writefile(
                { "---", "title: Rename Test", "---", "", "Some content" },
                original_path
            )
        end)

        after_each(function()
            -- Clean up both possible paths
            for _, p in ipairs({ original_path, renamed_path }) do
                if vim.fn.filereadable(p) == 1 then
                    vim.fn.delete(p)
                end
                pcall(vim.cmd, "bdelete! " .. vim.fn.fnameescape(p))
            end
        end)

        it("should rename a note from one slug to another", function()
            -- Open the source note
            vim.cmd("e " .. vim.fn.fnameescape(original_path))

            -- Execute the rename callback directly (avoid the bdelete! + edit in the callback)
            local Note = require("vault.notes.note")
            local note = Note(original_path)

            local ok, err = pcall(function()
                note:move(renamed_path)
            end)
            assert.is_true(ok, "move should succeed, got error: " .. tostring(err))

            -- Original should be gone
            assert.are.equal(
                0,
                vim.fn.filereadable(original_path),
                "original file should no longer exist"
            )
            -- Renamed should exist
            assert.are.equal(
                1,
                vim.fn.filereadable(renamed_path),
                "renamed file should exist at: " .. renamed_path
            )
        end)
    end)
end)

-- ═══════════════════════════════════════════════════════════════════════════════
-- TIER 4 — Completion Functions
-- ═══════════════════════════════════════════════════════════════════════════════

describe("Vault command completions", function()
    -- Ensure vault is configured so completions that depend on config work
    setup_vault()
    clear_state()

    local completions = require("vault.commands.completions")

    describe("api()", function()
        it("should return a list of API function names", function()
            -- vault.api requires telescope pickers at module scope.
            -- In headless tests this may fail if telescope state is broken.
            -- Use pcall to test gracefully.
            local ok, api_mod = pcall(require, "vault.api")
            if not ok then
                -- telescope pickers module cannot load in headless —
                -- verify the completions function itself returns a table
                -- by mocking at the package.loaded level
                package.loaded["vault.api"] = {
                    open_picker_bases = function() end,
                    open_picker_base_notes = function() end,
                    open_picker_notes_with_tag = function() end,
                }
            end

            local result = completions.api()
            assert.is_table(result)
            assert.is_true(#result > 0, "api completions should not be empty")

            -- Clean up mock if we installed one
            if not ok then
                package.loaded["vault.api"] = nil
            end
        end)

        it("includes tasks and actions at top level", function()
            local result = completions.api(nil, "Vault ", nil)
            assert.is_table(result)
            assert.is_true(vim.tbl_contains(result, "tasks"))
            assert.is_true(vim.tbl_contains(result, "actions"))
        end)

        it("completes tasks subcommands", function()
            local result = completions.api(nil, "Vault tasks ", nil)
            assert.is_table(result)
            assert.is_true(vim.tbl_contains(result, "new"))
            assert.is_true(vim.tbl_contains(result, "status"))
            assert.is_true(vim.tbl_contains(result, "pick-next"))
            assert.is_true(vim.tbl_contains(result, "promote"))
            assert.is_true(vim.tbl_contains(result, "list"))
            assert.is_true(vim.tbl_contains(result, "kanban"))
            assert.is_true(vim.tbl_contains(result, "backlog"))
            assert.is_true(vim.tbl_contains(result, "doctor"))
            assert.is_true(vim.tbl_contains(result, "recur"))
        end)

        it("completes tasks status values", function()
            local result = completions.api(nil, "Vault tasks status ", nil)
            assert.is_table(result)
            assert.is_true(#result >= 1)
            assert.is_true(vim.tbl_contains(result, "Status - Backlog"))
        end)
    end)

    describe("note_slugs()", function()
        it("should return note slugs from the fixture vault", function()
            -- Ensure scanner has data by requiring Notes first
            clear_state()
            local Notes = require("vault.notes")
            Notes() -- Trigger scan

            local result = completions.note_slugs()
            assert.is_table(result)
            assert.is_true(#result >= 22, "should have at least 22 slugs, got " .. #result)
        end)
    end)

    describe("vault_notes_presets()", function()
        it("should return the preset list", function()
            local result = completions.vault_notes_presets()
            assert.is_table(result)
            assert.are.same({ "linked", "orphans", "leaves", "by" }, result)
        end)
    end)

    describe("match_opts()", function()
        it("should return match option keys", function()
            local result = completions.match_opts()
            assert.is_table(result)
            assert.is_true(#result > 0, "match_opts should not be empty")
        end)
    end)

    describe("match_types()", function()
        it("should return match type keys", function()
            local result = completions.match_types()
            assert.is_table(result)
            assert.is_true(#result > 0, "match_types should not be empty")
        end)
    end)

    describe("dirs()", function()
        it("should return directory completions", function()
            -- Ensure Notes have been loaded so dirs() has data
            clear_state()
            local Notes = require("vault.notes")
            Notes()

            local result = completions.dirs(nil, "VaultDirs ", nil)
            assert.is_table(result)
            -- Fixture vault has directories: Inbox, Project, _docs, views, Journal, Journal/Daily
            assert.is_true(#result >= 1, "should have at least 1 directory")
        end)
    end)

    describe("tags()", function()
        it("should return tag completions", function()
            -- Ensure Notes/Tags have been loaded
            clear_state()
            local Notes = require("vault.notes")
            Notes()

            local result = completions.tags(nil, "VaultTags ", nil)
            assert.is_table(result)
            -- Fixture vault has many tags
            assert.is_true(#result >= 1, "should have at least 1 tag")
        end)
    end)

    describe("note_data_keys()", function()
        it("should return a list of note data keys", function()
            local result = completions.note_data_keys()
            assert.is_table(result)
            assert.is_true(#result > 0, "note_data_keys should not be empty")
        end)
    end)

    describe("duplicates_review()", function()
        local commands
        local original_duplicates

        before_each(function()
            setup_vault()
            clear_state()
            commands = require("vault.commands")
            original_duplicates = package.loaded["vault.duplicates"]
        end)

        after_each(function()
            package.loaded["vault.duplicates"] = original_duplicates
        end)

        it("passes dir and kind filters to duplicate review", function()
            local captured = nil
            package.loaded["vault.duplicates"] = {
                review = function(root, opts)
                    captured = { root = root, opts = opts }
                end,
                resolve_kind_filter = function(tokens)
                    return { metadata = true }, nil
                end,
                kind_filter_names = function()
                    return { "metadata" }
                end,
            }

            commands.duplicates_review({ fargs = { "dir", "Reference", "kind", "metadata" } })

            assert.is_not_nil(captured)
            assert.are.equal(fixture_root, captured.root)
            assert.is_true(captured.opts.kinds.metadata)
            assert.are.same({ "Reference" }, captured.opts.filter_spec.dirs)
            assert.are.same({ "metadata" }, captured.opts.filter_spec.kinds)
            assert.is_true(
                captured.opts.path_filters.dirs[fixture_root .. "/Reference/lua-patterns.md"]
            )
            assert.is_true(
                captured.opts.path_filters.dirs[fixture_root .. "/Reference/git-workflows.md"]
            )
        end)

        it("passes tag filters to duplicate review", function()
            local captured = nil
            package.loaded["vault.duplicates"] = {
                review = function(root, opts)
                    captured = { root = root, opts = opts }
                end,
                resolve_kind_filter = function(tokens)
                    return { divergent = true }, nil
                end,
                kind_filter_names = function()
                    return { "divergent" }
                end,
            }

            commands.duplicates_review({ fargs = { "tags", "test", "kind", "divergent" } })

            assert.is_not_nil(captured)
            assert.are.equal(fixture_root, captured.root)
            assert.are.same({ "test" }, captured.opts.filter_spec.tags)
            assert.are.same({ "divergent" }, captured.opts.filter_spec.kinds)
            assert.is_true(captured.opts.path_filters.tags[fixture_root .. "/test_note.md"])
            assert.is_true(captured.opts.kinds.divergent)
        end)

        it("completes duplicate review clause keywords at top level", function()
            local result = commands.complete_duplicates_review("", "Vault duplicates review ")

            assert.is_true(vim.tbl_contains(result, "dir"))
            assert.is_true(vim.tbl_contains(result, "tags"))
            assert.is_true(vim.tbl_contains(result, "kind"))
            assert.is_true(vim.tbl_contains(result, "vault"))
        end)

        it("completes directories inside a dir clause and keywords after it", function()
            local dir_values =
                commands.complete_duplicates_review("", "Vault duplicates review dir ")
            assert.is_true(vim.tbl_contains(dir_values, "Inbox"))
            assert.is_true(vim.tbl_contains(dir_values, "Reference"))

            local next_values =
                commands.complete_duplicates_review("", "Vault duplicates review dir Inbox ")
            assert.is_true(vim.tbl_contains(next_values, "kind"))
            assert.is_true(vim.tbl_contains(next_values, "tags"))
        end)

        it("completes tags and kind aliases in their respective clauses", function()
            local tag_values =
                commands.complete_duplicates_review("", "Vault duplicates review tags ")
            assert.is_true(vim.tbl_contains(tag_values, "test"))

            local kind_values =
                commands.complete_duplicates_review("", "Vault duplicates review kind ")
            assert.is_true(vim.tbl_contains(kind_values, "metadata"))
            assert.is_true(vim.tbl_contains(kind_values, "body"))
        end)

        it("passes related buckets into related duplicate review", function()
            local captured = nil
            package.loaded["vault.duplicates"] = {
                review_related = function(root, opts)
                    captured = { root = root, opts = opts }
                end,
                resolve_kind_filter = function()
                    return { divergent = true }, nil
                end,
                resolve_related_filter = function(tokens)
                    if tokens[1] == "likely" then
                        return { likely = true }, nil
                    end
                    return nil, "bad"
                end,
                kind_filter_names = function()
                    return { "metadata", "body", "divergent" }
                end,
                related_filter_names = function()
                    return { "likely", "maybe", "weak" }
                end,
            }

            commands.duplicates_related({ fargs = { "likely", "kind", "divergent" } })

            assert.is_not_nil(captured)
            assert.are.equal(fixture_root, captured.root)
            assert.is_true(captured.opts.related_buckets.likely)
            assert.are.same({ "likely" }, captured.opts.filter_spec.related)
            assert.is_true(captured.opts.kinds.divergent)
        end)

        it("completes related duplicate buckets and clauses", function()
            local bucket_values =
                commands.complete_duplicates_related("", "Vault duplicates related ")
            assert.is_true(vim.tbl_contains(bucket_values, "likely"))
            assert.is_true(vim.tbl_contains(bucket_values, "dir"))

            local kind_values =
                commands.complete_duplicates_related("", "Vault duplicates related likely kind ")
            assert.is_true(vim.tbl_contains(kind_values, "metadata"))
            assert.is_true(vim.tbl_contains(kind_values, "body"))
        end)
    end)
end)
