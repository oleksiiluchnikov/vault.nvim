vim.opt.runtimepath:append(vim.fn.getcwd() .. "/**")
vim.opt.runtimepath:append(vim.fn.getenv("HOME") .. "/.local/share/nvim/lazy/**")
local assert = require("luassert")
local Notes = require("vault.notes")
local Wikilinks = require("vault.wikilinks")
local Note = require("vault.notes.note")


describe("Notes:wikilinks", function()
  it("should return a VaultWikilinks object", function()
    local notes = Notes()
    local wikilinks = notes.wikilinks
    ---@diagnostic disable-next-line: undefined-field
    assert.is_true(wikilinks.class.name == "VaultWikilinks")
  end)

  
end)

describe("Notes.tags", function()
  it("should return a VaultTags object", function()
    local notes = Notes()
    local tags = notes.tags
    ---@diagnostic disable-next-line: undefined-field
    assert.is_true(tags.class.name == "VaultTags")
  end)
end)



