--- @module "busted"
vim.opt.runtimepath:append(string.format("%s/**", vim.fn.getcwd()))
local assert = require("luassert")
local Filter = require("vault.filter")
local state = require("vault.state")
local Config = require("vault.config")

describe("vault.filter", function()
    -- Reset state before each test
    before_each(function()
        package.loaded["vault.nvim"] = nil
        require("vault.nvim")
        state.clear_all()
    end)

    after_each(function() end)

    describe("initialization", function()
        it("should create a filter with single option table", function()
            local filter = Filter({
                search_term = "tags",
                include = { "test" },
                match_opt = "exact",
                mode = "all",
                case_sensitive = false,
            })

            assert.are.same(filter.opts[1].search_term, "tags")
            assert.are.same(filter.opts[1].include, { "test" })
            assert.are.same(filter.opts[1].match_opt, "exact")
        end)

        it("should create a filter with array of options", function()
            local filter = Filter({
                {
                    search_term = "tags",
                    include = { "test1" },
                },
                {
                    search_term = "tags",
                    include = { "test2" },
                },
            })

            assert.are.same(filter.opts[1].include, { "test1" })
            assert.are.same(filter.opts[2].include, { "test2" })
        end)

        it("should handle string-to-array conversion for include", function()
            local filter = Filter({
                search_term = "tags",
                include = "test",
            })

            assert.are.same(filter.opts[1].include, { "test" })
        end)

        it("should handle string-to-array conversion for exclude", function()
            local filter = Filter({
                search_term = "tags",
                include = { "test" },
                exclude = "excluded",
            })

            assert.are.same(filter.opts[1].exclude, { "excluded" })
        end)
    end)

    describe("validation", function()
        it("should error on missing search_term", function()
            assert.has_error(function()
                Filter({
                    include = { "test" },
                })
            end, "invalid argument: must have a search term")
        end)

        it("should error when neither include nor exclude is provided", function()
            assert.has_error(function()
                Filter({
                    search_term = "tags",
                })
            end, "invalid argument: must have at least one include or exclude")
        end)

        it("should error on invalid match_opt", function()
            assert.has_error(function()
                Filter({
                    search_term = "tags",
                    include = { "test" },
                    match_opt = "invalid",
                })
            end, "invalid argument: must be a valid match_opt")
        end)

        it("should error on invalid mode", function()
            assert.has_error(function()
                Filter({
                    search_term = "tags",
                    include = { "test" },
                    mode = "invalid",
                })
            end, "invalid argument: must be a valid mode")
        end)
    end)

    describe("invert functionality", function()
        it("should correctly invert include and exclude lists", function()
            local filter = Filter({
                search_term = "tags",
                include = { "test1", "test2" },
                exclude = { "test3", "test4" },
            })

            local inverted = filter:invert()
            assert.are.same(inverted.opts[1].include, { "test1", "test2" })
            assert.are.same(inverted.opts[1].exclude, { "test3", "test4" })
        end)
    end)

    describe("state management", function()
        it("should store filter in global state", function()
            local filter = Filter({
                search_term = "tags",
                include = { "test" },
            })

            local stored_filter = state.get_global_key("recent.filter")
            assert.are.same(stored_filter, filter)
        end)
    end)

    describe("args_to_opts conversion", function()
        it("should convert array arguments to options table", function()
            local filter = Filter({ "tags", { "test" }, { "exclude" }, "exact", "all", true })

            assert.are.same(filter.opts[1].search_term, "tags")
            assert.are.same(filter.opts[1].include, { "test" })
            assert.are.same(filter.opts[1].exclude, { "exclude" })
            assert.are.same(filter.opts[1].match_opt, "exact")
            assert.are.same(filter.opts[1].mode, "all")
            assert.is_true(filter.opts[1].case_sensitive)
        end)
    end)
end)
