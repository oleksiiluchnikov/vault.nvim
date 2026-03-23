local MODULE = "telescope._extensions.vault.pickers.property_values"

describe("vault property values picker", function()
    local originals

    before_each(function()
        originals = {
            module = package.loaded[MODULE],
            state = package.loaded["vault.core.state"],
            entry_display = package.loaded["telescope.pickers.entry_display"],
            finders = package.loaded["telescope.finders"],
            pickers = package.loaded["telescope.pickers"],
            sorters = package.loaded["telescope.sorters"],
            mappings = package.loaded["telescope._extensions.vault.mappings"],
            highlights = package.loaded["telescope._extensions.vault.highlights"],
            layouts = package.loaded["telescope._extensions.vault.layouts"],
            filter = package.loaded["telescope._extensions.vault.on_input_filter"],
        }
        package.loaded[MODULE] = nil
    end)

    after_each(function()
        package.loaded[MODULE] = originals.module
        package.loaded["vault.core.state"] = originals.state
        package.loaded["telescope.pickers.entry_display"] = originals.entry_display
        package.loaded["telescope.finders"] = originals.finders
        package.loaded["telescope.pickers"] = originals.pickers
        package.loaded["telescope.sorters"] = originals.sorters
        package.loaded["telescope._extensions.vault.mappings"] = originals.mappings
        package.loaded["telescope._extensions.vault.highlights"] = originals.highlights
        package.loaded["telescope._extensions.vault.layouts"] = originals.layouts
        package.loaded["telescope._extensions.vault.on_input_filter"] = originals.filter
    end)

    it("sorts values by count before building the finder", function()
        local captured_finder

        package.loaded["vault.core.state"] = {
            set_global_key = function() end,
        }
        package.loaded["telescope.pickers.entry_display"] = {
            create = function()
                return function() return "display" end
            end,
        }
        package.loaded["telescope.finders"] = {
            new_table = function(opts)
                captured_finder = {
                    results = vim.deepcopy(opts.results),
                    entry_maker = opts.entry_maker,
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
            get_fzy_sorter = function() return function() end end,
        }
        package.loaded["telescope._extensions.vault.mappings"] = {
            property_values = {},
        }
        package.loaded["telescope._extensions.vault.highlights"] = {
            setup = function() return nil end,
            make_attach_mappings = function() return function() return true end end,
        }
        package.loaded["telescope._extensions.vault.layouts"] = {
            ui_size = function() return 40, 120 end,
        }
        package.loaded["telescope._extensions.vault.on_input_filter"] = function()
            return function() end
        end

        local picker = require(MODULE)
        picker({
            property_name = "status",
            values = {
                low = { data = { name = "low", type = "text", count = 1 } },
                high = { data = { name = "high", type = "text", count = 5 } },
                medium = { data = { name = "medium", type = "text", count = 3 } },
            },
        })

        assert.are.same({ "high", "medium", "low" }, {
            captured_finder.results[1].data.name,
            captured_finder.results[2].data.name,
            captured_finder.results[3].data.name,
        })
    end)
end)
