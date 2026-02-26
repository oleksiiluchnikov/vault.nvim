-- spec/vault_spec.lua

describe("vault.nvim", function()
    local root_cwd = vim.fn.getcwd()
    local fixture_root = root_cwd .. "/tests/fixtures/demo-vault"
    local config = {
        root = fixture_root,
        ext = ".md",

        -- Disable features that might cause async noise during tests
        features = {
            cmp = false, -- Enable if testing completions specifically
            commands = true,
            watcher = false, -- Watchers rely on uv loop, can be flaky in simple tests
        },

        tags = {
            valid = { hex = true },
        },

        -- Ensure we don't write to standard cache paths during test
        search_tool = "rg",
    }
    require("vault").setup(config)

    before_each(function()
        config = require("vault.config")
        config.reset() -- Reset config to clean state before each test
    end)

    after_each(function()
        package.loaded["vault.config"] = nil
    end)

    it("should load the config module", function()
        assert.is_table(config)
    end)

    it("should setup with default options", function()
        config.setup()
        assert.is_table(config.options)
        assert.is_string(config.options.root)
        assert.equals("~/knowledge", config.options.root) -- Before expansion
    end)

    it("should setup with custom options", function()
        config.setup({
            root = "~/test-vault",
            ext = ".markdown",
        })
        local home_dir = vim.fn.expand("~")
        assert.equals(home_dir .. "/test-vault", config.options.root)
        assert.equals(".markdown", config.options.ext)
    end)

    it("should validate required options", function()
        assert.has_no.errors(function()
            config.setup({ root = "~/test" })
        end)
    end)
end)
