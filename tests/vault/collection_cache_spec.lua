describe("vault collection cache reuse", function()
    local originals

    before_each(function()
        originals = {
            state = package.loaded["vault.core.state"],
            scanner = package.loaded["vault.scanner"],
            tags = package.loaded["vault.tags"],
            properties = package.loaded["vault.properties"],
            dirs = package.loaded["vault.dirs"],
        }
    end)

    after_each(function()
        package.loaded["vault.core.state"] = originals.state
        package.loaded["vault.scanner"] = originals.scanner
        package.loaded["vault.tags"] = originals.tags
        package.loaded["vault.properties"] = originals.properties
        package.loaded["vault.dirs"] = originals.dirs
    end)

    local function make_state()
        local store = {}
        return store,
            {
                get_global_key = function(key)
                    return store[key]
                end,
                set_global_key = function(key, value)
                    store[key] = value
                end,
            }
    end

    it("reuses cached tags without rescanning", function()
        local _, state = make_state()
        local scan_calls = 0

        package.loaded["vault.core.state"] = state
        package.loaded["vault.scanner"] = {
            tags = function()
                scan_calls = scan_calls + 1
                return {
                    alpha = { data = { name = "alpha" } },
                }
            end,
        }

        local Tags = require("vault.tags")
        local first = Tags()
        assert.are.equal(1, scan_calls)

        package.loaded["vault.tags"] = nil
        package.loaded["vault.scanner"] = {
            tags = function()
                error("cached tags should be reused before rescanning")
            end,
        }

        local reloaded = require("vault.tags")
        local second = reloaded()
        assert.are.equal(first:count(), second:count())
    end)

    it("reuses cached properties without rescanning", function()
        local _, state = make_state()
        local scan_calls = 0

        package.loaded["vault.core.state"] = state
        package.loaded["vault.scanner"] = {
            properties = function()
                scan_calls = scan_calls + 1
                return {
                    alpha = { data = { name = "alpha" } },
                }
            end,
        }

        local Properties = require("vault.properties")
        local first = Properties()
        assert.are.equal(1, scan_calls)

        package.loaded["vault.properties"] = nil
        package.loaded["vault.scanner"] = {
            properties = function()
                error("cached properties should be reused before rescanning")
            end,
        }

        local reloaded = require("vault.properties")
        local second = reloaded()
        assert.are.equal(first:count(), second:count())
    end)

    it("reuses cached dirs without rescanning", function()
        local _, state = make_state()
        local scan_calls = 0

        package.loaded["vault.core.state"] = state
        package.loaded["vault.scanner"] = {
            dirs = function()
                scan_calls = scan_calls + 1
                return {
                    Inbox = { data = { relpath = "Inbox" } },
                }
            end,
        }

        local Dirs = require("vault.dirs")
        local first = Dirs()
        assert.are.equal(1, scan_calls)

        package.loaded["vault.dirs"] = nil
        package.loaded["vault.scanner"] = {
            dirs = function()
                error("cached dirs should be reused before rescanning")
            end,
        }

        local reloaded = require("vault.dirs")
        local second = reloaded()
        assert.are.equal(first:count(), second:count())
    end)
end)
