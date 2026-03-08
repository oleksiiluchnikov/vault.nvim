local config = require("vault.config")
local state = require("vault.core.state")

local tmp_root = vim.fn.getcwd() .. "/tests/tmp_notes_move_vault"

local function reset_modules()
    package.loaded["vault.notes"] = nil
    package.loaded["vault.scanner"] = nil
    package.loaded["vault.watcher"] = nil
end

local function rm_rf(path)
    if vim.fn.isdirectory(path) == 1 then
        vim.fn.delete(path, "rf")
    elseif vim.fn.filereadable(path) == 1 then
        vim.fn.delete(path)
    end
end

local function write(path, lines)
    local dir = vim.fn.fnamemodify(path, ":h")
    vim.fn.mkdir(dir, "p")
    vim.fn.writefile(lines, path)
end

local function read(path)
    return table.concat(vim.fn.readfile(path), "\n")
end

describe("VaultNotes batch moves", function()
    before_each(function()
        rm_rf(tmp_root)
        vim.fn.mkdir(tmp_root, "p")

        write(tmp_root .. "/_Legacy/sub/note-a.md", {
            "---",
            "slug: _Legacy/sub/note-a",
            "---",
            "[[_Legacy/sub/note-b]]",
        })
        write(tmp_root .. "/_Legacy/sub/note-b.md", {
            "# note b",
            "[[_Legacy/sub/note-a|alias]]",
        })
        write(tmp_root .. "/ref.md", {
            "[[_Legacy/sub/note-a]]",
            "[[_Legacy/sub/note-b|ref]]",
        })

        config.setup({
            root = tmp_root,
            ext = ".md",
            features = { watcher = true },
            watcher = {
                auto_update_links = true,
                prompt_on_rename = false,
                notify_on_rename = false,
                frontmatter_key = "slug",
            },
        })

        state.clear_all()
        reset_modules()
    end)

    after_each(function()
        rm_rf(tmp_root)
        state.clear_all()
        reset_modules()
    end)

    it("moves many notes and patches wikilinks once", function()
        local Notes = require("vault.notes")
        local notes = Notes()

        local report = notes:move_many({
            {
                from = tmp_root .. "/_Legacy/sub/note-a.md",
                to = tmp_root .. "/Clippings/sub/note-a.md",
            },
            {
                from = tmp_root .. "/_Legacy/sub/note-b.md",
                to = tmp_root .. "/Clippings/sub/note-b.md",
            },
        }, {
            update_links = true,
            silent = true,
            verbose = false,
        })

        assert.are.equal(2, report.moved)
        assert.are.equal(3, report.patched_files)
        assert.are.equal(0, vim.fn.filereadable(tmp_root .. "/_Legacy/sub/note-a.md"))
        assert.are.equal(1, vim.fn.filereadable(tmp_root .. "/Clippings/sub/note-a.md"))

        local note_a = read(tmp_root .. "/Clippings/sub/note-a.md")
        local note_b = read(tmp_root .. "/Clippings/sub/note-b.md")
        local ref = read(tmp_root .. "/ref.md")

        assert.is_truthy(note_a:match("slug:%s*Clippings/sub/note%-a"))
        assert.is_truthy(note_a:match("%[%[Clippings/sub/note%-b%]%]"))
        assert.is_truthy(note_b:match("%[%[Clippings/sub/note%-a|alias%]%]"))
        assert.is_truthy(ref:match("%[%[Clippings/sub/note%-a%]%]"))
        assert.is_truthy(ref:match("%[%[Clippings/sub/note%-b|ref%]%]"))
    end)

    it("moves a tree while preserving subdirectories", function()
        local Notes = require("vault.notes")
        local notes = Notes()

        local report = notes:move_tree({
            from_dir = tmp_root .. "/_Legacy",
            to_dir = tmp_root .. "/Clippings",
            update_links = true,
            preserve_subdirs = true,
            silent = true,
            verbose = false,
        })

        assert.are.equal(2, report.moved)
        assert.are.equal(1, vim.fn.filereadable(tmp_root .. "/Clippings/sub/note-b.md"))
        assert.are.equal(0, vim.fn.filereadable(tmp_root .. "/_Legacy/sub/note-b.md"))
        assert.is_truthy(read(tmp_root .. "/ref.md"):match("%[%[Clippings/sub/note%-a%]%]"))
    end)

    it("rejects collisions before moving anything", function()
        write(tmp_root .. "/Clippings/sub/note-a.md", { "existing" })

        local Notes = require("vault.notes")
        local notes = Notes()
        local ok, err = pcall(function()
            notes:move_tree({
                from_dir = tmp_root .. "/_Legacy",
                to_dir = tmp_root .. "/Clippings",
                update_links = true,
                preserve_subdirs = true,
                silent = true,
                verbose = false,
            })
        end)

        assert.is_false(ok)
        assert.is_truthy(tostring(err):match("target already exists"))
        assert.are.equal(1, vim.fn.filereadable(tmp_root .. "/_Legacy/sub/note-a.md"))
    end)
end)
