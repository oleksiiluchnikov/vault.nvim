--- @module "busted"
local assert = require("luassert")

local config = require("vault.config")

local function write(path, lines)
    vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
    vim.fn.writefile(lines, path)
end

describe("vault.obsidian", function()
    local root

    before_each(function()
        root = vim.fn.tempname()
        vim.fn.mkdir(root, "p")
        config.reset()
        package.loaded["vault.obsidian"] = nil
    end)

    after_each(function()
        vim.fn.delete(root, "rf")
        config.reset()
        package.loaded["vault.obsidian"] = nil
    end)

    it("reads templates, daily, app, and periodic settings", function()
        write(root .. "/.obsidian/app.json", {
            "{",
            '  "newFileLocation": "folder",',
            '  "newFileFolderPath": "Inbox",',
            '  "attachmentFolderPath": "assets",',
            '  "alwaysUpdateLinks": false,',
            '  "useMarkdownLinks": true',
            "}",
        })
        write(root .. "/.obsidian/templates.json", {
            "{",
            '  "timeFormat": "HH:mm:ss",',
            '  "dateFormat": "[journal] - YYYY-MM-DD dddd",',
            '  "folder": "_templates"',
            "}",
        })
        write(root .. "/.obsidian/daily-notes.json", {
            "{",
            '  "format": "[journal] - YYYY-MM-DD dddd",',
            '  "folder": "/",',
            '  "template": "template - journal"',
            "}",
        })
        write(root .. "/.obsidian/plugins/periodic-notes/data.json", {
            "{",
            '  "weekly": {',
            '    "enabled": true,',
            '    "format": "gggg-[W]ww",',
            '    "folder": "Journal/Weekly",',
            '    "template": "template - weekly"',
            "  }",
            "}",
        })

        local obsidian = require("vault.obsidian")
        local settings = obsidian.read(root)

        assert.are.equal("folder", settings.app.new_file_location)
        assert.are.equal("Inbox", settings.app.new_file_folder)
        assert.are.equal("assets", settings.app.attachment_folder)
        assert.is_false(settings.app.always_update_links)
        assert.is_true(settings.app.use_markdown_links)
        assert.are.equal(vim.fs.normalize(root .. "/_templates"), settings.templates.folder)
        assert.are.equal("[journal] - YYYY-MM-DD dddd", settings.daily.format)
        assert.are.equal("template - journal", settings.daily.template)
        assert.are.equal("gggg-[W]ww", settings.periodic.weekly.format)
        assert.are.equal(
            vim.fs.normalize(root .. "/Journal/Weekly"),
            settings.periodic.weekly.folder
        )
    end)

    it("falls back to app daily settings when daily-notes config is absent", function()
        write(root .. "/.obsidian/app.json", {
            "{",
            '  "dailyNotesFormat": "[daily] - YYYY-MM-DD",',
            '  "dailyNotesFolder": "Journal/Daily",',
            '  "dailyNotesTemplate": "template - daily"',
            "}",
        })

        local obsidian = require("vault.obsidian")
        local settings = obsidian.read(root)

        assert.are.equal("app", settings.daily.source)
        assert.are.equal("[daily] - YYYY-MM-DD", settings.daily.format)
        assert.are.equal(vim.fs.normalize(root .. "/Journal/Daily"), settings.daily.folder)
        assert.are.equal("template - daily", settings.daily.template)
    end)

    it("renders template placeholders and derives new note paths", function()
        local obsidian = require("vault.obsidian")
        local rendered = obsidian.render_template("# {{title}}\n{{date}}\n{{time}}\n{{cursor}}", {
            ts = os.time({ year = 2026, month = 4, day = 6, hour = 9, min = 5, sec = 7 }),
            title = "journal - 2026-04-06 Monday",
            templates = {
                folder = root,
                folder_raw = "",
                date_format = "YYYY-MM-DD dddd",
                time_format = "HH:mm:ss",
            },
        })

        assert.are.equal("# journal - 2026-04-06 Monday\n2026-04-06 Monday\n09:05:07\n", rendered)

        local settings = {
            app = {
                new_file_location = "folder",
                new_file_folder = "Inbox",
            },
        }
        assert.are.equal(
            vim.fs.normalize(root .. "/Inbox/foo.md"),
            obsidian.new_note_path(root, ".md", "foo", settings, nil)
        )
    end)

    it("applies app alwaysUpdateLinks to config when user did not override it", function()
        write(root .. "/.obsidian/app.json", {
            "{",
            '  "alwaysUpdateLinks": false',
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

        assert.is_false(require("vault.config").options.watcher.auto_update_links)
    end)
end)
