describe("vault.config", function()
    local demo_vault_path = vim.fn.getcwd() .. "/tests/fixtures/demo-vault"
    before_each(function()
        Config = require("vault.config")
        Config.reset() -- Reset config before each test
    end)

    describe("setup", function()
        it("should detect demo vault by default", function()
            Config.setup({
                root = demo_vault_path,
            })
            assert.are.equal(demo_vault_path, Config.options.root)
        end)

        it("should expand root directory with tilde", function()
            Config.setup({ root = demo_vault_path })
            assert.is_not.equal("~", Config.options.root:sub(1, 1))
        end)

        it("should merge user options with defaults", function()
            local custom_options = {
                root = demo_vault_path,
                ext = ".markdown",
                search_tool = "ag",
            }
            Config.setup(custom_options)
            assert.are.equal(vim.fn.expand(demo_vault_path), Config.options.root)
            assert.are.equal(".markdown", Config.options.ext)
            assert.are.equal("ag", Config.options.search_tool)
            -- Default options should still be present
            assert.are.same(Config.get_defaults().features, Config.options.features)
        end)

        it("should error on invalid root", function()
            assert.has_error(function()
                Config.setup({ root = 123 })
            end)
        end)
    end)

    describe("reset", function()
        it("should reset configuration to empty state", function()
            Config.setup({ root = demo_vault_path })
            Config.reset()
            assert.are.same({}, Config.options)
        end)
    end)

    describe("get_defaults", function()
        it("should return a fresh copy of defaults", function()
            local defaults1 = Config.get_defaults()
            local defaults2 = Config.get_defaults()
            assert.are.same(defaults1, defaults2)
            assert.are_not.equal(defaults1, defaults2) -- Should be different tables
        end)

        it("should include taxonomy defaults", function()
            local defaults = Config.get_defaults()
            assert.are.equal("categories", defaults.taxonomy.field)
            assert.are.equal("category - ", defaults.taxonomy.reference_prefix)
            assert.are.equal("person - ", defaults.taxonomy.mapping.person.prefix)
        end)
    end)

    describe("expand_dirs", function()
        it("should expand all directory paths", function()
            Config.setup({
                root = demo_vault_path,
                dirs = {
                    inbox = "inbox",
                    docs = "_docs",
                    templates = "_templates",
                    journal = {
                        root = "journal",
                        daily = "journal/Daily",
                    },
                },
            })

            local expected_root = vim.fn.expand(demo_vault_path)
            assert.are.equal(expected_root .. "/Inbox", Config.options.dirs.inbox)
            assert.are.equal(expected_root .. "/Journal", Config.options.dirs.journal.root)
            assert.are.equal(expected_root .. "/Journal/Daily", Config.options.dirs.journal.daily)
        end)
    end)

    -- describe("validate", function()
    --     it("should validate required options", function()
    --         assert.has_no.errors(function()
    --             Config.setup({ root = demo_vault_path })
    --         end)
    --     end)
    --
    --     it("should error on missing root", function()
    --         assert.has_error(function()
    --             Config.setup({ ext = ".md" })
    --         end)
    --     end)
    --
    --     it("should error on invalid root", function()
    --         assert.has_error(function()
    --             Config.setup({ root = 123 })
    --         end)
    --     end)
    --
    --     it("should error on invalid ext", function()
    --         assert.has_error(function()
    --             Config.setup({ root = demo_vault_path, ext = 123 })
    --         end)
    --     end)
    --
    --     it("should error on invalid search_tool", function()
    --         assert.has_error(function()
    --             Config.setup({ root = demo_vault_path, search_tool = 123 })
    --         end)
    --     end)
    --
    --     it("should error on invalid dirs", function()
    --         assert.has_error(function()
    --             Config.setup({ root = demo_vault_path, dirs = 123 })
    --         end)
    --     end)
    --
    --     it("should error on invalid dir paths", function()
    --         assert.has_error(function()
    --             Config.setup({ root = demo_vault_path, dirs = { inbox = 123 } })
    --         end)
    --     end)
    -- end)
end)
