local root_cwd = vim.fn.getcwd()
local fixture_root = root_cwd .. "/tests/tmp_property_value_rename_vault"

local function rm_rf(path)
    if vim.fn.isdirectory(path) == 1 then
        vim.fn.delete(path, "rf")
    elseif vim.fn.filereadable(path) == 1 then
        vim.fn.delete(path)
    end
end

local function write(path, lines)
    local dir = vim.fn.fnamemodify(path, ":h")
    vim.fn.mkdir(dir, "p")
    vim.fn.writefile(lines, path)
end

local function clear_state()
    package.loaded["vault"] = nil
    package.loaded["vault.properties"] = nil
    package.loaded["vault.notes"] = nil
    package.loaded["telescope._extensions.vault.actions"] = nil
    require("vault.core.state").global = {}
end

local function with_actions_stubs(fn)
    local originals = {
        actions_state = package.loaded["telescope.actions.state"],
        actions = package.loaded["telescope.actions"],
        utils = package.loaded["telescope._extensions.vault.utils"],
        highlights = package.loaded["vault.highlights"],
        popup = package.loaded["nui.popup"],
        event = package.loaded["nui.utils.autocmd"],
    }

    package.loaded["telescope.actions.state"] = {}
    package.loaded["telescope.actions"] = { close = function() end }
    package.loaded["telescope._extensions.vault.utils"] = {
        get_picker_selection = function()
            return nil, nil, {}
        end,
    }
    package.loaded["vault.highlights"] = { detach = function() end }
    package.loaded["nui.popup"] = function()
        return {}
    end
    package.loaded["nui.utils.autocmd"] = { event = {} }

    local ok, err = pcall(fn)

    package.loaded["telescope.actions.state"] = originals.actions_state
    package.loaded["telescope.actions"] = originals.actions
    package.loaded["telescope._extensions.vault.utils"] = originals.utils
    package.loaded["vault.highlights"] = originals.highlights
    package.loaded["nui.popup"] = originals.popup
    package.loaded["nui.utils.autocmd"] = originals.event

    if not ok then
        error(err)
    end
end

describe("property value rename", function()
    before_each(function()
        rm_rf(fixture_root)
        vim.fn.mkdir(fixture_root, "p")
        write(fixture_root .. "/one.md", {
            "---",
            "status: todo",
            "---",
            "# one",
        })
        write(fixture_root .. "/two.md", {
            "---",
            "status: todo",
            "---",
            "# two",
        })

        require("vault").setup({
            root = fixture_root,
            ext = ".md",
            features = {
                commands = true,
                watcher = false,
            },
        })
        clear_state()
    end)

    after_each(function()
        rm_rf(fixture_root)
        clear_state()
    end)

    it("renames a property value across all matching notes", function()
        local properties = require("vault.properties")()
        local status = properties.map.status
        local todo = status.data.values.todo
        with_actions_stubs(function()
            package.loaded["telescope._extensions.vault.actions"] = nil
            local actions = require("telescope._extensions.vault.actions")

            actions._rename_property_values("status", {
                { value = todo },
            }, {
                "'[[Status - Todo]]'",
            })
        end)

        local one = vim.fn.readfile(fixture_root .. "/one.md")
        local two = vim.fn.readfile(fixture_root .. "/two.md")
        assert.are.equal("status: '[[Status - Todo]]'", one[2])
        assert.are.equal("status: '[[Status - Todo]]'", two[2])
    end)

    it("normalizes boolean line maps into occurrence objects", function()
        with_actions_stubs(function()
            package.loaded["telescope._extensions.vault.actions"] = nil
            local actions = require("telescope._extensions.vault.actions")
            local occurrences = actions._normalize_occurrences({ [2] = true, [5] = true })

            assert.are.same({ { lnum = 2 }, { lnum = 5 } }, occurrences)
        end)
    end)

    it("finds exact property value occurrences from note text", function()
        with_actions_stubs(function()
            package.loaded["telescope._extensions.vault.actions"] = nil
            local actions = require("telescope._extensions.vault.actions")
            local occurrences = actions._find_property_value_occurrences(
                fixture_root .. "/one.md",
                "status",
                "todo"
            )

            assert.are.same(
                {
                    {
                        lnum = 2,
                        start_col = 9,
                        end_col = 12,
                    },
                },
                occurrences
            )
        end)
    end)
end)
