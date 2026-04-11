local MODULE = "telescope._extensions.vault.pickers.wikilinks"

describe("vault wikilinks picker", function()
    local originals

    before_each(function()
        originals = {
            module = package.loaded[MODULE],
            state = package.loaded["vault.core.state"],
            config = package.loaded["vault.config"],
            entry_display = package.loaded["telescope.pickers.entry_display"],
            finders = package.loaded["telescope.finders"],
            pickers = package.loaded["telescope.pickers"],
            sorters = package.loaded["telescope.sorters"],
            previewers = package.loaded["telescope._extensions.vault.previewers"],
            layouts = package.loaded["telescope._extensions.vault.layouts"],
            highlights = package.loaded["telescope._extensions.vault.highlights"],
            filter = package.loaded["telescope._extensions.vault.on_input_filter"],
            utils = package.loaded["vault.utils"],
            wikilinks = package.loaded["vault.wikilinks"],
            actions = package.loaded["telescope._extensions.vault.pickers.wikilinks.actions"],
        }
        package.loaded[MODULE] = nil
    end)

    after_each(function()
        package.loaded[MODULE] = originals.module
        package.loaded["vault.core.state"] = originals.state
        package.loaded["vault.config"] = originals.config
        package.loaded["telescope.pickers.entry_display"] = originals.entry_display
        package.loaded["telescope.finders"] = originals.finders
        package.loaded["telescope.pickers"] = originals.pickers
        package.loaded["telescope.sorters"] = originals.sorters
        package.loaded["telescope._extensions.vault.previewers"] = originals.previewers
        package.loaded["telescope._extensions.vault.layouts"] = originals.layouts
        package.loaded["telescope._extensions.vault.highlights"] = originals.highlights
        package.loaded["telescope._extensions.vault.on_input_filter"] = originals.filter
        package.loaded["vault.utils"] = originals.utils
        package.loaded["vault.wikilinks"] = originals.wikilinks
        package.loaded["telescope._extensions.vault.pickers.wikilinks.actions"] = originals.actions
    end)

    it("caches default results and avoids disk resolution checks during build", function()
        local state_store = {}
        local captured_finder
        local wikilinks_ctor_calls = 0
        local resolved_on_disk_calls = 0

        local resolved = {
            data = {
                slug = "alpha",
                target = "alpha",
                sources = { ["source-a"] = true },
                context = "resolved context",
            },
            is_resolved_on_disk = function()
                resolved_on_disk_calls = resolved_on_disk_calls + 1
                return true
            end,
        }
        local unresolved = {
            data = {
                slug = "beta",
                target = nil,
                sources = { ["source-b"] = true },
                context = "unresolved context",
            },
            is_resolved_on_disk = function()
                resolved_on_disk_calls = resolved_on_disk_calls + 1
                return false
            end,
        }

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
        package.loaded["telescope.pickers.entry_display"] = {
            create = function()
                return function(items)
                    return items
                end
            end,
        }
        package.loaded["telescope.finders"] = {
            new_table = function(opts)
                captured_finder = {
                    entry_maker = opts.entry_maker,
                    results = opts.results,
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
            get_generic_fuzzy_sorter = function()
                return function() end
            end,
        }
        package.loaded["telescope._extensions.vault.previewers"] = {}
        package.loaded["telescope._extensions.vault.layouts"] = {
            ui_size = function()
                return 40, 120
            end,
        }
        package.loaded["telescope._extensions.vault.highlights"] = {
            setup = function()
                return nil
            end,
            cleanup = function() end,
        }
        package.loaded["telescope._extensions.vault.on_input_filter"] = function()
            return function() end
        end
        package.loaded["vault.utils"] = {
            slug_to_path = function(slug)
                return "/tmp/" .. slug .. ".md"
            end,
        }
        package.loaded["vault.wikilinks"] = function()
            wikilinks_ctor_calls = wikilinks_ctor_calls + 1
            return {
                list = function()
                    return { unresolved, resolved }
                end,
            }
        end
        package.loaded["telescope._extensions.vault.pickers.wikilinks.actions"] = {
            make_batch_create = function()
                return function() end
            end,
            make_batch_resolve = function()
                return function() end
            end,
            make_enter = function()
                return function() end
            end,
            make_merge = function()
                return function() end
            end,
            make_resolve = function()
                return function() end
            end,
        }

        local picker = require(MODULE)
        picker({})
        local entry = captured_finder.entry_maker(captured_finder.results[1])
        entry.display(entry)
        picker({})

        assert.are.equal(1, wikilinks_ctor_calls)
        assert.are.equal(0, resolved_on_disk_calls)
        assert.are.equal("alpha", captured_finder.results[1].data.slug)
        assert.are.equal("beta", captured_finder.results[2].data.slug)
    end)
end)
