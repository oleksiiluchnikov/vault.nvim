-- Extend runtime path to include current working directory and Lazy plugins
vim.opt.runtimepath:append(vim.fn.getcwd() .. "/**")
vim.opt.runtimepath:append(vim.fn.getenv("HOME") .. "/.local/share/nvim/lazy/**")

-- Import required modules
local assert = require("luassert")
local VaultTags = require("vault.tags")

describe("VaultTags", function()
    -- Test for requiring the module
    it("should be required successfully", function()
        assert.is_not_nil(VaultTags)
    end)
end)

describe("VaultTags:init()", function()
    local tags = VaultTags()

    -- Test initialization of VaultTags object
    it("should return a `VaultTags` object", function()
        assert.is_true(tags.class.name == "VaultTags")
    end)

    -- Test the structure of a VaultTag object within the VaultTags map
    it("should return a VaultTag object within the map", function()
        local tag = vim.tbl_values(tags.map)[1]
        assert.is_true(tag.class.name == "VaultTag")
    end)
end)

describe("VaultTags:count()", function()
    local tags = VaultTags()

    -- Test the count method
    it("should return the correct number of tags", function()
        assert.is_true(tags:count() == #vim.tbl_keys(tags.map))
    end)
end)

describe("VaultTags:get_values_by_key()", function()
    local tags = VaultTags()

    -- Test retrieval of values by key
    it("should return a list of values for a key from tags", function()
        local values = tags:get_values_by_key("name")
        print(vim.inspect(values))
        assert.is_true(#values > 0)
    end)
end)

describe("VaultTags:filter()", function()
    local tags = VaultTags()

    -- Test filtering functionality
    it("should filter tags based on provided include/exclude rules", function()
        local filter_opts = {
            {
                include = { "tag1" },
                exclude = { "tag2" },
                match_opt = "exact",
                case_sensitive = false,
            },
        }
        local filtered_tags = tags:filter(filter_opts)

        -- Assuming filter should remove some tags, you might adjust according to actual data
        assert.is_true(filtered_tags:count() <= tags:count())
    end)
end)

describe("VaultTags:list()", function()
    local tags = VaultTags()

    -- Test conversion of map to list
    it("should return a list of tags", function()
        local list = tags:list()
        assert.is_true(#list > 0)
    end)
end)

describe("VaultTags:get_random_tag()", function()
    local tags = VaultTags()

    -- Test fetching a random tag
    it("should return a random tag", function()
        local random_tag = tags:get_random_tag()
        assert.is_true(random_tag.class.name == "VaultTag")
    end)
end)

describe("VaultTags:by()", function()
    local tags = VaultTags()

    -- Test filtering tags by key and value
    it("should return tags filtered by a specific key and value", function()
        local tags_by = tags:by("name", "specific_tag")
        assert.is_true(#tags_by > 0)
    end)
end)

describe("VaultTags:sources()", function()
    local tags = VaultTags()

    -- Test retrieving sources from tags
    it("should return a map of all sources from tags", function()
        local sources_map = tags:sources()
        assert.is_true(type(sources_map) == "table" and next(sources_map) ~= nil)
    end)
end)
