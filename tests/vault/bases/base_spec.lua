--- @module "busted"
vim.opt.runtimepath:append(vim.fn.getcwd() .. "/**")
vim.opt.runtimepath:append(vim.fn.getenv("HOME") .. "/.local/share/nvim/lazy/**")

local assert = require("luassert")
local Base = require("vault.bases.base")

-- ============================================================================
-- Base:init()
-- ============================================================================

describe("VaultBase:init()", function()
    it("should create a VaultBase object from raw data", function()
        local raw = {
            path = "/vault/views/projects.base",
            relpath = "views/projects.base",
            name = "projects",
            filters = { ["and"] = { 'file.hasTag("project")' } },
            formulas = { display_status = 'if(status, status, "unknown")' },
            properties = { ["file.name"] = { displayName = "Name" } },
            views = { { type = "table", name = "Project Table" } },
        }
        local base = Base(raw)
        assert.are.equal("VaultBase", base.class.name)
        assert.are.equal("projects", base.data.name)
        assert.are.equal("projects", base.data.slug)
        assert.are.equal("/vault/views/projects.base", base.data.path)
        assert.are.equal("views/projects.base", base.data.relpath)
    end)

    it("should accept minimal data with only name", function()
        local base = Base({ name = "minimal" })
        assert.are.equal("minimal", base.data.name)
        assert.are.equal("", base.data.path)
        assert.are.equal("", base.data.relpath)
    end)

    it("should accept minimal data with only path", function()
        local base = Base({ path = "/vault/views/test.base" })
        assert.are.equal("/vault/views/test.base", base.data.path)
        assert.are.equal("", base.data.name)
    end)

    it("should error when given a non-table", function()
        assert.has_error(function()
            Base("not a table")
        end)
    end)

    it("should error when given an empty table (no path or name)", function()
        assert.has_error(function()
            Base({})
        end)
    end)

    it("should default nil fields to empty/nil", function()
        local base = Base({ name = "empty" })
        assert.is_nil(base.data.filters)
        assert.is_nil(base.data.formulas)
        assert.is_nil(base.data.properties)
        assert.is_nil(base.data.views)
    end)
end)

-- ============================================================================
-- Base:__tostring()
-- ============================================================================

describe("VaultBase:__tostring()", function()
    it("should return a readable string representation", function()
        local base = Base({ name = "projects", path = "/vault/views/projects.base" })
        local str = tostring(base)
        assert.is_true(str:find("VaultBase") ~= nil)
        assert.is_true(str:find("projects") ~= nil)
    end)
end)

-- ============================================================================
-- Base:has_filters()
-- ============================================================================

describe("VaultBase:has_filters()", function()
    it("should return true when filters are present", function()
        local base = Base({
            name = "filtered",
            path = "/vault/views/filtered.base",
            filters = { ["and"] = { 'file.hasTag("project")' } },
        })
        assert.is_true(base:has_filters())
    end)

    it("should return false when filters are nil", function()
        local base = Base({ name = "nofilter", path = "/vault/views/nofilter.base" })
        assert.is_false(base:has_filters())
    end)

    it("should return false when filters are an empty table", function()
        local base = Base({
            name = "emptyfilter",
            path = "/vault/views/emptyfilter.base",
            filters = {},
        })
        assert.is_false(base:has_filters())
    end)
end)

-- ============================================================================
-- Base:has_formulas()
-- ============================================================================

describe("VaultBase:has_formulas()", function()
    it("should return true when formulas are present", function()
        local base = Base({
            name = "withformulas",
            path = "/vault/views/withformulas.base",
            formulas = { display_status = 'if(status, status, "unknown")' },
        })
        assert.is_true(base:has_formulas())
    end)

    it("should return false when formulas are nil", function()
        local base = Base({ name = "noformulas", path = "/vault/views/noformulas.base" })
        assert.is_false(base:has_formulas())
    end)

    it("should return false when formulas are an empty table", function()
        local base = Base({
            name = "emptyformulas",
            path = "/vault/views/emptyformulas.base",
            formulas = {},
        })
        assert.is_false(base:has_formulas())
    end)
end)

-- ============================================================================
-- Base:formula_names()
-- ============================================================================

describe("VaultBase:formula_names()", function()
    it("should return a list of formula names", function()
        local base = Base({
            name = "test",
            path = "/vault/views/test.base",
            formulas = {
                display_status = 'if(status, status, "unknown")',
                name_upper = "file.name.title()",
            },
        })
        local names = base:formula_names()
        assert.is_table(names)
        assert.are.equal(2, #names)
        -- Sort for deterministic comparison
        table.sort(names)
        assert.are.equal("display_status", names[1])
        assert.are.equal("name_upper", names[2])
    end)

    it("should return an empty list when no formulas", function()
        local base = Base({ name = "test", path = "/vault/views/test.base" })
        local names = base:formula_names()
        assert.is_table(names)
        assert.are.equal(0, #names)
    end)
end)

-- ============================================================================
-- Base:view_count()
-- ============================================================================

describe("VaultBase:view_count()", function()
    it("should return the number of views", function()
        local base = Base({
            name = "test",
            path = "/vault/views/test.base",
            views = {
                { type = "table", name = "View 1" },
                { type = "table", name = "View 2" },
                { type = "table", name = "View 3" },
            },
        })
        assert.are.equal(3, base:view_count())
    end)

    it("should return 0 when no views", function()
        local base = Base({ name = "test", path = "/vault/views/test.base" })
        assert.are.equal(0, base:view_count())
    end)
end)

-- ============================================================================
-- Base:display_names()
-- ============================================================================

describe("VaultBase:display_names()", function()
    it("should return property key -> displayName mapping", function()
        local base = Base({
            name = "test",
            path = "/vault/views/test.base",
            properties = {
                ["file.name"] = { displayName = "Name" },
                status = { displayName = "Status" },
            },
        })
        local names = base:display_names()
        assert.are.equal("Name", names["file.name"])
        assert.are.equal("Status", names["status"])
    end)

    it("should use key as fallback when displayName is missing", function()
        local base = Base({
            name = "test",
            path = "/vault/views/test.base",
            properties = {
                tags = "simple_value",
            },
        })
        local names = base:display_names()
        assert.are.equal("tags", names["tags"])
    end)

    it("should return empty table when no properties", function()
        local base = Base({ name = "test", path = "/vault/views/test.base" })
        local names = base:display_names()
        assert.is_table(names)
        assert.is_nil(next(names))
    end)
end)

-- ============================================================================
-- Base:match_notes()
-- ============================================================================

describe("VaultBase:match_notes()", function()
    -- Mock notes for testing
    local mock_notes = {
        ["Project/test_note"] = {
            data = {
                path = "/vault/Project/test_note.md",
                relpath = "Project/test_note.md",
                slug = "Project/test_note",
                stem = "test_note",
                content = "some content",
                tags = {
                    project = { data = { name = "project", sources = {} } },
                },
                frontmatter = {
                    data = {
                        status = "active",
                        tags = { "project" },
                    },
                },
            },
        },
        ["Inbox/orphan"] = {
            data = {
                path = "/vault/Inbox/orphan.md",
                relpath = "Inbox/orphan.md",
                slug = "Inbox/orphan",
                stem = "orphan",
                content = "",
                tags = {},
                frontmatter = { data = {} },
            },
        },
    }

    it("should return all notes when no filters are defined", function()
        local base = Base({ name = "all", path = "/vault/views/all.base" })
        local matched = base:match_notes(mock_notes)
        -- No filters means all notes match
        local count = 0
        for _ in pairs(matched) do
            count = count + 1
        end
        assert.are.equal(2, count)
    end)

    it("should filter notes using and: combinator", function()
        local base = Base({
            name = "projects",
            path = "/vault/views/projects.base",
            filters = {
                ["and"] = {
                    'file.hasTag("project")',
                    'file.inFolder("Project")',
                },
            },
        })
        local matched = base:match_notes(mock_notes)
        -- Only the Project/test_note should match
        assert.is_not_nil(matched["Project/test_note"])
        assert.is_nil(matched["Inbox/orphan"])
    end)

    it("should return empty table when no notes match", function()
        local base = Base({
            name = "nonexistent",
            path = "/vault/views/nonexistent.base",
            filters = {
                ["and"] = {
                    'file.hasTag("nonexistent_tag")',
                },
            },
        })
        local matched = base:match_notes(mock_notes)
        assert.is_nil(next(matched))
    end)
end)

-- ============================================================================
-- Base:evaluate_formulas()
-- ============================================================================

describe("VaultBase:evaluate_formulas()", function()
    local mock_note = {
        data = {
            path = "/vault/Project/test_note.md",
            relpath = "Project/test_note.md",
            slug = "Project/test_note",
            stem = "test_note",
            content = "some content",
            tags = {
                project = { data = { name = "project", sources = {} } },
            },
            frontmatter = {
                data = {
                    status = "active",
                    tags = { "project" },
                },
            },
        },
    }

    it("should return empty table when no formulas", function()
        local base = Base({ name = "test", path = "/vault/views/test.base" })
        local results = base:evaluate_formulas(mock_note)
        assert.is_table(results)
        assert.is_nil(next(results))
    end)

    it("should evaluate formulas against a note", function()
        local base = Base({
            name = "test",
            path = "/vault/views/test.base",
            formulas = {
                display_status = 'if(status, status, "unknown")',
            },
        })
        local results = base:evaluate_formulas(mock_note)
        assert.is_not_nil(results.display_status)
        -- status is "active" which is truthy, so if() should return "active"
        assert.are.equal("active", results.display_status)
    end)

    it("should handle formula evaluation errors gracefully", function()
        local base = Base({
            name = "test",
            path = "/vault/views/test.base",
            formulas = {
                bad_formula = "this.is.not.a.valid.expression((((",
            },
        })
        -- Should not error, just set the value to nil
        local results = base:evaluate_formulas(mock_note)
        assert.is_table(results)
        -- The failed formula should have nil value
        assert.is_nil(results.bad_formula)
    end)
end)
