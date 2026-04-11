local MODULE = "telescope._extensions.vault.pickers.properties"

describe("vault properties picker", function()
    local originals

    before_each(function()
        originals = {
            module = package.loaded[MODULE],
            state = package.loaded["vault.core.state"],
            config = package.loaded["vault.config"],
            finders = package.loaded["telescope.finders"],
            pickers = package.loaded["telescope.pickers"],
            sorters = package.loaded["telescope.sorters"],
            mappings = package.loaded["telescope._extensions.vault.mappings"],
            highlights = package.loaded["telescope._extensions.vault.highlights"],
            layouts = package.loaded["telescope._extensions.vault.layouts"],
            previewers = package.loaded["telescope._extensions.vault.previewers"],
            filter = package.loaded["telescope._extensions.vault.on_input_filter"],
            entry_maker = package.loaded["telescope._extensions.vault.entry_maker"],
            properties = package.loaded["vault.properties"],
        }
        package.loaded[MODULE] = nil
    end)

    after_each(function()
        package.loaded[MODULE] = originals.module
        package.loaded["vault.core.state"] = originals.state
        package.loaded["vault.config"] = originals.config
        package.loaded["telescope.finders"] = originals.finders
        package.loaded["telescope.pickers"] = originals.pickers
        package.loaded["telescope.sorters"] = originals.sorters
        package.loaded["telescope._extensions.vault.mappings"] = originals.mappings
        package.loaded["telescope._extensions.vault.highlights"] = originals.highlights
        package.loaded["telescope._extensions.vault.layouts"] = originals.layouts
        package.loaded["telescope._extensions.vault.previewers"] = originals.previewers
        package.loaded["telescope._extensions.vault.on_input_filter"] = originals.filter
        package.loaded["telescope._extensions.vault.entry_maker"] = originals.entry_maker
        package.loaded["vault.properties"] = originals.properties
    end)

    it("reuses cached default properties between openings", function()
        local state_store = {}
        local captured_finder
        local properties_ctor_calls = 0

        package.loaded["vault.core.state"] = {
            get_global_key = function(key)
                return state_store[key]
            end,
            set_global_key = function(key, value)
                state_store[key] = value
            end,
        }
        package.loaded["vault.config"] = {
            options = { root = "/tmp/vault" },
        }
        package.loaded["telescope.finders"] = {
            new_table = function(opts)
                captured_finder = {
                    results = vim.deepcopy(opts.results),
                }
                return captured_finder
            end,
        }
        package.loaded["telescope.pickers"] = {
            new = function(_, picker_opts)
                return picker_opts
            end,
        }
        package.loaded["telescope.sorters"] = {
            get_fzy_sorter = function()
                return function() end
            end,
        }
        package.loaded["telescope._extensions.vault.mappings"] = {
            properties = {},
        }
        package.loaded["telescope._extensions.vault.highlights"] = {
            setup = function()
                return nil
            end,
            make_attach_mappings = function()
                return function()
                    return true
                end
            end,
        }
        package.loaded["telescope._extensions.vault.layouts"] = {
            ui_size = function()
                return 40, 120
            end,
        }
        package.loaded["telescope._extensions.vault.previewers"] = {}
        package.loaded["telescope._extensions.vault.on_input_filter"] = function()
            return function() end
        end
        package.loaded["telescope._extensions.vault.entry_maker"] = {
            counted = function()
                return function() end, function(item)
                    return item
                end
            end,
        }
        package.loaded["vault.properties"] = function()
            properties_ctor_calls = properties_ctor_calls + 1
            local alpha = { data = { count = 5, name = "alpha" } }
            local beta = { data = { count = 2, name = "beta" } }
            return {
                list = function()
                    return { beta, alpha }
                end,
                map = {
                    alpha = alpha,
                    beta = beta,
                },
            }
        end

        local picker = require(MODULE)
        picker({})
        picker({})

        assert.are.equal(1, properties_ctor_calls)
        assert.are.same({ "alpha", "beta" }, {
            captured_finder.results[1].data.name,
            captured_finder.results[2].data.name,
        })
    end)
end)
