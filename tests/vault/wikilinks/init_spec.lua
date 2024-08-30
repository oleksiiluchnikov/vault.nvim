local Notes = require("vault.notes")
local assert = require("luassert")

describe("VaultWikilinks:", function()
    it("should return a new Wikilinks object", function()
        local Wikilinks = require("vault.wikilinks")
        local wikilinks = Wikilinks()
        --- @diagnostic disable-next-line: undefined-field
        assert.is_true(wikilinks.class.name == "VaultWikilinks")
    end)
end)

describe("VaultWikilinks:unresolved", function()
    it("should return a new Wikilinks object", function()
        local Wikilinks = require("vault.wikilinks")
        local wikilinks = Wikilinks()
        --- @diagnostic disable-next-line: undefined-field
        assert.is_true(wikilinks.class.name == "VaultWikilinks")
    end)
    it("should return a new Wikilinks object with links to Note that do not exist", function()
        local Wikilinks = require("vault.wikilinks")
        local wikilinks = Wikilinks()
        local unresolved_links = wikilinks:unresolved()
        local link_titles = vim.tbl_map(function(wikilink)
            return wikilink.title
        end, unresolved_links.map)

        local notes_map = Notes().map
        local notes_stems = vim.tbl_map(function(note)
            return note.data.stem:lower()
        end, notes_map)
        for _, stem in ipairs(notes_stems) do
            assert.is_false(vim.tbl_contains(link_titles, stem))
        end
    end)
end)
