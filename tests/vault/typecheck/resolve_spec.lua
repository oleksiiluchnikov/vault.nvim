describe("vault.typecheck.resolve", function()
    local resolve

    local function wl(name)
        return "[[" .. name .. "]]"
    end

    local tmp_root

    local function setup_root()
        tmp_root = vim.fn.tempname() .. "_vault_resolve"
        vim.fn.mkdir(tmp_root .. "/Templates", "p")
        vim.fn.mkdir(tmp_root .. "/Categories", "p")
    end

    local function write_file(rel_path, lines)
        local path = tmp_root .. "/" .. rel_path
        vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
        vim.fn.writefile(lines, path)
    end

    before_each(function()
        package.loaded["vault.typecheck.resolve"] = nil
        package.loaded["vault.typecheck.frontmatter"] = nil
        resolve = require("vault.typecheck.resolve")
        setup_root()
    end)

    after_each(function()
        if tmp_root then
            vim.fn.delete(tmp_root, "rf")
        end
    end)

    it("resolves template via category note", function()
        write_file("Tasks.md", {
            "---",
            'template: "' .. wl("task-template") .. '"',
            "---",
        })
        write_file("Templates/task-template.md", {
            "---",
            'type: "task"',
            "---",
        })

        local path, err = resolve.resolve({ wl("Tasks") }, tmp_root)
        assert.is_nil(err)
        assert.equals(tmp_root .. "/Templates/task-template.md", path)
    end)

    it("resolves category note in Categories/ subfolder", function()
        write_file("Categories/Journal.md", {
            "---",
            'template: "' .. wl("daily-note-template") .. '"',
            "---",
        })
        write_file("Templates/daily-note-template.md", {
            "---",
            'title: "{{date:YYYY-MM-DD}}"',
            "---",
        })

        local path, err = resolve.resolve({ wl("Journal") }, tmp_root)
        assert.is_nil(err)
        assert.truthy(path:match("daily%-note%-template%.md$"))
    end)

    it("errors on no categories", function()
        local _, err = resolve.resolve(nil, tmp_root)
        assert.equals("no categories field", err)
    end)

    it("errors on empty categories", function()
        local _, err = resolve.resolve({}, tmp_root)
        assert.equals("no categories field", err)
    end)

    it("errors on multiple categories", function()
        local _, err = resolve.resolve({ wl("Tasks"), wl("Content") }, tmp_root)
        assert.truthy(err:match("multiple categories"))
    end)

    it("errors when category note not found", function()
        local _, err = resolve.resolve({ wl("NonExistent") }, tmp_root)
        assert.truthy(err:match("category note not found"))
    end)

    it("errors when category note has no template field", function()
        write_file("Tasks.md", {
            "---",
            'type: "reference"',
            "---",
        })

        local _, err = resolve.resolve({ wl("Tasks") }, tmp_root)
        assert.truthy(err:match("has no template field"))
    end)

    it("errors when template file not found", function()
        write_file("Tasks.md", {
            "---",
            'template: "' .. wl("missing-template") .. '"',
            "---",
        })

        local _, err = resolve.resolve({ wl("Tasks") }, tmp_root)
        assert.truthy(err:match("template not found"))
    end)
end)
