describe("vault.typecheck.frontmatter", function()
    local fm

    -- Wikilink helper to avoid [[ ]] confusing Lua parser
    local function wl(name)
        return "[[" .. name .. "]]"
    end

    before_each(function()
        package.loaded["vault.typecheck.frontmatter"] = nil
        fm = require("vault.typecheck.frontmatter")
    end)

    local function write_tmp(lines)
        local path = vim.fn.tempname() .. ".md"
        vim.fn.writefile(lines, path)
        return path
    end

    describe("read_raw_frontmatter()", function()
        it("preserves wikilink brackets", function()
            local path = write_tmp({
                "---",
                'status: "' .. wl("Status - Backlog") .. '"',
                "---",
                "# Title",
            })
            local fields = fm.read_raw_frontmatter(path)
            assert.equals(wl("Status - Backlog"), fields.status)
        end)

        it("preserves numbers as numbers", function()
            local path = write_tmp({
                "---",
                "committed: 20260306030425",
                "---",
            })
            local fields = fm.read_raw_frontmatter(path)
            assert.equals(20260306030425, fields.committed)
        end)

        it("strips quotes from strings", function()
            local path = write_tmp({
                "---",
                'type: "task"',
                "---",
            })
            local fields = fm.read_raw_frontmatter(path)
            assert.equals("task", fields.type)
        end)

        it("parses multi-line YAML arrays", function()
            local path = write_tmp({
                "---",
                "categories:",
                '  - "' .. wl("Tasks") .. '"',
                '  - "' .. wl("Content") .. '"',
                "---",
            })
            local fields = fm.read_raw_frontmatter(path)
            assert.same({ wl("Tasks"), wl("Content") }, fields.categories)
        end)

        it("parses inline arrays", function()
            local path = write_tmp({
                "---",
                'categories: ["' .. wl("Tasks") .. '"]',
                "---",
            })
            local fields = fm.read_raw_frontmatter(path)
            assert.same({ wl("Tasks") }, fields.categories)
        end)

        it("returns empty table for empty array", function()
            local path = write_tmp({
                "---",
                "blocked_by: []",
                "---",
            })
            local fields = fm.read_raw_frontmatter(path)
            assert.same({}, fields.blocked_by)
        end)

        it("handles empty string values", function()
            local path = write_tmp({
                "---",
                'due: ""',
                "---",
            })
            local fields = fm.read_raw_frontmatter(path)
            assert.equals("", fields.due)
        end)

        it("returns empty table for file without frontmatter", function()
            local path = write_tmp({
                "# Just a title",
                "Some content",
            })
            local fields = fm.read_raw_frontmatter(path)
            assert.same({}, fields)
        end)

        it("returns empty table for nonexistent file", function()
            local fields = fm.read_raw_frontmatter("/nonexistent/path.md")
            assert.same({}, fields)
        end)

        it("handles multi-line list followed by scalar", function()
            local path = write_tmp({
                "---",
                "categories:",
                '  - "' .. wl("Tasks") .. '"',
                'type: "task"',
                "---",
            })
            local fields = fm.read_raw_frontmatter(path)
            assert.same({ wl("Tasks") }, fields.categories)
            assert.equals("task", fields.type)
        end)
    end)

    describe("build_line_map()", function()
        it("maps field names to 0-indexed line numbers", function()
            local path = write_tmp({
                "---",
                'status: "' .. wl("Status - Backlog") .. '"',
                'title: "My Task"',
                'due: ""',
                "---",
            })
            local map = fm.build_line_map(path)
            assert.equals(1, map.status)
            assert.equals(2, map.title)
            assert.equals(3, map.due)
        end)

        it("returns empty map for file without frontmatter", function()
            local path = write_tmp({ "# Title" })
            local map = fm.build_line_map(path)
            assert.same({}, map)
        end)
    end)
end)
