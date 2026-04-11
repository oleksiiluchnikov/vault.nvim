local MODULE = "vault.prewarm"

describe("vault prewarm", function()
    local originals

    before_each(function()
        originals = {
            module = package.loaded[MODULE],
            config = package.loaded["vault.config"],
            state = package.loaded["vault.core.state"],
            prep = package.loaded["telescope._extensions.vault.pickers.notes.default_prep"],
            schedule = vim.schedule,
            uv = vim.uv,
        }
        package.loaded[MODULE] = nil
    end)

    after_each(function()
        package.loaded[MODULE] = originals.module
        package.loaded["vault.config"] = originals.config
        package.loaded["vault.core.state"] = originals.state
        package.loaded["telescope._extensions.vault.pickers.notes.default_prep"] = originals.prep
        vim.schedule = originals.schedule
        vim.uv = originals.uv
        vim.env.VAULT_TEST_DISABLE_PREWARM = "1"
    end)

    it("schedules and runs the idle notes prewarm once", function()
        local state_store = {}
        local started_delay = nil
        local prepare_calls = 0
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
        package.loaded["telescope._extensions.vault.pickers.notes.default_prep"] = {
            get_or_prepare = function()
                prepare_calls = prepare_calls + 1
            end,
        }

        local prewarm = require(MODULE)
        assert.is_true(prewarm.schedule_notes())
        assert.is_true(prewarm.schedule_notes())
        assert.is_not_nil(timer_callback)

        timer_callback()

        assert.are.equal(25, started_delay)
        assert.are.equal(1, prepare_calls)
    end)

    it("does not schedule when notes prewarm is disabled", function()
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
        assert.is_false(prewarm.schedule_notes())
        assert.is_false(created_timer)
    end)
end)
