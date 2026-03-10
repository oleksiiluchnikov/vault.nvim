local root_cwd = vim.fn.getcwd()
local fixture_root = root_cwd .. "/tests/fixtures/demo-vault"

local function clear_state()
    package.loaded["vault"] = nil
    package.loaded["vault.properties"] = nil
    package.loaded["telescope._extensions.vault.previewers"] = nil
    require("vault.core.state").global = {}
end

local function with_telescope_previewer_stub(fn)
    local original = package.loaded["telescope.previewers"]
    package.loaded["telescope.previewers"] = {
        vim_buffer_vimgrep = {
            new = function(spec)
                return spec
            end,
        },
        new_buffer_previewer = function(spec)
            return spec
        end,
    }
    local ok, err = pcall(fn)
    package.loaded["telescope.previewers"] = original
    if not ok then
        error(err)
    end
end

describe("telescope._extensions.vault.previewers properties", function()
    before_each(function()
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

    it("renders property values as a table-style list", function()
        local properties = require("vault.properties")()
        with_telescope_previewer_stub(function()
            local previewers = require("telescope._extensions.vault.previewers")
            local property = properties.map.tags
            local lines = select(1, previewers._property_preview_lines(property))

            assert.are.equal("tags", lines[1])
            assert.is_true(lines[2]:match("sources %d+   values %d+") ~= nil)
            assert.are.equal("", lines[3])
            assert.are.equal("type          value             count", lines[4])
            assert.are.equal("-------------------------------------", lines[5])
            assert.is_true(lines[6]:match("^text%s+project%s+5$") ~= nil)
        end)
    end)

    it("normalizes multiline preview lines safely", function()
        with_telescope_previewer_stub(function()
            local previewers = require("telescope._extensions.vault.previewers")
            local lines = previewers._normalize_preview_lines({ "one\ntwo", "three" })

            assert.are.same({ "one", "two", "three" }, lines)
        end)
    end)
end)
