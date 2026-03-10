local root_cwd = vim.fn.getcwd()
local fixture_root = root_cwd .. "/tests/fixtures/demo-vault"

local function clear_state()
    package.loaded["vault"] = nil
    package.loaded["vault.notes"] = nil
    package.loaded["vault.wikilinks"] = nil
    package.loaded["telescope._extensions.vault.pickers.notes.stats"] = nil
    require("vault.core.state").global = {}
end

describe("telescope._extensions.vault.pickers.notes.stats", function()
    before_each(function()
        require("vault").setup({
            root = fixture_root,
            ext = ".md",
            features = {
                commands = true,
                watcher = false,
            },
        })
        clear_state()
    end)

    it("collects outlink, backlink, and dangling counts for notes", function()
        local notes = require("vault.notes")():list()
        local stats = require("telescope._extensions.vault.pickers.notes.stats")
        local counts = stats.collect(notes)
        local note_by_slug = {}
        for _, note in ipairs(notes) do
            note_by_slug[note.data.slug] = note
        end

        local test_note = note_by_slug["test_note"]
        assert.is_not_nil(test_note)

        local expected_out = vim.tbl_count(test_note.data.outlinks or {})
        local expected_in = vim.tbl_count(test_note.data.inlinks or {})
        local expected_dang = 0
        for _, wl in pairs(test_note.data.outlinks or {}) do
            if not wl.data.target or wl.data.target == "" then
                expected_dang = expected_dang + 1
            end
        end

        assert.are.equal(expected_out, counts.test_note.outlinks)
        assert.are.equal(expected_in, counts.test_note.inlinks)
        assert.are.equal(expected_dang, counts.test_note.dangling)
        assert.are.equal(
            string.format("out %d  in %d  dang %d", expected_out, expected_in, expected_dang),
            stats.format(counts.test_note)
        )
        assert.are.same({
            string.format("out %d", expected_out),
            string.format("in %d", expected_in),
            string.format("dang %d", expected_dang),
        }, { stats.columns(counts.test_note) })
    end)
end)
