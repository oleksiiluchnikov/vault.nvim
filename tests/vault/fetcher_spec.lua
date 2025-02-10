--- @module "busted"
vim.opt.runtimepath:append(vim.fn.getcwd() .. "/**")
vim.opt.runtimepath:append(vim.fn.getenv("HOME") .. "/.local/share/nvim/lazy/**")

local assert = require("luassert")
local Path = require("plenary.path")
local config = require("vault.config")

-- Setup test environment
local demo_vault = vim.fn.getcwd() .. "/tests/fixtures/demo-vault"
local temp_file_path = demo_vault .. "/test_note.md"

describe("Vaultrequire('vault.fetcher')", function()
    before_each(function()
        -- Set up vault config for testing first
        config.setup({
            root = demo_vault,
        })

        -- Create test vault directory and files
        if not Path:new(demo_vault):exists() then
            vim.fn.mkdir(demo_vault, "p")
        end

        -- Create a test note with various features to test
        local test_content = [=[
        ---
        title: Test Note
        tags: [test, markdown, #nested/tag]
        status: active
        priority: 1
        ---

        # Test Note

        Some content with a [[Wiki Link]] and another [[Nested/Wiki/Link|With Title]].

        - [ ] Todo item 1 #todo
        - [x] Completed todo
        - [ ] Another todo with [[Wiki Link]] #priority

        Check out [External Link](https://example.com)

        #standalone-tag #another/nested/tag

        Some inline fields::value and [key2::value2]
        ]=]

        local file = io.open(temp_file_path, "w")
        if not file then
            error("Failed to create test file")
        end
        file:write(test_content)
        file:close()
    end)

    after_each(function()
        -- Cleanup test files
        -- os.remove(temp_file_path)
        -- vim.fn.delete(demo_vault, "rf")
    end)

    describe("paths()", function()
        it("should return map of paths with correct structure", function()
            --- @type vault.EntryInfoMap
            local paths = require("vault.fetcher").paths()
            assert.is_table(paths)

            -- Test first path entry
            --- @type vault.path
            local first_path = next(paths)
            assert.is_not_nil(first_path)
            assert.is_table(paths[first_path])
            assert.is_string(paths[first_path].path)
            assert.is_string(paths[first_path].slug)
            assert.is_string(paths[first_path].relpath)
            assert.is_string(paths[first_path].basename)
        end)
    end)

    describe("wikilinks()", function()
        -- it("should return map of wikilinks", function()
        --     local wikilinks = require("vault.fetcher").wikilinks()
        --     assert.is_table(wikilinks)
        --
        --     -- Should find our test wikilinks
        --     assert.is_not_nil(wikilinks["Wiki Link"])
        --     assert.is_not_nil(wikilinks["Nested/Wiki/Link"])
        --
        --     -- Test wikilink structure
        --     local wikilink = wikilinks["Wiki Link"]
        --     assert.is_table(wikilink.data)
        --     assert.is_table(wikilink.data.sources)
        --     assert.is_number(wikilink.data.count)
        -- end)

        it("should return first wikilink", function()
            local wikilinks = require("vault.fetcher").wikilinks()
            print(vim.inspect(wikilinks))
        end)
    end)
    --
    -- describe("tags()", function()
    --     it("should return map of tags", function()
    --         local tags = require("vault.fetcher").tags()
    --         assert.is_table(tags)
    --
    --         -- Should find both frontmatter and inline tags
    --         assert.is_not_nil(tags["test"])
    --         assert.is_not_nil(tags["markdown"])
    --         assert.is_not_nil(tags["todo"])
    --         assert.is_not_nil(tags["nested/tag"])
    --
    --         -- Test tag structure
    --         local tag = tags["test"]
    --         assert.is_table(tag.data)
    --         assert.is_string(tag.data.name)
    --         assert.is_table(tag.data.sources)
    --     end)
    -- end)
    --
    -- describe("tasks()", function()
    --     it("should return map of tasks", function()
    --         local tasks = require("vault.fetcher").tasks()
    --         assert.is_table(tasks)
    --
    --         -- Should find all todo items
    --         local first_note_tasks = next(tasks)
    --         assert.is_not_nil(first_note_tasks)
    --         assert.equals(3, vim.tbl_count(tasks[first_note_tasks])) -- Should find 3 tasks
    --
    --         -- Test task structure
    --         local task = tasks[first_note_tasks][1]
    --         assert.is_string(task.line)
    --         assert.is_string(task.status)
    --         assert.is_string(task.text)
    --     end)
    -- end)
    --
    -- describe("links()", function()
    --     it("should return map of external links", function()
    --         local links = require("vault.fetcher").links()
    --         assert.is_table(links)
    --
    --         -- Should find our test external link
    --         local first_note_links = next(links)
    --         assert.is_not_nil(first_note_links)
    --
    --         -- Test link structure
    --         local link = links[first_note_links][1]
    --         assert.equals("External Link", link.text)
    --         assert.equals("https://example.com", link.url)
    --     end)
    -- end)
    --
    -- describe("fields()", function()
    --     it("should return map of fields", function()
    --         local fields = require("vault.fetcher").fields()
    --         assert.is_table(fields)
    --
    --         -- Should find inline fields
    --         assert.is_not_nil(fields["value"])
    --         assert.is_not_nil(fields["key2"])
    --
    --         -- Test field structure
    --         local field = next(fields)
    --         assert.is_table(fields[field])
    --     end)
    -- end)
    --
    -- describe("properties()", function()
    --     it("should return map of frontmatter properties", function()
    --         local properties = require("vault.fetcher").properties()
    --         assert.is_table(properties)
    --
    --         -- Should find frontmatter properties
    --         assert.is_not_nil(properties["title"])
    --         assert.is_not_nil(properties["tags"])
    --         assert.is_not_nil(properties["status"])
    --         assert.is_not_nil(properties["priority"])
    --
    --         -- Test property structure
    --         local prop = properties["title"]
    --         assert.is_table(prop.data)
    --         assert.equals("title", prop.data.name)
    --         assert.is_table(prop.data.values)
    --     end)
    -- end)
end)
