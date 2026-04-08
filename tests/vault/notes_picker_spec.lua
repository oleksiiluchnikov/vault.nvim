local MODULE = "telescope._extensions.vault.pickers.notes"
local COLUMNS_MODULE = "telescope._extensions.vault.pickers.notes.columns"

---@return table
local function sample_note()
    return {
        data = {
            slug = "very/deeply/nested/directory/with/long/name/topic",
            relpath = "very/deeply/nested/directory/with/long/name/topic.md",
            path = "/tmp/very/deeply/nested/directory/with/long/name/topic.md",
            title = "Readable Title",
            content = "",
            created = "",
        },
    }
end

describe("vault notes picker", function()
    local originals

    before_each(function()
        originals = {
            module = package.loaded[MODULE],
            columns_module = package.loaded[COLUMNS_MODULE],
            state = package.loaded["vault.core.state"],
            config = package.loaded["vault.config"],
            entry_display = package.loaded["telescope.pickers.entry_display"],
            finders = package.loaded["telescope.finders"],
            pickers = package.loaded["telescope.pickers"],
            sorters = package.loaded["telescope.sorters"],
            log = package.loaded["vault.log"],
            previewers = package.loaded["telescope._extensions.vault.previewers"],
            mappings = package.loaded["telescope._extensions.vault.mappings"],
            layouts = package.loaded["telescope._extensions.vault.layouts"],
            highlights = package.loaded["telescope._extensions.vault.highlights"],
            filter = package.loaded["telescope._extensions.vault.on_input_filter"],
            stats = package.loaded["telescope._extensions.vault.pickers.notes.stats"],
        }
        package.loaded[MODULE] = nil
        package.loaded[COLUMNS_MODULE] = nil
    end)

    after_each(function()
        package.loaded[MODULE] = originals.module
        package.loaded[COLUMNS_MODULE] = originals.columns_module
        package.loaded["vault.core.state"] = originals.state
        package.loaded["vault.config"] = originals.config
        package.loaded["telescope.pickers.entry_display"] = originals.entry_display
        package.loaded["telescope.finders"] = originals.finders
        package.loaded["telescope.pickers"] = originals.pickers
        package.loaded["telescope.sorters"] = originals.sorters
        package.loaded["vault.log"] = originals.log
        package.loaded["telescope._extensions.vault.previewers"] = originals.previewers
        package.loaded["telescope._extensions.vault.mappings"] = originals.mappings
        package.loaded["telescope._extensions.vault.layouts"] = originals.layouts
        package.loaded["telescope._extensions.vault.highlights"] = originals.highlights
        package.loaded["telescope._extensions.vault.on_input_filter"] = originals.filter
        package.loaded["telescope._extensions.vault.pickers.notes.stats"] = originals.stats
    end)

    local function stub_deps(config)
        local captured = {
            items = nil,
            finder = nil,
        }

        package.loaded["vault.core.state"] = {
            set_global_key = function() end,
        }
        package.loaded["vault.config"] = {
            options = config or {},
        }
        package.loaded["telescope.pickers.entry_display"] = {
            create = function(opts)
                captured.items = vim.deepcopy(opts.items)
                return function(items)
                    return items
                end
            end,
        }
        package.loaded["telescope.finders"] = {
            new_table = function(opts)
                captured.finder = {
                    results = vim.deepcopy(opts.results),
                    entry_maker = opts.entry_maker,
                }
                return captured.finder
            end,
        }
        package.loaded["telescope.pickers"] = {
            new = function(_, picker_opts)
                return picker_opts
            end,
        }
        package.loaded["telescope.sorters"] = {
            get_fzy_sorter = function()
                return {
                    scoring_function = function()
                        return 1
                    end,
                    highlighter = function() end,
                }
            end,
            new = function(opts)
                return opts
            end,
        }
        package.loaded["vault.log"] = {
            scope = function()
                return { info = function() end }
            end,
        }
        package.loaded["telescope._extensions.vault.previewers"] = {}
        package.loaded["telescope._extensions.vault.mappings"] = {
            notes = {},
        }
        package.loaded["telescope._extensions.vault.layouts"] = {
            ui_size = function()
                return 40, 100
            end,
            notes = function()
                return {
                    layout_config = {
                        width = 96,
                        preview_width = 0.4,
                    },
                }
            end,
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
        package.loaded["telescope._extensions.vault.on_input_filter"] = function()
            return function() end
        end
        package.loaded["telescope._extensions.vault.pickers.notes.stats"] = {
            collect = function()
                return {
                    [sample_note().data.slug] = {
                        outlinks = 0,
                        inlinks = 0,
                        dangling = 0,
                    },
                }
            end,
        }

        return captured
    end

    it("caps the directory column width in the default layout", function()
        local captured = stub_deps()
        local picker = require(MODULE)
        local notes = {
            list = function()
                return { sample_note() }
            end,
        }

        picker({ notes = notes, _wikilinks_map = {} })
        local entry = captured.finder.entry_maker(captured.finder.results[1])
        entry.display(entry)

        assert.are.equal(24, captured.items[5].width)
    end)

    it("uses globally configured note columns", function()
        local captured = stub_deps({
            telescope = {
                notes = {
                    columns = {
                        { key = "directory", max_width = 10 },
                        { key = "slug", flex = 1, min_width = 10 },
                    },
                },
            },
        })
        local picker = require(MODULE)
        local notes = {
            list = function()
                return { sample_note() }
            end,
        }

        picker({ notes = notes, _wikilinks_map = {} })
        local entry = captured.finder.entry_maker(captured.finder.results[1])
        local cells = entry.display(entry)

        assert.are.equal(2, #captured.items)
        assert.are.equal(10, captured.items[1].width)
        assert.are.equal("very/deeply/nested/directory/with/long/name", cells[1][1])
        assert.are.equal(sample_note().data.slug, cells[2][1])
    end)

    it("prefers per-picker columns over global config", function()
        local captured = stub_deps({
            telescope = {
                notes = {
                    columns = { "directory", "slug" },
                },
            },
        })
        local picker = require(MODULE)
        local notes = {
            list = function()
                return { sample_note() }
            end,
        }

        picker({
            notes = notes,
            _wikilinks_map = {},
            columns = { "title" },
        })
        local entry = captured.finder.entry_maker(captured.finder.results[1])
        local cells = entry.display(entry)

        assert.are.equal(1, #captured.items)
        assert.are.equal("Readable Title", cells[1][1])
    end)
end)
