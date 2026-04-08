--- @module "busted"
local assert = require("luassert")

local config = require("vault.config")

local function write(path, lines)
    vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
    vim.fn.writefile(lines, path)
end

describe("vault.journal", function()
    local root

    before_each(function()
        root = vim.fn.tempname()
        vim.fn.mkdir(root, "p")
        config.reset()
        package.loaded["vault.journal"] = nil
    end)

    after_each(function()
        vim.fn.delete(root, "rf")
        config.reset()
        package.loaded["vault.journal"] = nil
    end)

    it("uses Obsidian daily-notes.json format and folder", function()
        write(root .. "/.obsidian/daily-notes.json", {
            "{",
            '  "format": "[journal] - YYYY-MM-DD dddd",',
            '  "folder": "/"',
            "}",
        })

        require("vault").setup({
            root = root,
            features = {
                cmp = false,
                commands = false,
                watcher = false,
            },
        })

        local journal = require("vault.journal")
        local settings = journal.settings()

        assert.are.equal("obsidian", settings.source)
        assert.are.equal(vim.fs.normalize(root), settings.dir)
        assert.are.equal("journal - 2026-04-06 Monday", journal.basename("2026-04-06", settings))
        assert.are.equal(
            vim.fs.normalize(root .. "/journal - 2026-04-06 Monday.md"),
            journal.path("2026-04-06", settings)
        )
    end)

    it("renders the Obsidian daily template when creating a journal note", function()
        write(root .. "/.obsidian/daily-notes.json", {
            "{",
            '  "format": "[journal] - YYYY-MM-DD dddd",',
            '  "folder": "/",',
            '  "template": "template - journal"',
            "}",
        })
        write(root .. "/.obsidian/templates.json", {
            "{",
            '  "timeFormat": "HH:mm:ss",',
            '  "dateFormat": "YYYY-MM-DD dddd",',
            '  "folder": ""',
            "}",
        })
        write(root .. "/template - journal.md", {
            "# {{title}}",
            "- {{date}}",
            "- {{time}}",
            "{{cursor}}",
        })

        require("vault").setup({
            root = root,
            features = {
                cmp = false,
                commands = false,
                watcher = false,
            },
        })

        local journal = require("vault.journal")
        local content = journal.initial_content("2026-04-06")

        assert.are.equal(
            "# journal - 2026-04-06 Monday\n- 2026-04-06 Monday\n- 12:00:00\n",
            content
        )
    end)

    it("falls back to legacy journal.daily directory when Obsidian settings are absent", function()
        require("vault").setup({
            root = root,
            dirs = {
                journal = {
                    daily = "Journal/Daily",
                },
            },
            features = {
                cmp = false,
                commands = false,
                watcher = false,
            },
        })

        local journal = require("vault.journal")
        local settings = journal.settings()

        assert.are.equal("legacy", settings.source)
        assert.are.equal(vim.fs.normalize(root .. "/Journal/Daily"), settings.dir)
        assert.are.equal("2026-04-06 Monday", journal.basename("2026-04-06", settings))
        assert.are.equal(
            vim.fs.normalize(root .. "/Journal/Daily/2026-04-06 Monday.md"),
            journal.path("2026-04-06", settings)
        )
    end)
end)
