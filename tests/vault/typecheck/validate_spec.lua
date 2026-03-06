describe("vault.typecheck.validate", function()
    local validate
    local infer

    local function wl(name)
        return "[[" .. name .. "]]"
    end

    -- Always-passes wikilink checker
    local function ok_wl(_)
        return nil
    end

    -- Always-fails wikilink checker
    local function fail_wl(link)
        local inner = link:match("^%[%[(.-)%]%]$") or link
        return "dangling wikilink: " .. wl(inner) .. " (target not found)"
    end

    before_each(function()
        package.loaded["vault.typecheck.validate"] = nil
        package.loaded["vault.typecheck.infer"] = nil
        validate = require("vault.typecheck.validate")
        infer = require("vault.typecheck.infer")
    end)

    local function make_schema(fields_raw)
        local fields = {}
        for k, v in pairs(fields_raw) do
            fields[k] = infer.infer(v)
        end
        return { template_path = "/fake/template.md", fields = fields }
    end

    describe("validate()", function()
        it("passes valid note matching schema", function()
            local schema = make_schema({
                type = "task",
                status = wl("Status - Backlog"),
                due = "",
                blocked_by = {},
                committed = 20260306,
            })
            local errors = validate.validate({
                schema = schema,
                raw_fields = {
                    categories = { wl("Tasks") },
                    type = "task",
                    status = wl("Status - Done"),
                    due = "tomorrow",
                    blocked_by = {},
                    committed = 20260307,
                },
                line_map = {},
                check_wikilink = ok_wl,
            })
            assert.equals(0, #errors)
        end)

        it("errors on missing required field", function()
            local schema = make_schema({ type = "task" })
            local errors = validate.validate({
                schema = schema,
                raw_fields = { categories = { wl("Tasks") } },
                line_map = {},
                check_wikilink = ok_wl,
            })
            assert.equals(1, #errors)
            assert.truthy(errors[1].message:match("missing required"))
        end)

        it("allows missing optional field", function()
            local schema = make_schema({ due = "" })
            local errors = validate.validate({
                schema = schema,
                raw_fields = { categories = { wl("Tasks") } },
                line_map = {},
                check_wikilink = ok_wl,
            })
            assert.equals(0, #errors)
        end)

        it("allows extra fields not in schema", function()
            local schema = make_schema({ type = "task" })
            local errors = validate.validate({
                schema = schema,
                raw_fields = {
                    categories = { wl("Tasks") },
                    type = "task",
                    airtable_fields = "something extra",
                },
                line_map = {},
                check_wikilink = ok_wl,
            })
            assert.equals(0, #errors)
        end)

        it("errors on multiple categories", function()
            local schema = make_schema({ type = "task" })
            local errors = validate.validate({
                schema = schema,
                raw_fields = {
                    categories = { wl("Tasks"), wl("Content") },
                    type = "task",
                },
                line_map = {},
                check_wikilink = ok_wl,
            })
            assert.equals(1, #errors)
            assert.truthy(errors[1].message:match("multiple categories"))
        end)

        it("errors on plain string where wikilink expected", function()
            local schema = make_schema({ status = wl("Status - Backlog") })
            local errors = validate.validate({
                schema = schema,
                raw_fields = {
                    categories = { wl("Tasks") },
                    status = "Todo",
                },
                line_map = {},
                check_wikilink = ok_wl,
            })
            assert.equals(1, #errors)
            assert.truthy(errors[1].message:match("expected wikilink"))
        end)

        it("errors on wikilink prefix mismatch", function()
            local schema = make_schema({ status = wl("Status - Backlog") })
            local errors = validate.validate({
                schema = schema,
                raw_fields = {
                    categories = { wl("Tasks") },
                    status = wl("Priority - High"),
                },
                line_map = {},
                check_wikilink = ok_wl,
            })
            assert.equals(1, #errors)
            assert.truthy(errors[1].message:match("prefix mismatch"))
        end)

        it("errors on dangling wikilink", function()
            local schema = make_schema({ status = wl("Status - Backlog") })
            local errors = validate.validate({
                schema = schema,
                raw_fields = {
                    categories = { wl("Tasks") },
                    status = wl("Status - NonExistent"),
                },
                line_map = {},
                check_wikilink = fail_wl,
            })
            assert.equals(1, #errors)
            assert.truthy(errors[1].message:match("dangling wikilink"))
        end)

        it("errors on invalid enum value", function()
            local schema = make_schema({ status = "draft | published" })
            local errors = validate.validate({
                schema = schema,
                raw_fields = {
                    categories = { wl("Tasks") },
                    status = "archived",
                },
                line_map = {},
                check_wikilink = ok_wl,
            })
            assert.equals(1, #errors)
            assert.truthy(errors[1].message:match("expected one of"))
        end)

        it("errors on non-number where number expected", function()
            local schema = make_schema({ committed = 20260306 })
            local errors = validate.validate({
                schema = schema,
                raw_fields = {
                    categories = { wl("Tasks") },
                    committed = "not-a-number",
                },
                line_map = {},
                check_wikilink = ok_wl,
            })
            assert.equals(1, #errors)
            assert.truthy(errors[1].message:match("expected number"))
        end)

        it("errors on non-wikilink in array_wikilink", function()
            local schema = make_schema({ blocked_by = { wl("Some Task") } })
            local errors = validate.validate({
                schema = schema,
                raw_fields = {
                    categories = { wl("Tasks") },
                    blocked_by = { "plain text" },
                },
                line_map = {},
                check_wikilink = ok_wl,
            })
            assert.equals(1, #errors)
            assert.truthy(errors[1].message:match("expected wikilink"))
        end)

        it("skips template variable fields", function()
            local schema = make_schema({
                title = "{{title}}",
                created = "{{date:YYYYMMDDHHmmss}}",
            })
            local errors = validate.validate({
                schema = schema,
                raw_fields = {
                    categories = { wl("Tasks") },
                    title = "Anything goes",
                    created = "20260307",
                },
                line_map = {},
                check_wikilink = ok_wl,
            })
            assert.equals(0, #errors)
        end)
    end)
end)
