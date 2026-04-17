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

    it("invalidates note caches explicitly", function()
        local scanner = require("vault.scanner")
        state.set_global_key("cache.notes.paths", { demo = true })
        state.set_global_key("cache.notes.slugs", { demo = true })
        state.set_global_key("cache.notes.basename_index", { demo = true })

        scanner.invalidate_notes_cache()

        assert.is_nil(state.get_global_key("cache.notes.paths"))
        assert.is_nil(state.get_global_key("cache.notes.slugs"))
        assert.is_nil(state.get_global_key("cache.notes.basename_index"))
    end)
end)

describe("vault.scanner persisted cache path", function()
    local originals

    before_each(function()
        originals = {
            config = package.loaded["vault.config"],
            core = package.loaded["vault_core"],
            scanner = package.loaded["vault.scanner"],
        }
        package.loaded["vault.scanner"] = nil
    end)

    after_each(function()
        package.loaded["vault.config"] = originals.config
        package.loaded["vault_core"] = originals.core
        package.loaded["vault.scanner"] = originals.scanner
        state.set_global_key("cache.notes.paths_and_wikilinks_cached", nil)
        state.set_global_key("notes.link_index", nil)
    end)

    it("passes a persisted snapshot path to the core cached scanner", function()
        local captured = nil
        package.loaded["vault.config"] = {
            options = {
                root = "/tmp/demo-vault",
                ignore = { ".git/*", "node_modules/*" },
            },
        }
        package.loaded["vault_core"] = {
            paths_and_wikilinks_cached = function(root, ignores, generation, snapshot_path)
                captured = {
                    generation = generation,
                    ignores = ignores,
                    root = root,
                    snapshot_path = snapshot_path,
                }
                return {
                    changed = true,
                    full = true,
                    generation = 1,
                    paths = {},
                    wikilinks = {},
                }
            end,
        }

        require("vault.scanner").paths_and_wikilinks_cached()

        assert.is_not_nil(captured)
        assert.are.equal("/tmp/demo-vault", captured.root)
        assert.are.same({ ".git/*", "node_modules/*" }, captured.ignores)
        assert.is_nil(captured.generation)
        assert.is_truthy(captured.snapshot_path:match("vault%.nvim/scan%-cache/.+%.bin$"))
    end)

    it("clears the persisted snapshot path when clearing the Rust cache", function()
        local cleared_path = nil
        package.loaded["vault.config"] = {
            options = {
                root = "/tmp/demo-vault",
                ignore = { ".git/*" },
            },
        }
        package.loaded["vault_core"] = {
            clear_cache = function(snapshot_path)
                cleared_path = snapshot_path
            end,
        }
        state.set_global_key("cache.notes.paths_and_wikilinks_cached", { generation = 9 })
        state.set_global_key("notes.link_index", { demo = true })

        require("vault.scanner").clear_rust_cache()

        assert.is_nil(state.get_global_key("cache.notes.paths_and_wikilinks_cached"))
        assert.is_nil(state.get_global_key("notes.link_index"))
        assert.is_truthy(cleared_path:match("vault%.nvim/scan%-cache/.+%.bin$"))
    end)
end)

describe("vault.scanner background revalidate", function()
    local originals

    before_each(function()
        originals = {
            config = package.loaded["vault.config"],
            core = package.loaded["vault_core"],
            prewarm = package.loaded["vault.prewarm"],
            scanner = package.loaded["vault.scanner"],
            schedule = vim.schedule,
        }
        package.loaded["vault.scanner"] = nil
    end)

    after_each(function()
        package.loaded["vault.config"] = originals.config
        package.loaded["vault_core"] = originals.core
        package.loaded["vault.prewarm"] = originals.prewarm
        package.loaded["vault.scanner"] = originals.scanner
        vim.schedule = originals.schedule
        state.clear_all()
    end)

    it("schedules one background revalidate after a snapshot-backed result", function()
        local scheduled = {}
        local calls = 0

        vim.schedule = function(fn)
            scheduled[#scheduled + 1] = fn
        end

        package.loaded["vault.config"] = {
            options = {
                root = "/tmp/demo-vault",
                ignore = {},
            },
        }
        package.loaded["vault_core"] = {
            paths_and_wikilinks_cached = function(_, _, known_generation)
                calls = calls + 1
                if known_generation == nil then
                    return {
                        changed = true,
                        full = true,
                        generation = 5,
                        needs_revalidate = true,
                        paths = {
                            demo = {
                                path = "/tmp/demo-vault/demo.md",
                                slug = "demo",
                                relpath = "demo.md",
                            },
                        },
                        wikilinks = {},
                    }
                end

                return {
                    changed = false,
                    full = false,
                    generation = known_generation,
                    needs_revalidate = false,
                }
            end,
        }

        local scanner = require("vault.scanner")
        scanner.paths_and_wikilinks_cached()

        assert.are.equal(1, calls)
        assert.are.equal(1, #scheduled)

        scheduled[1]()

        assert.are.equal(2, calls)
        assert.is_nil(state.get_global_key("vault.scanner.background_revalidate_scheduled"))
    end)

    it("clears derived caches and reruns prewarm when revalidate finds changes", function()
        local scheduled = {}
        local prewarm_calls = 0

        vim.schedule = function(fn)
            scheduled[#scheduled + 1] = fn
        end

        package.loaded["vault.config"] = {
            options = {
                root = "/tmp/demo-vault",
                ignore = {},
            },
        }
        package.loaded["vault.prewarm"] = {
            run_enabled_now = function()
                prewarm_calls = prewarm_calls + 1
                return true
            end,
        }
        package.loaded["vault_core"] = {
            paths_and_wikilinks_cached = function(_, _, known_generation)
                if known_generation == nil then
                    return {
                        changed = true,
                        full = true,
                        generation = 5,
                        needs_revalidate = true,
                        paths = {
                            demo = {
                                path = "/tmp/demo-vault/demo.md",
                                slug = "demo",
                                relpath = "demo.md",
                            },
                        },
                        wikilinks = {},
                    }
                end

                return {
                    changed = true,
                    full = true,
                    generation = 6,
                    needs_revalidate = false,
                    paths = {
                        demo = {
                            path = "/tmp/demo-vault/demo.md",
                            slug = "demo",
                            relpath = "demo.md",
                        },
                    },
                    wikilinks = {},
                }
            end,
        }

        local scanner = require("vault.scanner")
        scanner.paths_and_wikilinks_cached()
        state.set_global_key("notes", { demo = true })
        state.set_global_key("tags", { demo = true })

        scheduled[1]()

        local cached = state.get_global_key("cache.notes.paths_and_wikilinks_cached")
        assert.are.equal(6, cached.generation)
        assert.is_nil(state.get_global_key("notes"))
        assert.is_nil(state.get_global_key("tags"))
        assert.are.equal(1, prewarm_calls)
    end)
end)
