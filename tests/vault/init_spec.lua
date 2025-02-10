-- spec/vault_spec.lua

describe("vault.nvim", function()
    local config

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
        assert.equals("~/test-vault", config.options.root) -- Before expansion
        assert.equals(".markdown", config.options.ext)
    end)

    it("should validate required options", function()
        assert.has_no.errors(function()
            config.setup({ root = "~/test" })
        end)
    end)
end)
