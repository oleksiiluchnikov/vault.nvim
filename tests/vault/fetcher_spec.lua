vim.opt.runtimepath:append(vim.fn.getcwd() .. "/**")
vim.opt.runtimepath:append(vim.fn.getenv("HOME") .. "/.local/share/nvim/lazy/**")
local assert = require("luassert")
local Fetcher = require("vault.fetcher")
local test_text = [[
---
title: Hello World
date_created: 2021-01-01
date_modified: 2021-01-01
tags: [hello, world]
nested:
  - hello
  - world
bool: true
num: 1

weight: 1.5
wikilinked: \[\[Hello World\]\]
---
]]

describe("VaultFetcher", function()
    it("should return", function() end)
end)

describe("VaultFetcher.paths", function()
    it("should return vault.Notes.map that not nil", function()
        --- @type table<vault.slug, {path: vault.path, slug: vault.slug, relpath: string, basename: vault.Note.Data.basename}>
        local paths_map = Fetcher.paths()
        if next(paths_map) == nil then
            assert.is_nil(paths_map)
        else
            assert.is_not_nil(paths_map)
        end
    end)
end)
