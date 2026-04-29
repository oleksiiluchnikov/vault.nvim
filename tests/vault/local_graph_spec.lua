local MODULE = "vault.ui.local_graph"

describe("vault local graph", function()
    local originals

    before_each(function()
        originals = {
            module = package.loaded[MODULE],
            config = package.loaded["vault.config"],
            link_index = package.loaded["vault.notes.link_index"],
            create = package.loaded["vault.notes.create"],
            scanner = package.loaded["vault.scanner"],
            note = package.loaded["vault.notes.note"],
        }

        package.loaded[MODULE] = nil
        package.loaded["vault.config"] = {
            options = {
                views = {
                    local_graph = {
                        enabled = true,
                        width = 40,
                    },
                },
            },
        }
    end)

    after_each(function()
        for _, win in ipairs(vim.api.nvim_list_wins()) do
            local buf = vim.api.nvim_win_get_buf(win)
            if
                vim.api.nvim_buf_is_valid(buf)
                and vim.api.nvim_buf_get_name(buf):match("^vault://local%-graph/")
            then
                pcall(vim.api.nvim_win_close, win, true)
            end
        end

        package.loaded[MODULE] = originals.module
        package.loaded["vault.config"] = originals.config
        package.loaded["vault.notes.link_index"] = originals.link_index
        package.loaded["vault.notes.create"] = originals.create
        package.loaded["vault.scanner"] = originals.scanner
        package.loaded["vault.notes.note"] = originals.note
    end)

    it("renders backlinks, outgoing links, and unresolved links", function()
        package.loaded["vault.notes.link_index"] = {
            get = function()
                return {
                    paths = {
                        current = { title = "Current Note", path = "/tmp/current.md" },
                        source = { title = "Source Note", path = "/tmp/source.md" },
                        target = { title = "Target Note", path = "/tmp/target.md" },
                    },
                    outlinks_by_source = {
                        current = {
                            target = { data = { target = "target" } },
                            missing = { data = { slug = "missing" } },
                        },
                    },
                    inlinks_by_target = {
                        current = {
                            source = true,
                        },
                    },
                }
            end,
        }

        local graph = require(MODULE)
        graph.open({ data = { slug = "current" } }, { enter = true })

        local buf = vim.api.nvim_get_current_buf()
        local lines = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")

        assert.matches("Local Graph", lines, nil, true)
        assert.matches("out 1  in 1  unresolved 1", lines, nil, true)
        assert.matches("Source No", lines, nil, true)
        assert.matches("Current Note", lines, nil, true)
        assert.matches("Target No", lines, nil, true)
        assert.matches("missing ?", lines, nil, true)
    end)

    it("creates unresolved link notes when opened", function()
        local created_slug
        local invalidated = false
        local edited_path

        package.loaded["vault.notes.link_index"] = {
            get = function()
                return {
                    paths = {
                        current = { title = "Current Note", path = "/tmp/current.md" },
                    },
                    outlinks_by_source = {
                        current = {
                            missing = { data = { slug = "missing" } },
                        },
                    },
                    inlinks_by_target = {},
                }
            end,
        }
        package.loaded["vault.notes.create"] = {
            create = function(slug, opts)
                created_slug = slug
                assert.are.same({ open = false }, opts)
                return "/tmp/missing.md"
            end,
        }
        package.loaded["vault.scanner"] = {
            invalidate_notes_cache = function()
                invalidated = true
            end,
        }
        package.loaded["vault.notes.note"] = function(path)
            edited_path = path
            return { data = { slug = "missing", path = path } }
        end

        local source_buf = vim.api.nvim_create_buf(false, true)
        vim.api.nvim_set_current_buf(source_buf)

        local graph = require(MODULE)
        graph.open({ data = { slug = "current" } }, { enter = true })

        local buf = vim.api.nvim_get_current_buf()
        local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
        for row, line in ipairs(lines) do
            if line:find("missing", 1, true) then
                vim.api.nvim_win_set_cursor(0, { row, #line - 1 })
                break
            end
        end

        local cr = vim.api.nvim_replace_termcodes("<CR>", true, false, true)
        vim.api.nvim_feedkeys(cr, "x", false)

        assert.are.equal("missing", created_slug)
        assert.is_true(invalidated)
        assert.are.equal("/tmp/missing.md", edited_path)

        pcall(vim.api.nvim_buf_delete, source_buf, { force = true })
    end)
end)
