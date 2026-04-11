local MODULE = "vault.prewarm"

describe("vault prewarm", function()
    local originals

    before_each(function()
        originals = {
            module = package.loaded[MODULE],
            config = package.loaded["vault.config"],
            dirs_prep = package.loaded["telescope._extensions.vault.pickers.dirs.default_prep"],
            notes = package.loaded["vault.notes"],
            link_index = package.loaded["vault.notes.link_index"],
            properties_prep = package.loaded["telescope._extensions.vault.pickers.properties.default_prep"],
            state = package.loaded["vault.core.state"],
            prep = package.loaded["telescope._extensions.vault.pickers.notes.default_prep"],
            schedule = vim.schedule,
            tags_prep = package.loaded["telescope._extensions.vault.pickers.tags.default_prep"],
            uv = vim.uv,
        }
        package.loaded[MODULE] = nil
    end)

    after_each(function()
        package.loaded[MODULE] = originals.module
        package.loaded["vault.config"] = originals.config
        package.loaded["telescope._extensions.vault.pickers.dirs.default_prep"] =
            originals.dirs_prep
        package.loaded["vault.notes"] = originals.notes
        package.loaded["vault.notes.link_index"] = originals.link_index
        package.loaded["telescope._extensions.vault.pickers.properties.default_prep"] =
            originals.properties_prep
        package.loaded["vault.core.state"] = originals.state
        package.loaded["telescope._extensions.vault.pickers.notes.default_prep"] = originals.prep
        vim.schedule = originals.schedule
        package.loaded["telescope._extensions.vault.pickers.tags.default_prep"] =
            originals.tags_prep
        vim.uv = originals.uv
        vim.env.VAULT_TEST_DISABLE_PREWARM = "1"
    end)

    it("schedules and runs all enabled idle prewarms once", function()
        local state_store = {}
        local dirs_prepare_calls = 0
        local started_delay = nil
        local link_index_calls = 0
        local notes_ctor_calls = 0
        local prepare_calls = 0
        local properties_prepare_calls = 0
        local tags_prepare_calls = 0
        local timer_callback = nil

        vim.env.VAULT_TEST_DISABLE_PREWARM = nil
        vim.schedule = function(fn)
            fn()
        end
        vim.uv = vim.tbl_extend("force", vim.uv or {}, {
            new_timer = function()
                return {
                    start = function(_, delay_ms, _, cb)
                        started_delay = delay_ms
                        timer_callback = cb
                    end,
                    stop = function() end,
                    close = function() end,
                }
            end,
        })

        package.loaded["vault.config"] = {
            options = {
                telescope = {
                    prewarm = {
                        notes = true,
                        properties = true,
                        tags = true,
                        dirs = true,
                        delay_ms = 25,
                    },
                },
            },
        }
        package.loaded["vault.core.state"] = {
            get_global_key = function(key)
                return state_store[key]
            end,
            set_global_key = function(key, value)
                state_store[key] = value
            end,
        }
        package.loaded["vault.notes.link_index"] = {
            get = function()
                link_index_calls = link_index_calls + 1
                return {}
            end,
        }
        package.loaded["vault.notes"] = setmetatable({}, {
            __call = function()
                notes_ctor_calls = notes_ctor_calls + 1
                return {}
            end,
        })
        package.loaded["telescope._extensions.vault.pickers.notes.default_prep"] = {
            get_or_prepare = function()
                prepare_calls = prepare_calls + 1
            end,
        }
        package.loaded["telescope._extensions.vault.pickers.properties.default_prep"] = {
            get_or_prepare = function()
                properties_prepare_calls = properties_prepare_calls + 1
            end,
        }
        package.loaded["telescope._extensions.vault.pickers.tags.default_prep"] = {
            get_or_prepare = function()
                tags_prepare_calls = tags_prepare_calls + 1
            end,
        }
        package.loaded["telescope._extensions.vault.pickers.dirs.default_prep"] = {
            get_or_prepare = function()
                dirs_prepare_calls = dirs_prepare_calls + 1
            end,
        }

        local prewarm = require(MODULE)
        assert.is_true(prewarm.schedule())
        assert.is_true(prewarm.schedule())
        assert.is_not_nil(timer_callback)

        timer_callback()

        assert.are.equal(25, started_delay)
        assert.are.equal(1, link_index_calls)
        assert.are.equal(1, notes_ctor_calls)
        assert.are.equal(1, prepare_calls)
        assert.are.equal(1, properties_prepare_calls)
        assert.are.equal(1, tags_prepare_calls)
        assert.are.equal(1, dirs_prepare_calls)
    end)

    it("does not schedule when all prewarm jobs are disabled", function()
        local created_timer = false

        vim.env.VAULT_TEST_DISABLE_PREWARM = nil
        vim.uv = vim.tbl_extend("force", vim.uv or {}, {
            new_timer = function()
                created_timer = true
                return {
                    start = function() end,
                    stop = function() end,
                    close = function() end,
                }
            end,
        })

        package.loaded["vault.config"] = {
            options = {
                telescope = {
                    prewarm = {
                        notes = false,
                        properties = false,
                        tags = false,
                        dirs = false,
                        delay_ms = 25,
                    },
                },
            },
        }
        package.loaded["vault.core.state"] = {
            get_global_key = function()
                return nil
            end,
            set_global_key = function() end,
        }

        local prewarm = require(MODULE)
        assert.is_false(prewarm.schedule())
        assert.is_false(created_timer)
    end)
end)
