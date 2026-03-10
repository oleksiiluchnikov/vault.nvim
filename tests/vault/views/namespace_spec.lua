describe("vault.views namespace", function()
    it("re-exports grid, list, kanban, calendar, and shared views", function()
        local grid = require("vault.views.grid")
        local base_grid = require("vault.bases.views.grid")
        assert.are.equal(base_grid.open, grid.open)
        assert.are.equal(base_grid.reload, grid.reload)

        local list = require("vault.views.list")
        local base_list = require("vault.bases.views.list")
        assert.are.equal(base_list.open, list.open)

        local kanban = require("vault.views.kanban")
        local base_kanban = require("vault.bases.views.kanban")
        assert.are.equal(base_kanban.open, kanban.open)

        local calendar = require("vault.views.calendar")
        local base_calendar = require("vault.bases.views.calendar")
        assert.are.equal(base_calendar.open, calendar.open)

        local shared = require("vault.views.shared")
        local base_shared = require("vault.bases.views.shared")
        assert.are.equal(base_shared.set_frontmatter_fields, shared.set_frontmatter_fields)
    end)
end)
