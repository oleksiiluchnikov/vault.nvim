local MODULE = "telescope._extensions.vault.pickers.notes"
local COLUMNS_MODULE = "telescope._extensions.vault.pickers.notes.columns"
local DEFAULT_PREP_MODULE = "telescope._extensions.vault.pickers.notes.default_prep"
local PROGRESSIVE_MODULE = "telescope._extensions.vault.pickers.notes.progressive"
local SHARED_PROGRESSIVE_MODULE = "telescope._extensions.vault.pickers.progressive"

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
            telescope_config = package.loaded["telescope.config"],
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
            default_prep = package.loaded[DEFAULT_PREP_MODULE],
            progressive = package.loaded[PROGRESSIVE_MODULE],
            shared_progressive = package.loaded[SHARED_PROGRESSIVE_MODULE],
            notes = package.loaded["vault.notes"],
            scanner = package.loaded["vault.scanner"],
            fzy = package.loaded["telescope.algos.fzy"],
            schedule = vim.schedule,
            uv_new_timer = vim.uv.new_timer,
        }
        package.loaded[MODULE] = nil
        package.loaded[COLUMNS_MODULE] = nil
        package.loaded[DEFAULT_PREP_MODULE] = nil
        package.loaded[PROGRESSIVE_MODULE] = nil
        package.loaded[SHARED_PROGRESSIVE_MODULE] = nil
    end)

    after_each(function()
        package.loaded[MODULE] = originals.module
        package.loaded[COLUMNS_MODULE] = originals.columns_module
        package.loaded["vault.core.state"] = originals.state
        package.loaded["vault.config"] = originals.config
        package.loaded["telescope.config"] = originals.telescope_config
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
        package.loaded[DEFAULT_PREP_MODULE] = originals.default_prep
        package.loaded[PROGRESSIVE_MODULE] = originals.progressive
        package.loaded[SHARED_PROGRESSIVE_MODULE] = originals.shared_progressive
        package.loaded["vault.notes"] = originals.notes
        package.loaded["vault.scanner"] = originals.scanner
        package.loaded["telescope.algos.fzy"] = originals.fzy
        vim.schedule = originals.schedule
        vim.uv.new_timer = originals.uv_new_timer
    end)

    local function stub_deps(config)
        local captured = {
            generic_highlighter_self = nil,
            generic_sorter = nil,
            generic_sorter_calls = 0,
            items = nil,
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
                    local generic_sorter = {
                        state = { prompt_cache = {} },
                    }
                    captured.generic_sorter_calls = captured.generic_sorter_calls + 1
                    generic_sorter.scoring_function = function(_, prompt, line, entry)
                        if config and type(config._generic_score) == "function" then
                            return config._generic_score(prompt, line, entry)
                        end
                        return 1
                    end
                    generic_sorter._init = function(self)
                        self.state.initialized = true
                    end
                    generic_sorter._start = function(self, prompt)
                        self.state.last_prompt = prompt
                    end
                    generic_sorter._finish = function(self, prompt)
                        self.state.finished_prompt = prompt
                    end
                    generic_sorter._destroy = function(self)
                        self.state.destroyed = true
                    end
                    generic_sorter.highlighter = function(self)
                        captured.generic_highlighter_self = self
                        return {}
                    end
                    captured.generic_sorter = generic_sorter
                    return generic_sorter
                end,
            },
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
                    closed = false,
                    kind = "table",
                    results = vim.deepcopy(opts.results),
                    entry_maker = opts.entry_maker,
                }
                captured.finder.close = function(self)
                    self.closed = true
                end
                return captured.finder
            end,
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
                picker_opts._completion_callbacks = {}
                picker_opts.is_done = function()
                    return false
                end
                picker_opts.register_completion_callback = function(self, cb)
                    table.insert(self._completion_callbacks, cb)
                end
                picker_opts.refresh = function(self)
                    captured.refresh_count = captured.refresh_count + 1
                    local callbacks = {}
                    for index, cb in ipairs(self._completion_callbacks or {}) do
                        callbacks[index] = cb
                    end
                    for _, cb in ipairs(callbacks) do
                        cb(self)
                    end
                end
                picker_opts.full_layout_update = function()
                    captured.full_layout_updated = true
                end
                if picker_opts.__hide_previewer and picker_opts.previewer then
                    picker_opts.hidden_previewer = picker_opts.previewer
                    picker_opts.previewer = nil
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
        package.loaded["telescope._extensions.vault.previewers"] = {
            notes = {},
        }
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

        assert.are.equal(8, captured.items[5].width)
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

    it("includes title and paths in static note search text", function()
        local captured = stub_deps()
        local picker = require(MODULE)
        local notes = {
            list = function()
                return { sample_note() }
            end,
        }

        picker({ notes = notes, _wikilinks_map = {} })
        local entry = captured.finder.entry_maker(captured.finder.results[1])

        assert.is_truthy(entry.ordinal:find("topic", 1, true))
        assert.is_truthy(entry.ordinal:find("readable title", 1, true))
        assert.is_truthy(entry.ordinal:find("topic%.md"))
        assert.is_truthy(entry.ordinal:find("/tmp/very/deeply", 1, true))
    end)

    it("reuses cached default note prep between openings", function()
        stub_deps({ root = "/tmp/vault" })

        local scanner_calls = 0
        local notes_from_paths_calls = 0
        local stats_collect_calls = 0
        local prepared = nil
        local scheduled = {}

        vim.schedule = function(fn)
            scheduled[#scheduled + 1] = fn
        end

        package.loaded[DEFAULT_PREP_MODULE] = {
            get_or_prepare = function()
                if prepared == nil then
                    scanner_calls = scanner_calls + 1
                    notes_from_paths_calls = notes_from_paths_calls + 1
                    stats_collect_calls = stats_collect_calls + 1
                    prepared = {
                        link_counts = {
                            [sample_note().data.slug] = {
                                outlinks = 0,
                                inlinks = 0,
                                dangling = 0,
                            },
                        },
                        notes = {
                            list = function()
                                return { sample_note() }
                            end,
                        },
                        results = { sample_note() },
                    }
                end

                return prepared
            end,
        }

        local picker = require(MODULE)
        local first = picker({})
        local second = picker({})

        first.attach_mappings(1, function() end)
        second.attach_mappings(2, function() end)
        scheduled[1]()
        scheduled[2]()

        assert.are.equal(1, scanner_calls)
        assert.are.equal(1, notes_from_paths_calls)
        assert.are.equal(1, stats_collect_calls)
    end)

    it("defers default prep until Telescope attach mappings run", function()
        local captured = stub_deps({ root = "/tmp/vault" })
        local prepare_calls = 0
        local ready_event = nil
        local scheduled = nil

        vim.schedule = function(fn)
            scheduled = fn
        end

        package.loaded[DEFAULT_PREP_MODULE] = {
            get_or_prepare = function()
                prepare_calls = prepare_calls + 1
                return {
                    link_counts = {
                        [sample_note().data.slug] = {
                            outlinks = 0,
                            inlinks = 0,
                            dangling = 0,
                        },
                    },
                    notes = {
                        list = function()
                            return { sample_note() }
                        end,
                    },
                    results = { sample_note() },
                }
            end,
        }

        local picker = require(MODULE)({
            _on_ready = function(event)
                ready_event = event
            end,
        })

        assert.are.equal("dynamic", captured.finder.kind)
        assert.are.equal(0, prepare_calls)
        assert.is_not_nil(picker.previewer)

        picker.attach_mappings(1, function() end)
        assert.is_function(scheduled)

        scheduled()

        assert.are.equal(1, prepare_calls)
        assert.are.equal(1, captured.refresh_count)
        assert.are.same({ result_count = 1, state = "ready" }, ready_event)
    end)

    it("matches relpath in dynamic note search", function()
        local captured = stub_deps({ root = "/tmp/vault" })
        local scheduled = {}

        vim.schedule = function(fn)
            scheduled[#scheduled + 1] = fn
        end

        package.loaded[DEFAULT_PREP_MODULE] = {
            get_or_prepare = function()
                return {
                    link_counts = {
                        [sample_note().data.slug] = { outlinks = 0, inlinks = 0, dangling = 0 },
                    },
                    notes = {
                        list = function()
                            return { sample_note() }
                        end,
                    },
                    results = { sample_note() },
                }
            end,
        }

        local picker = require(MODULE)({})
        picker.attach_mappings(1, function() end)
        scheduled[1]()

        local filtered = captured.finder.fn("topic.md")
        assert.are.equal(1, #filtered)
        assert.are.equal(sample_note().data.slug, filtered[1].data.slug)
    end)

    it("keeps dynamic note fuzzy matches for single-word prompts", function()
        local captured = stub_deps({ root = "/tmp/vault" })
        local scheduled = {}
        local note = sample_note()

        package.loaded["telescope.algos.fzy"] = {
            has_match = function(prompt, line)
                assert.are.equal("tpc", prompt)
                return line:find("topic", 1, true) ~= nil
            end,
        }

        vim.schedule = function(fn)
            scheduled[#scheduled + 1] = fn
        end

        package.loaded[DEFAULT_PREP_MODULE] = {
            get_or_prepare = function()
                return {
                    link_counts = {
                        [note.data.slug] = { outlinks = 0, inlinks = 0, dangling = 0 },
                    },
                    notes = {
                        list = function()
                            return { note }
                        end,
                    },
                    results = { note },
                }
            end,
        }

        local picker = require(MODULE)({})
        picker.attach_mappings(1, function() end)
        scheduled[1]()

        local filtered = captured.finder.fn("tpc")
        assert.are.equal(1, #filtered)
        assert.are.equal(note.data.slug, filtered[1].data.slug)
    end)

    it("keeps dynamic note matches strict for multi-word prompts", function()
        local captured = stub_deps({
            root = "/tmp/vault",
            _generic_score = function()
                return -1
            end,
        })
        local scheduled = {}
        local note_a = sample_note()
        local note_b = sample_note()
        local query = "bases databases views"

        note_a.data.slug = "architecture-philosophy"
        note_a.data.path = "/tmp/vault/architecture-philosophy.md"
        note_a.data.relpath = "architecture-philosophy.md"
        note_a.data.title = "Architecture philosophy"
        note_a.data.content = "Bases aren't databases. Vault views."

        note_b.data.slug = "false-positive"
        note_b.data.path = "/tmp/vault/false-positive.md"
        note_b.data.relpath = "false-positive.md"
        note_b.data.title = "False positive"
        note_b.data.content = "b a s e s x d a t a b a s e s x v i e w s"

        package.loaded["telescope.algos.fzy"] = {
            has_match = function(prompt, line)
                local needle_index = 1
                if prompt == "" then
                    return true
                end
                for i = 1, #line do
                    if line:sub(i, i) == prompt:sub(needle_index, needle_index) then
                        needle_index = needle_index + 1
                        if needle_index > #prompt then
                            return true
                        end
                    end
                end
                return false
            end,
        }

        vim.schedule = function(fn)
            scheduled[#scheduled + 1] = fn
        end

        package.loaded[DEFAULT_PREP_MODULE] = {
            get_or_prepare = function()
                return {
                    link_counts = {
                        [note_a.data.slug] = { outlinks = 0, inlinks = 0, dangling = 0 },
                        [note_b.data.slug] = { outlinks = 0, inlinks = 0, dangling = 0 },
                    },
                    notes = {
                        list = function()
                            return { note_a, note_b }
                        end,
                    },
                    results = { note_a, note_b },
                }
            end,
        }

        local picker = require(MODULE)({})
        picker.attach_mappings(1, function() end)
        scheduled[1]()

        local filtered = captured.finder.fn(query)
        assert.are.equal(1, #filtered)
        assert.are.equal(note_a.data.slug, filtered[1].data.slug)

        local entry = captured.finder.entry_maker(filtered[1])
        local score = captured.picker.sorter.scoring_function(
            captured.picker.sorter,
            query,
            entry.ordinal,
            entry
        )
        assert.is_true(score > 0)
    end)

    it("shows matched over total in the dynamic status text", function()
        local captured = stub_deps({ root = "/tmp/vault" })
        local scheduled = {}
        local timer_callback = nil
        local note_a = sample_note()
        local note_b = sample_note()

        note_a.data.slug = "alpha note"
        note_a.data.path = "/tmp/vault/alpha.md"
        note_a.data.relpath = "alpha.md"
        note_a.data.title = "Alpha"

        note_b.data.slug = "beta note"
        note_b.data.path = "/tmp/vault/beta.md"
        note_b.data.relpath = "beta.md"
        note_b.data.title = "Beta"

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

        package.loaded[DEFAULT_PREP_MODULE] = {
            get_or_prepare = function()
                return {
                    link_counts = {
                        [note_a.data.slug] = { outlinks = 0, inlinks = 0, dangling = 0 },
                        [note_b.data.slug] = { outlinks = 0, inlinks = 0, dangling = 0 },
                    },
                    notes = {
                        list = function()
                            return { note_a, note_b }
                        end,
                    },
                    results = { note_a, note_b },
                }
            end,
        }

        local picker = require(MODULE)({})
        picker.attach_mappings(1, function() end)
        scheduled[1]()

        assert.are.equal(" 2 / 2", captured.picker.get_status_text())

        captured.finder.fn("beta")

        assert.are.equal(" ... / 2", captured.picker.get_status_text())

        timer_callback()
        scheduled[2]()

        assert.are.equal(" 1 / 2", captured.picker.get_status_text())
    end)

    it("caps displayed matches while keeping the full matched count", function()
        local captured = stub_deps({ root = "/tmp/vault" })
        local scheduled = {}
        local timer_callback = nil
        local note_a = sample_note()
        local note_b = sample_note()
        local note_c = sample_note()

        note_a.data.slug = "alpha note"
        note_a.data.path = "/tmp/vault/alpha.md"
        note_a.data.relpath = "alpha.md"
        note_a.data.title = "Alpha"

        note_b.data.slug = "beta note"
        note_b.data.path = "/tmp/vault/beta.md"
        note_b.data.relpath = "beta.md"
        note_b.data.title = "Beta"

        note_c.data.slug = "gamma"
        note_c.data.path = "/tmp/vault/gamma.md"
        note_c.data.relpath = "gamma.md"
        note_c.data.title = "Gamma"

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

        package.loaded[DEFAULT_PREP_MODULE] = {
            get_or_prepare = function()
                return {
                    link_counts = {
                        [note_a.data.slug] = { outlinks = 0, inlinks = 0, dangling = 0 },
                        [note_b.data.slug] = { outlinks = 0, inlinks = 0, dangling = 0 },
                        [note_c.data.slug] = { outlinks = 0, inlinks = 0, dangling = 0 },
                    },
                    notes = {
                        list = function()
                            return { note_a, note_b, note_c }
                        end,
                    },
                    results = { note_a, note_b, note_c },
                }
            end,
        }

        local picker = require(MODULE)({ prompt_result_limit = 1 })
        picker.attach_mappings(1, function() end)
        scheduled[1]()

        local filtered = captured.finder.fn("note")
        assert.are.equal(1, #filtered)
        assert.are.equal("alpha note", filtered[1].data.slug)

        assert.are.equal(" ... / 3", captured.picker.get_status_text())

        timer_callback()
        scheduled[2]()

        assert.are.equal(" 2 / 3", captured.picker.get_status_text())
    end)

    it("keeps the first regex character in static note filtering", function()
        local captured = stub_deps()
        package.loaded["telescope._extensions.vault.on_input_filter"] = nil
        package.loaded[MODULE] = nil

        local note_a = sample_note()
        local note_b = sample_note()
        note_a.data.slug = "abc-note"
        note_a.data.path = "/tmp/vault/abc-note.md"
        note_a.data.relpath = "abc-note.md"
        note_b.data.slug = "bc-only"
        note_b.data.path = "/tmp/vault/bc-only.md"
        note_b.data.relpath = "bc-only.md"

        require(MODULE)({
            notes = {
                list = function()
                    return { note_a, note_b }
                end,
            },
            _wikilinks_map = {},
        })

        local result = captured.picker.on_input_filter_cb("abc/")

        assert.are.equal("", result.prompt)
        assert.are.equal(1, #captured.finder.results)
        assert.are.equal("abc-note", captured.finder.results[1].data.slug)
    end)

    it("supports negative regex in static note filtering", function()
        local captured = stub_deps()
        package.loaded["telescope._extensions.vault.on_input_filter"] = nil
        package.loaded[MODULE] = nil

        local note_a = sample_note()
        local note_b = sample_note()
        note_a.data.slug = "abc-note"
        note_a.data.path = "/tmp/vault/abc-note.md"
        note_a.data.relpath = "abc-note.md"
        note_b.data.slug = "keep-note"
        note_b.data.path = "/tmp/vault/keep-note.md"
        note_b.data.relpath = "keep-note.md"

        require(MODULE)({
            notes = {
                list = function()
                    return { note_a, note_b }
                end,
            },
            _wikilinks_map = {},
        })

        local result = captured.picker.on_input_filter_cb("-abc/")

        assert.are.equal("", result.prompt)
        assert.are.equal(1, #captured.finder.results)
        assert.are.equal("keep-note", captured.finder.results[1].data.slug)
    end)

    it("applies each static regex filter against the original note set", function()
        local captured = stub_deps()
        package.loaded["telescope._extensions.vault.on_input_filter"] = nil
        package.loaded[MODULE] = nil

        local note_a = sample_note()
        local note_b = sample_note()
        note_a.data.slug = "alpha"
        note_a.data.path = "/tmp/vault/alpha.md"
        note_a.data.relpath = "alpha.md"
        note_b.data.slug = "beta"
        note_b.data.path = "/tmp/vault/beta.md"
        note_b.data.relpath = "beta.md"

        require(MODULE)({
            notes = {
                list = function()
                    return { note_a, note_b }
                end,
            },
            _wikilinks_map = {},
        })

        captured.picker.on_input_filter_cb("alpha/")
        captured.picker.on_input_filter_cb("beta/")

        assert.are.equal(1, #captured.finder.results)
        assert.are.equal("beta", captured.finder.results[1].data.slug)
    end)

    it("uses the same searchable fields for static and dynamic regex note filtering", function()
        local captured = stub_deps({ root = "/tmp/vault" })
        package.loaded["telescope._extensions.vault.on_input_filter"] = nil
        package.loaded[MODULE] = nil

        local scheduled = {}
        vim.schedule = function(fn)
            scheduled[#scheduled + 1] = fn
        end

        local note_a = sample_note()
        local note_b = sample_note()
        note_a.data.slug = "title-only-slug"
        note_a.data.title = "Needle Title"
        note_a.data.path = "/tmp/vault/title-only-slug.md"
        note_a.data.relpath = "title-only-slug.md"
        note_b.data.slug = "other"
        note_b.data.title = "Other"
        note_b.data.path = "/tmp/vault/other.md"
        note_b.data.relpath = "other.md"

        package.loaded[DEFAULT_PREP_MODULE] = {
            get_or_prepare = function()
                return {
                    link_counts = {
                        [note_a.data.slug] = { outlinks = 0, inlinks = 0, dangling = 0 },
                        [note_b.data.slug] = { outlinks = 0, inlinks = 0, dangling = 0 },
                    },
                    notes = {
                        list = function()
                            return { note_a, note_b }
                        end,
                    },
                    results = { note_a, note_b },
                }
            end,
        }

        local dynamic_picker = require(MODULE)({})
        dynamic_picker.attach_mappings(1, function() end)
        scheduled[1]()
        local dynamic_matches = captured.finder.fn("Needle/")

        package.loaded[MODULE] = nil
        local static_captured = stub_deps()
        package.loaded["telescope._extensions.vault.on_input_filter"] = nil
        require(MODULE)({
            notes = {
                list = function()
                    return { note_a, note_b }
                end,
            },
            _wikilinks_map = {},
        })
        static_captured.picker.on_input_filter_cb("Needle/")

        assert.are.equal(1, #dynamic_matches)
        assert.are.equal(1, #static_captured.finder.results)
        assert.are.equal(dynamic_matches[1].data.slug, static_captured.finder.results[1].data.slug)
    end)

    it("orders exact filename stem matches before partial stem matches", function()
        local captured = stub_deps()
        local picker = require(MODULE)
        local exact = sample_note()
        local partial = sample_note()
        exact.data.path = "/tmp/vault/topic.md"
        exact.data.slug = "topic"
        partial.data.path = "/tmp/vault/topic-extra.md"
        partial.data.slug = "topic-extra"

        picker({
            notes = {
                list = function()
                    return { exact, partial }
                end,
            },
            _wikilinks_map = {},
        })
        local exact_entry = captured.finder.entry_maker(exact)
        local partial_entry = captured.finder.entry_maker(partial)
        local sorter = captured.picker.sorter

        local exact_score =
            sorter.scoring_function(sorter, "topic", exact_entry.ordinal, exact_entry)
        local partial_score =
            sorter.scoring_function(sorter, "topic", partial_entry.ordinal, partial_entry)

        assert.is_true(exact_score < partial_score)
    end)

    it("uses Telescope generic sorter when configured", function()
        local captured = stub_deps()
        local picker = require(MODULE)
        local notes = {
            list = function()
                return { sample_note() }
            end,
        }

        picker({ notes = notes, _wikilinks_map = {} })

        assert.are.equal(1, captured.generic_sorter_calls)
    end)

    it("calls the generic sorter highlighter with the generic sorter state", function()
        local captured = stub_deps()
        local picker = require(MODULE)
        local notes = {
            list = function()
                return { sample_note() }
            end,
        }

        picker({ notes = notes, _wikilinks_map = {} })

        assert.has_no.errors(function()
            captured.picker.sorter.highlighter(captured.picker.sorter, "topic", "topic")
        end)
        assert.are.same(captured.generic_sorter, captured.generic_highlighter_self)
    end)

    it("delegates sorter lifecycle hooks to the generic sorter", function()
        local captured = stub_deps()
        local picker = require(MODULE)
        local notes = {
            list = function()
                return { sample_note() }
            end,
        }

        picker({ notes = notes, _wikilinks_map = {} })

        captured.picker.sorter.init()
        captured.picker.sorter.start(nil, "ab")
        captured.picker.sorter.finish(nil, "ab")
        captured.picker.sorter.destroy()

        assert.is_true(captured.generic_sorter.state.initialized)
        assert.are.equal("ab", captured.generic_sorter.state.last_prompt)
        assert.are.equal("ab", captured.generic_sorter.state.finished_prompt)
        assert.is_true(captured.generic_sorter.state.destroyed)
    end)
end)
