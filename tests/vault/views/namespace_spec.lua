describe("vault.views namespace", function()
    it("re-exports grid, list, kanban, calendar, and shared views", function()
        local grid = require("vault.views.grid")
        assert.is_function(grid.open)
        assert.is_function(grid.reload)

        local list = require("vault.views.list")
        assert.is_function(list.open)

        local kanban = require("vault.views.kanban")
        assert.is_function(kanban.open)

        local calendar = require("vault.views.calendar")
        assert.is_function(calendar.open)

        local shared = require("vault.views.shared")
        assert.is_function(shared.set_frontmatter_fields)
    end)
end)
