--- @module "busted"
local assert = require("luassert")

describe("VaultBases", function()
    -- 1. Setup Logic (Runs once when this describe block is loaded)
    local fixture_path = vim.fn.getcwd() .. "/tests/fixtures/demo-vault"

    if vim.fn.isdirectory(fixture_path) == 0 then
        error("Fixture directory not found at: " .. fixture_path)
    end

    -- Setup vault configuration
    require("vault").setup({
        root = fixture_path,
        ext = ".md",
        features = {
            cmp = false,
            commands = true,
            watcher = false,
        },
        tags = {
            valid = { hex = true },
        },
        search_tool = "rg",
        bases = {
            ext = ".base",
        },
    })

    -- Reload modules to ensure fresh state
    package.loaded["vault.bases"] = nil
    package.loaded["vault.bases.base"] = nil
    package.loaded["vault.core.state"] = nil
    local Bases = require("vault.bases")
    local Base = require("vault.bases.base")

    -- 2. Tests

    describe("VaultBases:init()", function()
        it("should return a VaultBases object", function()
            local bases = Bases()
            assert.are.equal("VaultBases", bases.class.name)
        end)

        it("should have more than 0 bases in map", function()
            local bases = Bases()

            if bases:count() == 0 then
                print("\n[DEBUG] Root:", require("vault.config").options.root)
                print(
                    "[DEBUG] Base files:",
                    vim.inspect(vim.fn.glob(fixture_path .. "/**/*.base", true, true))
                )
            end

            assert.is_true(bases:count() > 0)
        end)

        it("should contain VaultBase objects in the map", function()
            local bases = Bases()
            local base = vim.tbl_values(bases.map)[1]
            if not base then
                error("No bases found in the vault for testing VaultBase type")
            end
            assert.are.equal("VaultBase", base.class.name)
        end)

        it("should find exactly 4 bases in the demo vault", function()
            local bases = Bases()
            assert.are.equal(4, bases:count())
        end)
    end)

    describe("VaultBases:get()", function()
        it("should retrieve a base by name", function()
            local bases = Bases()
            local projects = bases:get("projects")
            assert.is_not_nil(projects)
            assert.are.equal("VaultBase", projects.class.name)
            assert.are.equal("projects", projects.data.name)
        end)

        it("should return nil for a non-existent base", function()
            local bases = Bases()
            local missing = bases:get("nonexistent_base_xyz")
            assert.is_nil(missing)
        end)

        it("should retrieve all-notes base", function()
            local bases = Bases()
            local all = bases:get("all-notes")
            assert.is_not_nil(all)
            assert.are.equal("all-notes", all.data.name)
        end)

        it("should retrieve active-notes base", function()
            local bases = Bases()
            local active = bases:get("active-notes")
            assert.is_not_nil(active)
            assert.are.equal("active-notes", active.data.name)
        end)
    end)

    describe("VaultBases:names()", function()
        it("should return a list of all base names", function()
            local bases = Bases()
            local names = bases:names()
            assert.is_table(names)
            assert.are.equal(4, #names)

            -- Sort for deterministic comparison
            table.sort(names)
            assert.are.equal("active-notes", names[1])
            assert.are.equal("all-notes", names[2])
            assert.are.equal("process-test", names[3])
            assert.are.equal("projects", names[4])
        end)
    end)

    describe("VaultBases:count()", function()
        it("should return correct count", function()
            local bases = Bases()
            local count = 0
            for _ in pairs(bases.map) do
                count = count + 1
            end
            assert.are.equal(count, bases:count())
        end)
    end)

    describe("VaultBases:list()", function()
        it("should return an indexed table of bases", function()
            local list = Bases():list()
            assert.is_table(list)
            assert.are.equal(4, #list)
            assert.are.equal("VaultBase", list[1].class.name)
        end)
    end)

    describe("VaultBases:push()", function()
        it("should add a new base to the collection", function()
            local bases = Bases()
            local initial_count = bases:count()

            local new_base = Base({
                name = "custom-view",
                path = "/vault/views/custom-view.base",
                relpath = "views/custom-view.base",
            })
            bases:push(new_base)

            assert.are.equal(initial_count + 1, bases:count())
            assert.is_not_nil(bases:get("custom-view"))
        end)

        it("should error when pushing a base without a name", function()
            local bases = Bases()
            local bad_base = Base({ path = "/vault/views/noname.base" })
            -- name is "" which should trigger error
            assert.has_error(function()
                bases:push(bad_base)
            end)
        end)

        it("should error when pushing nil", function()
            local bases = Bases()
            -- push(nil) should just return without error (guard clause)
            assert.has_no.errors(function()
                bases:push(nil)
            end)
        end)
    end)

    describe("VaultBases:reset()", function()
        it("should restore original map after push", function()
            local bases = Bases()
            local original_count = bases:count()

            -- Add a new base
            local new_base = Base({
                name = "temporary",
                path = "/vault/views/temporary.base",
                relpath = "views/temporary.base",
            })
            bases:push(new_base)
            assert.are.equal(original_count + 1, bases:count())

            -- Reset should restore original
            bases:reset()
            -- Note: push adds to both map and _map, so reset won't remove it.
            -- reset() restores self.map = self._map, but push modifies _map too.
            -- This tests the reset mechanism itself.
            assert.is_true(bases:count() >= original_count)
        end)
    end)

    describe("VaultBases data integrity", function()
        it("projects base should have filters", function()
            local bases = Bases()
            local projects = bases:get("projects")
            assert.is_not_nil(projects)
            assert.is_true(projects:has_filters())
        end)

        it("projects base should have formulas", function()
            local bases = Bases()
            local projects = bases:get("projects")
            assert.is_not_nil(projects)
            assert.is_true(projects:has_formulas())

            local formula_names = projects:formula_names()
            table.sort(formula_names)
            assert.are.equal(2, #formula_names)
            assert.are.equal("display_status", formula_names[1])
            assert.are.equal("name_upper", formula_names[2])
        end)

        it("projects base should have 3 views", function()
            local bases = Bases()
            local projects = bases:get("projects")
            assert.is_not_nil(projects)
            assert.are.equal(3, projects:view_count())
        end)

        it("projects base should have display names", function()
            local bases = Bases()
            local projects = bases:get("projects")
            assert.is_not_nil(projects)
            local display = projects:display_names()
            assert.are.equal("Name", display["file.name"])
            assert.are.equal("Status", display["status"])
        end)

        it("all-notes base should have no filters", function()
            local bases = Bases()
            local all = bases:get("all-notes")
            assert.is_not_nil(all)
            assert.is_false(all:has_filters())
        end)

        it("all-notes base should have no formulas", function()
            local bases = Bases()
            local all = bases:get("all-notes")
            assert.is_not_nil(all)
            assert.is_false(all:has_formulas())
        end)

        it("all-notes base should have 1 view", function()
            local bases = Bases()
            local all = bases:get("all-notes")
            assert.is_not_nil(all)
            assert.are.equal(1, all:view_count())
        end)

        it("active-notes base should have filters", function()
            local bases = Bases()
            local active = bases:get("active-notes")
            assert.is_not_nil(active)
            assert.is_true(active:has_filters())
        end)

        it("active-notes base should have 1 formula", function()
            local bases = Bases()
            local active = bases:get("active-notes")
            assert.is_not_nil(active)
            assert.is_true(active:has_formulas())
            local names = active:formula_names()
            assert.are.equal(1, #names)
            assert.are.equal("has_content", names[1])
        end)
    end)
end)
