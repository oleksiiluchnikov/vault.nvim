describe("vault.watcher", function()
    local Watcher
    local temp_vault

    before_each(function()
        -- Setup temp vault
        temp_vault = vim.fn.tempname()
        vim.fn.mkdir(temp_vault, "p")

        require("vault").setup({ root = temp_vault })
        Watcher = require("vault.watcher")
    end)

    after_each(function()
        vim.fn.delete(temp_vault, "rf")
    end)

    it("detects file renames", function()
        local watcher = Watcher()
        watcher:start()

        -- Create test files
        local old_path = temp_vault .. "/old.md"
        local new_path = temp_vault .. "/new.md"

        vim.fn.writefile({ "# Old" }, old_path)
        vim.fn.rename(old_path, new_path)

        -- Wait for debounce
        vim.wait(1000)

        assert.is_true(vim.fn.filereadable(new_path) == 1)
        watcher:stop()
    end)

    it("updates wikilinks on rename", function()
        -- Test link update logic
        local referrer = temp_vault .. "/referrer.md"
        local target = temp_vault .. "/target.md"

        vim.fn.writefile({ "[[target]]" }, referrer)
        vim.fn.writefile({ "# Target" }, target)

        local watcher = Watcher()
        watcher:handle_rename(target, temp_vault .. "/renamed.md")

        local content = vim.fn.readfile(referrer)
        assert.are.same({ "[[renamed]]" }, content)
    end)
end)
