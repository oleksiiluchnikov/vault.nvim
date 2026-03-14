local artifacts = require("tests.e2e.helpers.artifacts")
local driver = require("tests.e2e.helpers.driver")
local fixture = require("tests.e2e.helpers.fixture")

local function write(path, lines)
    vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
    vim.fn.writefile(lines, path)
end

local function make_vault(name, files)
    local root = fixture.make_temp_dir(name)
    for relpath, lines in pairs(files) do
        write(root .. "/" .. relpath, lines)
    end
    return root
end

local function with_session(source_root, scenario, fn)
    local session = driver.start({ source_root = source_root, scenario = scenario })
    local ok, err = pcall(fn, session)
    if not ok then
        driver.capture(session)
        artifacts.write_vault_diff(session.artifacts_dir, source_root, session.root)
        driver.stop(session)
        error(err)
    end
    driver.stop(session)
end

describe("vault.e2e notes filter variants", function()
    local source_root

    before_each(function()
        source_root = make_vault("vault-e2e-notes-filter-variants", {
            ["Inbox/root-note.md"] = {
                "---",
                'title: "root note"',
                "tags:",
                "---",
                "",
                "# Root note",
                "Links to [[Inbox/linked-target]].",
                "Also links to [[Missing Note]].",
            },
            ["Inbox/linked-target.md"] = {
                "---",
                'title: "linked target"',
                'status: "active"',
                "---",
                "",
                "# Linked target",
                "Backlinks from [[Inbox/root-note]].",
            },
            ["Inbox/no-frontmatter.md"] = {
                "# No frontmatter",
                "Body only.",
            },
            ["Projects/internal-note.md"] = {
                "---",
                'title: "internal note"',
                'tags: [project]',
                "---",
                "",
                "# Internal note",
            },
            ["Inbox/empty-tags-note.md"] = {
                "---",
                'title: "empty tags note"',
                'tags: ""',
                "---",
                "",
                "# Empty tags note",
            },
            ["Archive/empty-body.md"] = {
                "---",
                'title: "empty body"',
                'status: "archived"',
                "---",
            },
            ["Inbox/blank.md"] = { "" },
        })
    end)

    local function smoke_picker(cmd, scenario)
        with_session(source_root, scenario, function(session)
            driver.lua(session, string.format([[
                local ok, err = pcall(vim.cmd, %q)
                vim.g._filter_ok = ok and "1" or "0"
                vim.g._filter_err = tostring(err or "")
            ]], cmd))

            assert.is_true(driver.wait_for(session, function()
                return driver.expr(session, "g:_filter_ok") == "1"
            end, { timeout_ms = 10000 }))

            local ft = driver.expr(session, "&filetype")
            if ft == "TelescopePrompt" then
                driver.keys(session, "<Esc>")
            end
        end)
    end

    it("opens notes linked without error", function()
        smoke_picker("Vault notes linked", "notes-linked")
    end)

    it("opens notes internals without error", function()
        smoke_picker("Vault notes internals", "notes-internals")
    end)

    it("opens notes dangling without error", function()
        smoke_picker("Vault notes dangling", "notes-dangling")
    end)

    it("opens notes dir Inbox without error", function()
        smoke_picker("Vault notes dir Inbox", "notes-dir-inbox")
    end)

    it("opens notes empty-property tags without error", function()
        smoke_picker("Vault notes empty-property tags", "notes-empty-property-tags")
    end)

    it("opens notes empty without error", function()
        smoke_picker("Vault notes empty", "notes-empty")
    end)

    it("opens notes no-frontmatter without error", function()
        smoke_picker("Vault notes no-frontmatter", "notes-no-frontmatter")
    end)
end)
