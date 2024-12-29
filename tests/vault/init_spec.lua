--- @module "busted"
-- spec/vault_spec.lua
local vault = require("vault")
local busted = require("busted")
local assert = require("luassert.stub")

describe("vault.nvim", function()
    local config

    before_each(function()
        config = {
            setup = assert.stub(),
            options = {
                features = {
                    commands = false,
                    cmp = false,
                }
            }
        }
        package.loaded["vault.config"] = config
    end)

    after_each(function()
        package.loaded["vault.config"] = nil
        package.loaded["vault.commands"] = nil
        package.loaded["vault.cmp"] = nil
    end)

    describe("setup", function()
        it("should call config.setup with options", function()
            local opts = { some_option = true }
            vault.setup(opts)
            assert.stub(config.setup).was_called_with(opts)
        end)

        it("should require vault.commands if features.commands is true", function()
            config.options.features.commands = true
            vault.setup()
            assert.stub(require).was_called_with("vault.commands")
        end)

        it("should call vault.cmp.setup if features.cmp is true", function()
            config.options.features.cmp = true
            package.loaded["vault.cmp"] = { setup = assert.stub() }
            vault.setup()
            assert.stub(require("vault.cmp").setup).was_called()
        end)
    end)

    describe("checkhealth", function()
        it("should return error if telescope is not installed", function()
            package.loaded["telescope"] = nil
            local result = vault.checkhealth()
            assert.are.same(result, {
                status = "error",
                message = "`telescope` is required to run vault.nvim",
            })
        end)

        it("should return error if cmp is not installed", function()
            package.loaded["telescope"] = {}
            package.loaded["cmp"] = nil
            local result = vault.checkhealth()
            assert.are.same(result, {
                status = "error",
                message = "`cmp` is required to run vault.nvim",
            })
        end)

        it("should return ok if all dependencies are installed", function()
            package.loaded["telescope"] = {}
            package.loaded["cmp"] = {}
            local result = vault.checkhealth()
            assert.are.same(result, {
                status = "ok",
                message = "All dependencies are installed",
            })
        end)
    end)
end)
