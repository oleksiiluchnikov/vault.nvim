local Notes = require("vault.notes")
-- test
local text = [=[---
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
wikilinked: [[Hello World]]
---
]=]

local random_note = Notes():with_frontmatter():get_random_note()
local frontmatter = random_note.data.frontmatter
print(vim.inspect(frontmatter.data))

-- describe("NoteFrontmatter:init()", function()
--     it("should return a `NoteFrontmatter` instance", function()
--         local frontmatter = random_note.data.frontmatter
--         print(vim.inspect(frontmatter.data))
--     end)
-- end)
