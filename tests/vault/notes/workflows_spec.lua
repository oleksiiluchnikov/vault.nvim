local config = require("vault.config")
local state = require("vault.core.state")

local function write(path, lines)
    vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
    vim.fn.writefile(lines, path)
end

local function reset_modules()
    package.loaded["vault.notes"] = nil
    package.loaded["vault.notes.paths"] = nil
    package.loaded["vault.notes.workflows"] = nil
    package.loaded["vault.scanner"] = nil
end

describe("vault.notes.workflows", function()
    local root

    before_each(function()
        root = vim.fn.tempname() .. "_vault_workflows"
        vim.fn.mkdir(root, "p")
        state.clear_all()
        config.reset()
        reset_modules()
    end)

    after_each(function()
        vim.fn.delete(root, "rf")
        state.clear_all()
        config.reset()
        reset_modules()
    end)

    it("merges into the existing target path instead of recreating it in the current new-note folder", function()
        write(root .. "/.obsidian/app.json", {
            "{",
            '  "newFileLocation": "folder",',
            '  "newFileFolderPath": "Drafts"',
            "}",
        })
        write(root .. "/Statuses.md", { "# source" })
        write(root .. "/category - Statuses.md", { "# target" })

        require("vault").setup({
            root = root,
            ext = ".md",
            features = { cmp = false, commands = false, watcher = false },
        })
        reset_modules()

        local original_merge = package.loaded["vault.merge"]
        local called = nil
        package.loaded["vault.merge"] = {
            merge = function(target_path, source_path)
                called = { target_path = target_path, source_path = source_path }
            end,
        }

        require("vault.notes.workflows").merge(root .. "/Statuses.md", "category - Statuses", {})

        package.loaded["vault.merge"] = original_merge

        assert.is_not_nil(called)
        assert.are.equal(root .. "/category - Statuses.md", called.target_path)
        assert.are.equal(root .. "/Statuses.md", called.source_path)
        assert.are.equal(0, vim.fn.filereadable(root .. "/Drafts/category - Statuses.md"))
    end)
end)
