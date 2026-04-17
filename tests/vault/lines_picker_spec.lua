local MODULE = "telescope._extensions.vault.pickers.lines"
local PROGRESSIVE_MODULE = "telescope._extensions.vault.pickers.progressive"

local function sample_line(content)
    return {
        data = {
            content = content or "- [ ] alpha note",
            metadata = {},
            tags = {},
            wikilinks = {},
            count = 1,
        },
    }
end

describe("vault lines picker", function()
    local originals

    before_each(function()
        originals = {
            module = package.loaded[MODULE],
            progressive = package.loaded[PROGRESSIVE_MODULE],
            state = package.loaded["vault.core.state"],
            config = package.loaded["vault.config"],
            telescope_config = package.loaded["telescope.config"],
            entry_display = package.loaded["telescope.pickers.entry_display"],
            pickers = package.loaded["telescope.pickers"],
            sorters = package.loaded["telescope.sorters"],
            finders = package.loaded["telescope.finders"],
            log = package.loaded["vault.log"],
            mappings = package.loaded["telescope._extensions.vault.mappings"],
            highlights = package.loaded["telescope._extensions.vault.highlights"],
            layouts = package.loaded["telescope._extensions.vault.layouts"],
            lines = package.loaded["vault.lines"],
            schedule = vim.schedule,
            uv_new_timer = vim.uv.new_timer,
        }
        package.loaded[MODULE] = nil
        package.loaded[PROGRESSIVE_MODULE] = nil
    end)

    after_each(function()
        package.loaded[MODULE] = originals.module
        package.loaded[PROGRESSIVE_MODULE] = originals.progressive
        package.loaded["vault.core.state"] = originals.state
        package.loaded["vault.config"] = originals.config
        package.loaded["telescope.config"] = originals.telescope_config
        package.loaded["telescope.pickers.entry_display"] = originals.entry_display
        package.loaded["telescope.pickers"] = originals.pickers
        package.loaded["telescope.sorters"] = originals.sorters
        package.loaded["telescope.finders"] = originals.finders
        package.loaded["vault.log"] = originals.log
        package.loaded["telescope._extensions.vault.mappings"] = originals.mappings
        package.loaded["telescope._extensions.vault.highlights"] = originals.highlights
        package.loaded["telescope._extensions.vault.layouts"] = originals.layouts
        package.loaded["vault.lines"] = originals.lines
        vim.schedule = originals.schedule
        vim.uv.new_timer = originals.uv_new_timer
    end)

    local function stub_deps(config)
        local captured = {
            finder = nil,
            picker = nil,
            refresh_count = 0,
        }
        local state_store = {}

        package.loaded["vault.core.state"] = {
            get_global_key = function(key)
                return state_store[key]
            end,
            set_global_key = function(key, value)
                state_store[key] = value
            end,
        }
        package.loaded["vault.config"] = {
            options = config or {},
        }
        package.loaded["telescope.config"] = {
            values = {
                generic_sorter = function()
                    return {
                        _destroy = function() end,
                        _finish = function() end,
                        _init = function() end,
                        _start = function() end,
                        scoring_function = function()
                            return 1
                        end,
                        highlighter = function()
                            return {}
                        end,
                    }
                end,
            },
        }
        package.loaded["telescope.pickers.entry_display"] = {
            create = function()
                return function(items)
                    return items
                end
            end,
        }
        package.loaded["telescope.finders"] = {
            new_dynamic = function(opts)
                captured.finder = {
                    entry_maker = opts.entry_maker,
                    fn = opts.fn,
                    kind = "dynamic",
                }
                return captured.finder
            end,
        }
        package.loaded["telescope.pickers"] = {
            new = function(_, picker_opts)
                picker_opts.is_done = function()
                    return false
                end
                picker_opts.refresh = function()
                    captured.refresh_count = captured.refresh_count + 1
                end
                captured.picker = picker_opts
                return picker_opts
            end,
        }
        package.loaded["telescope.sorters"] = {
            get_fzy_sorter = function()
                return {
                    scoring_function = function()
                        return 1
                    end,
                    highlighter = function()
                        return {}
                    end,
                }
            end,
        }
        package.loaded["vault.log"] = {
            scope = function()
                return {
                    info = function() end,
                }
            end,
        }
        package.loaded["telescope._extensions.vault.mappings"] = {
            lines = function()
                return true
            end,
        }
        package.loaded["telescope._extensions.vault.highlights"] = {
            make_attach_mappings = function(mapping_fn)
                return function(prompt_bufnr, map)
                    return mapping_fn(prompt_bufnr, map)
                end
            end,
            setup = function()
                return nil
            end,
        }
        package.loaded["telescope._extensions.vault.layouts"] = {
            ui_size = function()
                return 40, 120
            end,
        }

        return captured
    end

    it("defers line loading until attach mappings run", function()
        local captured = stub_deps({ root = "/tmp/vault" })
        local line_calls = 0
        local scheduled = nil

        vim.schedule = function(fn)
            scheduled = fn
        end
        vim.uv.new_timer = function()
            return {
                close = function() end,
                start = function() end,
                stop = function() end,
            }
        end
        package.loaded["vault.lines"] = function()
            line_calls = line_calls + 1
            return {
                list = function()
                    return { sample_line() }
                end,
            }
        end

        local picker = require(MODULE)({})

        assert.are.equal("dynamic", captured.finder.kind)
        assert.are.equal(0, line_calls)

        picker.attach_mappings(1, function() end)
        scheduled()

        assert.are.equal(1, line_calls)
        assert.are.equal(1, captured.refresh_count)
    end)

    it("caps displayed matches while delaying exact matched count", function()
        local captured = stub_deps({ root = "/tmp/vault" })
        local scheduled = {}
        local timer_callback = nil
        local line_a = sample_line("alpha note")
        local line_b = sample_line("beta note")
        local line_c = sample_line("gamma")

        vim.schedule = function(fn)
            scheduled[#scheduled + 1] = fn
        end
        vim.uv.new_timer = function()
            return {
                close = function() end,
                start = function(_, _, _, cb)
                    timer_callback = cb
                end,
                stop = function() end,
            }
        end
        package.loaded["vault.lines"] = function()
            return {
                list = function()
                    return { line_a, line_b, line_c }
                end,
            }
        end

        local picker = require(MODULE)({ prompt_result_limit = 1 })
        picker.attach_mappings(1, function() end)
        scheduled[1]()

        assert.are.equal(" 3 / 3", captured.picker.get_status_text())

        local filtered = captured.finder.fn("note")
        assert.are.equal(1, #filtered)
        assert.are.equal("alpha note", filtered[1].data.content)
        assert.are.equal(" ... / 3", captured.picker.get_status_text())

        timer_callback()
        scheduled[2]()
        assert.are.equal(" 2 / 3", captured.picker.get_status_text())
    end)
end)
