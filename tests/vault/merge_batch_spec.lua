local config = require("vault.config")
local state = require("vault.core.state")

local tmp_root = vim.fn.getcwd() .. "/tests/tmp_merge_batch_vault"

local function reset_modules()
    package.loaded["vault.notes"] = nil
    package.loaded["vault.scanner"] = nil
    package.loaded["vault.watcher"] = nil
    package.loaded["vault.merge"] = nil
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

describe("vault.merge.safe_absorb_many", function()
    before_each(function()
        rm_rf(tmp_root)
        vim.fn.mkdir(tmp_root, "p")

        write(tmp_root .. "/Inbox/note-a.md", {
            "---",
            "title: note a",
            "created: 20240101000000",
            "---",
            "# note-a",
            "body",
        })
        write(tmp_root .. "/Inbox/note-a 1.md", {
            "---",
            "title: note a",
            "score: 0",
            "created: 20250101000000",
            "---",
            "# note-a 1",
            "body",
        })
        write(tmp_root .. "/Inbox/note-b.md", {
            "---",
            "title: note b",
            "created: 20240102000000",
            "---",
            "# note-b",
            "same",
        })
        write(tmp_root .. "/Inbox/note-b 1.md", {
            "---",
            "title: note b",
            "score: 1",
            "created: 20250102000000",
            "---",
            "# note-b 1",
            "same",
        })
        write(tmp_root .. "/ref.md", {
            "[[Inbox/note-a 1|alias a]]",
            "[[Inbox/note-b 1]]",
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

    it("batch rewrites links once and trashes sources", function()
        local merge = require("vault.merge")

        local result = merge.safe_absorb_many({
            {
                target_path = tmp_root .. "/Inbox/note-a.md",
                source_path = tmp_root .. "/Inbox/note-a 1.md",
            },
            {
                target_path = tmp_root .. "/Inbox/note-b.md",
                source_path = tmp_root .. "/Inbox/note-b 1.md",
            },
        }, { silent = true })

        assert.are.equal(2, result.applied)
        assert.are.equal(1, result.patched)
        assert.are.equal(2, result.trashed)
        assert.are.equal(0, result.skipped)

        local note_a = read(tmp_root .. "/Inbox/note-a.md")
        local note_b = read(tmp_root .. "/Inbox/note-b.md")
        local ref = read(tmp_root .. "/ref.md")

        assert.is_truthy(note_a:match("score:%s*1") or note_a:match("score:%s*0"))
        assert.is_truthy(note_b:match("score:%s*1"))
        assert.is_truthy(ref:match("%[%[Inbox/note%-a|alias a%]%]"))
        assert.is_truthy(ref:match("%[%[Inbox/note%-b%]%]"))
        assert.are.equal(0, vim.fn.filereadable(tmp_root .. "/Inbox/note-a 1.md"))
        assert.are.equal(0, vim.fn.filereadable(tmp_root .. "/Inbox/note-b 1.md"))
        assert.are.equal(1, vim.fn.filereadable(tmp_root .. "/.trash/note-a 1.md"))
        assert.are.equal(1, vim.fn.filereadable(tmp_root .. "/.trash/note-b 1.md"))
    end)

    it("batch applies prepared merged lines with one rewrite pass", function()
        local merge = require("vault.merge")

        local result = merge.absorb_many({
            {
                target_path = tmp_root .. "/Inbox/note-a.md",
                source_path = tmp_root .. "/Inbox/note-a 1.md",
                merged_lines = {
                    "---",
                    "title: note a",
                    "score: 0",
                    "---",
                    "# note-a",
                    "body",
                },
            },
            {
                target_path = tmp_root .. "/Inbox/note-b.md",
                source_path = tmp_root .. "/Inbox/note-b 1.md",
                merged_lines = {
                    "---",
                    "title: note b",
                    "score: 1",
                    "---",
                    "# note-b",
                    "same",
                },
            },
        }, { silent = true })

        assert.are.equal(2, result.applied)
        assert.are.equal(1, result.patched)
        assert.are.equal(2, result.trashed)
        assert.are.equal(0, result.skipped)

        local note_a = read(tmp_root .. "/Inbox/note-a.md")
        local ref = read(tmp_root .. "/ref.md")
        assert.is_truthy(note_a:match("score:%s*0"))
        assert.is_truthy(ref:match("%[%[Inbox/note%-a|alias a%]%]"))
        assert.are.equal(0, vim.fn.filereadable(tmp_root .. "/Inbox/note-a 1.md"))
    end)
end)
