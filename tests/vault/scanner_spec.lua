local state = require("vault.core.state")

describe("vault.scanner.paths", function()
    local save_depth_key = "vault.process_save_depth"

    before_each(function()
        package.loaded["vault.scanner"] = nil
        package.loaded["vault_core"] = nil
        state.set_global_key("cache.notes.paths", nil)
        state.set_global_key(save_depth_key, nil)
    end)

    after_each(function()
        package.loaded["vault_core"] = nil
        state.set_global_key("cache.notes.paths", nil)
        state.set_global_key(save_depth_key, nil)
    end)

    it("uses cached paths during process-buffer saves", function()
        local calls = 0
        package.loaded["vault_core"] = {
            paths = function()
                calls = calls + 1
                return {
                    demo = {
                        path = "/tmp/demo.md",
                        slug = "demo",
                        relpath = "demo.md",
                    },
                }
            end,
        }

        local scanner = require("vault.scanner")
        local initial = scanner.paths()
        state.set_global_key(save_depth_key, 1)

        local cached = scanner.paths()

        assert.are.equal(1, calls)
        assert.are.same(initial, cached)
    end)
end)
