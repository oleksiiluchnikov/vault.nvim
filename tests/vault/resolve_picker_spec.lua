describe("vault.ui.resolve_picker", function()
    it("creates from the typed query when results are empty", function()
        local picker = require("vault.ui.resolve_picker")
        local result = picker._submit_result(nil, "Initiative - mytt", true)

        assert.is_not_nil(result)
        assert.are.equal("create", result.action)
        assert.are.equal("Initiative - mytt", result.slug)
        assert.are.equal("Initiative - mytt", result.prompt)
    end)

    it("uses the typed query when the create row is selected", function()
        local picker = require("vault.ui.resolve_picker")
        local result = picker._submit_result({
            value = {
                action = "create",
                slug = "old-slug",
            },
        }, "New canonical target", true)

        assert.is_not_nil(result)
        assert.are.equal("create", result.action)
        assert.are.equal("New canonical target", result.slug)
    end)

    it("cancels when results are empty and no query was typed", function()
        local picker = require("vault.ui.resolve_picker")
        local result = picker._submit_result(nil, "", true)

        assert.is_nil(result)
    end)

    it("can force-create from the typed query even when results exist", function()
        local picker = require("vault.ui.resolve_picker")
        local result = picker._force_create_result("Reference/Initiative - mytt", true)

        assert.is_not_nil(result)
        assert.are.equal("create", result.action)
        assert.are.equal("Reference/Initiative - mytt", result.slug)
    end)
end)
