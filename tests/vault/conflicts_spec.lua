local config = require("vault.config")
local state = require("vault.core.state")

local tmp_root = vim.fn.getcwd() .. "/tests/tmp_conflicts_vault"

local function reset_modules()
    package.loaded["vault.conflicts"] = nil
    package.loaded["vault.scanner"] = nil
    package.loaded["vault.wikilinks.wikilink"] = nil
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

describe("vault.conflicts.scan", function()
    before_each(function()
        rm_rf(tmp_root)
        vim.fn.mkdir(tmp_root, "p")

        write(tmp_root .. "/References/topic.md", {
            "---",
            "title: topic",
            "created: 20240101000000",
            "---",
            "# topic",
            "alpha",
            "beta",
        })
        write(tmp_root .. "/References/topic 1.md", {
            "---",
            "title: topic",
            "created: 20250101000000",
            "score: 0",
            "---",
            "# topic 1",
            "alpha",
            "beta",
        })
        write(tmp_root .. "/References/idea.md", {
            "# idea",
            "one",
            "two",
        })
        write(tmp_root .. "/References/idea 1.md", {
            "# idea 1",
            "one",
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

    it("classifies live conflict pairs without report files", function()
        local conflicts = require("vault.conflicts")
        local items = conflicts.scan(tmp_root .. "/References")

        assert.are.equal(2, #items)
        assert.are.equal("copy_subset", items[1].kind)
        assert.are.equal("References/idea.md", items[1].keep)
        assert.are.equal("conflicting_metadata", items[2].kind)
        assert.are.equal("References/topic.md", items[2].keep)
    end)
end)
