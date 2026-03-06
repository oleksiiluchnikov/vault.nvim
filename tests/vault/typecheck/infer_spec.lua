describe("vault.typecheck.infer", function()
    local infer

    before_each(function()
        package.loaded["vault.typecheck.infer"] = nil
        infer = require("vault.typecheck.infer")
    end)

    describe("infer()", function()
        it("returns unknown for nil", function()
            local ft = infer.infer(nil)
            assert.equals("unknown", ft.kind)
            assert.is_false(ft.required)
        end)

        it("infers number from numeric value", function()
            local ft = infer.infer(20260306)
            assert.equals("number", ft.kind)
            assert.is_true(ft.required)
        end)

        it("infers optional from empty string", function()
            local ft = infer.infer("")
            assert.equals("optional", ft.kind)
            assert.is_false(ft.required)
        end)

        it("infers string from plain non-empty string", function()
            local ft = infer.infer("task")
            assert.equals("string", ft.kind)
            assert.is_true(ft.required)
        end)

        it("infers wikilink from [[Prefix - Value]]", function()
            local ft = infer.infer("[[Status - Backlog]]")
            assert.equals("wikilink", ft.kind)
            assert.is_true(ft.required)
            assert.equals("Status - ", ft.prefix)
        end)

        it("infers wikilink without prefix from [[SimpleLink]]", function()
            local ft = infer.infer("[[Tasks]]")
            assert.equals("wikilink", ft.kind)
            assert.is_true(ft.required)
            assert.is_nil(ft.prefix)
        end)

        it("infers enum from pipe-separated string", function()
            local ft = infer.infer("draft | published")
            assert.equals("enum", ft.kind)
            assert.is_true(ft.required)
            assert.same({ "draft", "published" }, ft.values)
        end)

        it("infers title_template from {{title}}", function()
            local ft = infer.infer("{{title}}")
            assert.equals("title_template", ft.kind)
            assert.is_false(ft.required)
        end)

        it("infers date_template from {{date:FORMAT}}", function()
            local ft = infer.infer("{{date:YYYYMMDDHHmmss}}")
            assert.equals("date_template", ft.kind)
            assert.is_false(ft.required)
        end)

        it("infers array_wikilink from empty array", function()
            local ft = infer.infer({})
            assert.equals("array_wikilink", ft.kind)
            assert.is_false(ft.required)
        end)

        it("infers array_wikilink from array with wikilinks", function()
            local ft = infer.infer({ "[[Tasks]]" })
            assert.equals("array_wikilink", ft.kind)
            assert.is_false(ft.required)
        end)

        it("infers array_string from array with plain strings", function()
            local ft = infer.infer({ "research", "draft" })
            assert.equals("array_string", ft.kind)
            assert.is_false(ft.required)
        end)

        it("returns unknown for non-string non-table non-number", function()
            local ft = infer.infer(true)
            assert.equals("string", ft.kind)
        end)
    end)

    describe("load_schema()", function()
        it("builds schema from mock frontmatter", function()
            local mock_read = function(_)
                return {
                    type = "task",
                    status = "[[Status - Backlog]]",
                    title = "{{title}}",
                    due = "",
                    blocked_by = {},
                    committed = 20260306,
                }
            end

            local schema = infer.load_schema("/fake/template.md", mock_read)
            assert.equals("/fake/template.md", schema.template_path)
            assert.equals("string", schema.fields.type.kind)
            assert.equals("wikilink", schema.fields.status.kind)
            assert.equals("title_template", schema.fields.title.kind)
            assert.equals("optional", schema.fields.due.kind)
            assert.equals("array_wikilink", schema.fields.blocked_by.kind)
            assert.equals("number", schema.fields.committed.kind)
        end)
    end)
end)
