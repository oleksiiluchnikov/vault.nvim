local utils = require("vault.utils")
local Note = require("vault.notes.note")
local Watcher = require("vault.watcher")
local a = require("plenary.async.tests")

a.describe("watcher → link update", function()
    a.it("patches in-links when file is renamed", function()
        -- ❶  prepare sandbox paths
        local root = vim.fn.tempname()
        vim.fn.mkdir(root, "p")
        local src_path = root .. "/note A.md"
        local dst_path = root .. "/note B.md"
        local other = root .. "/ref.md"

        -- ❷  write two notes: one referencing the other
        vim.fn.writefile({ "# note A" }, src_path)
        vim.fn.writefile({ "[[note A]]" }, other)

        -- ❸  prime vault
        require("vault.config").setup({ root = root, features = { watcher = false } })
        require("vault.scanner").refresh()

        -- ❹  run rename though watcher handler
        local w = Watcher()
        local patched = w:handle_rename(src_path, dst_path)

        -- ❺  assert
        assert.are.equal(1, patched)
        local new_link = vim.fn.readfile(other)[1]
        assert.are.equal("[[note B]]", new_link)
    end)
end)
