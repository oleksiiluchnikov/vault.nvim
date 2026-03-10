--- @module "busted"
local assert = require("luassert")

describe("VaultNotes", function()
    -- 1. Setup Logic (Runs once when this describe block is loaded)
    local fixture_path = vim.fn.getcwd() .. "/tests/fixtures/demo-vault"

    if vim.fn.isdirectory(fixture_path) == 0 then
        error("Fixture directory not found at: " .. fixture_path)
    end

    -- Setup vault configuration
    require("vault").setup({
        root = fixture_path,
        ext = ".md",
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

    -- Reload the module to ensure it picks up the config
    package.loaded["vault.notes"] = nil
    package.loaded["vault.core.state"] = nil
    local Notes = require("vault.notes")

    -- 2. Helpers
    local function has_key(note, key)
        return note.data[key] ~= nil
    end

    -- 3. Tests
    describe("VaultNotes:init()", function()
        it("should return a `VaultNotes` object", function()
            local notes = Notes()
            assert.are.equal("VaultNotes", notes.class.name)
        end)

        it("should have more than 0 notes in map", function()
            local notes = Notes()

            if notes:count() == 0 then
                print("\n[DEBUG] Root:", require("vault.config").options.root)
                print(
                    "[DEBUG] Files:",
                    vim.inspect(vim.fn.glob(fixture_path .. "/**/*.md", true, true))
                )
            end

            assert.is_true(notes:count() > 0)
        end)

        it("should contain VaultNote objects", function()
            local notes = Notes()
            local note = vim.tbl_values(notes.map)[1]
            if not note then
                error("No notes found in the vault for testing VaultNote type")
            end
            assert.are.equal("VaultNote", note.class.name)
        end)
    end)

    describe("VaultNotes:to_group", function()
        it("should return a `VaultNotesGroup` object", function()
            local notes = Notes()
            local notes_group = notes:to_group()
            assert.are.equal("VaultNotesGroup", notes_group.class.name)
        end)
    end)

    describe("VaultNotes:to_cluster", function()
        it("should return a `VaultNotesCluster` object", function()
            local notes = Notes()
            -- Find a note that actually has links for a meaningful cluster
            local linked_notes = notes:linked()
            if not linked_notes then
                error("Failed to retrieve linked notes for cluster test")
            end

            if linked_notes:count() > 0 then
                local center_note = linked_notes:get_random()
                local cluster = notes:to_cluster(center_note, 0)
                assert.are.equal("VaultNotesCluster", cluster.class.name)
            else
                print("Skipping cluster test: no linked notes found")
            end
        end)
    end)

    describe("VaultNotes:list()", function()
        it("should return an indexed table of notes", function()
            local list = Notes():list()
            assert.is_table(list)
            assert.is_number(#list)
            if #list > 0 then
                assert.are.equal("VaultNote", list[1].class.name)
            end
        end)
    end)

    describe("VaultNotes:count()", function()
        it("should return correct count", function()
            local notes = Notes()
            local count = 0
            for _ in pairs(notes.map) do
                count = count + 1
            end
            assert.are.equal(count, notes:count())
        end)
    end)

    describe("VaultNotes:get_random()", function()
        it("should return a random note", function()
            local note = Notes():get_random()
            assert.is_not_nil(note)
            assert.are.equal("VaultNote", note.class.name)
        end)
    end)

    describe("VaultNotes:has()", function()
        it("should find note by exact stem", function()
            local notes = Notes()
            local random_note = notes:get_random()
            local stem = random_note.data.stem

            assert.is_true(notes:has("stem", stem, "exact"))
        end)

        it("should find note by startswith stem", function()
            local notes = Notes()
            local random_note = notes:get_random()
            local stem = random_note.data.stem
            local partial = stem:sub(1, math.max(1, math.floor(#stem / 2)))

            assert.is_true(notes:has("stem", partial, "startswith"))
        end)
    end)

    describe("VaultNotes:filter()", function()
        it("should filter by tags (startswith)", function()
            local notes = Notes()
            -- Based on your demo vault files
            local query_tag = "example"

            local filtered = notes:filter({
                search_term = "tags",
                include = { query_tag },
                match_opt = "startswith",
                mode = "any",
            })

            assert.are.equal("VaultNotesGroup", filtered.class.name)
        end)

        it("should filter by content regex", function()
            local filtered = Notes():filter("content", "#", "contains")
            assert.are.equal("VaultNotesGroup", filtered.class.name)
        end)
    end)

    describe("VaultNotes:linked()", function()
        it("should return notes with links", function()
            local linked = Notes():linked()
            assert.are.equal("VaultNotesGroup", linked.class.name)

            if linked:count() > 0 then
                local note = linked:get_random()
                local has_out = note.data.outlinks and next(note.data.outlinks) ~= nil
                local has_in = note.data.inlinks and next(note.data.inlinks) ~= nil
                assert.is_true(has_out or has_in, "Linked note must have inlinks or outlinks")
            end
        end)
    end)

    describe("VaultNotes:orphans()", function()
        it("should return notes with no links", function()
            local orphans = Notes():orphans()
            assert.are.equal("VaultNotesGroup", orphans.class.name)

            for _, note in pairs(orphans.map) do
                local has_out = note.data.outlinks and next(note.data.outlinks) ~= nil
                assert.is_false(has_out, "Orphan should not have outlinks")
            end
        end)
    end)

    describe("VaultNotes:without_property()", function()
        it("should return notes missing a specific frontmatter field", function()
            local notes = Notes():without_property("categories")
            assert.are.equal("VaultNotesGroup", notes.class.name)
            assert.is_true(notes:count() > 0)

            for _, note in pairs(notes.map) do
                local fm = note.data.frontmatter
                local value = type(fm) == "table" and (fm.categories or (type(fm.data) == "table" and fm.data.categories))
                    or nil
                local missing = value == nil
                    or value == vim.NIL
                    or (type(value) == "string" and vim.trim(value) == "")
                    or (type(value) == "table" and next(value) == nil)
                assert.is_true(missing)
            end
        end)
    end)

    describe("VaultNotes:reset()", function()
        it("should restore original map", function()
            local notes = Notes()
            local original_count = notes:count()

            -- Modify the map (filter it)
            notes:filter("stem", "NonExistentStem12345")
            local filtered_count = notes:count()

            assert.is_true(filtered_count < original_count)

            -- Reset
            notes:reset()
            assert.are.equal(original_count, notes:count())
        end)
    end)
end)
