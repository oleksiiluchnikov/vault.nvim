-- tests/vault/scanner/wikilink_filtering_spec.lua
--
-- Tests that the Rust scanner correctly rejects false-positive wikilinks:
--   1. Bash [[ ... ]] conditionals (leading/trailing whitespace)
--   2. Wikilinks inside inline backticks (`[[note]]`)
--   3. Wikilinks inside fenced code blocks (already handled)
--
-- Uses tests/fixtures/demo-vault/shell_and_code_test.md as the fixture.

local assert = require("luassert")

local root_cwd = vim.fn.getcwd()
local fixture_root = root_cwd .. "/tests/fixtures/demo-vault"

--- Fresh setup for each describe block.
local function setup_vault()
    -- Clear cached modules
    for k, _ in pairs(package.loaded) do
        if k:match("^vault") then
            package.loaded[k] = nil
        end
    end

    require("vault").setup({
        root = fixture_root,
        ext = ".md",
        features = {
            cmp = false,
            commands = true,
            watcher = false,
        },
        tags = {
            valid = { hex = true },
        },
        search_tool = "rg",
    })
end

-- ─── Rust scanner level ─────────────────────────────────────────────────────

describe("Rust scanner wikilink filtering:", function()
    local scan_data

    before_each(function()
        setup_vault()
        local core = require("vault_core")
        local config = require("vault.config")
        local root = vim.fn.expand(config.options.root)
        local ignores = config.options.ignore or {}
        scan_data = core.scan(root, ignores)
    end)

    -- Helper: find the parsed note for our fixture
    local function find_fixture_note()
        for _, note in ipairs(scan_data) do
            if note.path:match("shell_and_code_test%.md$") then
                return note
            end
        end
        return nil
    end

    it("finds the shell_and_code_test fixture note", function()
        local note = find_fixture_note()
        assert.is_not_nil(note, "shell_and_code_test.md should be found by scanner")
    end)

    it("extracts real wikilinks (test_note, README, Project/My new masterpeace)", function()
        local note = find_fixture_note()
        assert.is_not_nil(note)

        local stems = {}
        for _, wl in ipairs(note.wikilinks) do
            stems[wl.target] = true
        end

        assert.is_true(stems["test_note"] ~= nil, "should extract [[test_note]]")
        assert.is_true(stems["README"] ~= nil, "should extract [[README]]")
        assert.is_true(stems["Project/My new masterpeace"] ~= nil, "should extract [[Project/My new masterpeace]]")
    end)

    it("rejects bash conditionals with leading whitespace: [[ -d ... ]]", function()
        local note = find_fixture_note()
        assert.is_not_nil(note)

        -- These are unfenced bash lines in the fixture:
        -- [[ -d "$MOUNT_POINT" ]] && mount_drive
        -- [[ ! "$title" =~ ^[A-Z] ]] && fix_title
        -- And inline: `[[ -d "$path" ]]`, `[[ ! -f "$file" ]]`
        local bad_stems = {
            ' -d "$MOUNT_POINT" ',
            ' ! "$title" =~ ^[A-Z] ',
            ' -d "$path" ',
            ' ! -f "$file" ',
            ' -d "$TARGET_PATH" ',
            ' ! -f "$HOME/.config" ',
        }

        for _, wl in ipairs(note.wikilinks) do
            for _, bad in ipairs(bad_stems) do
                assert.is_not.equals(
                    wl.target,
                    bad,
                    "should NOT extract bash conditional as wikilink: " .. vim.inspect(bad)
                )
            end
            -- General check: no extracted wikilink should start with whitespace
            assert.is_false(
                wl.target:match("^%s") ~= nil,
                "wikilink target should not start with whitespace: " .. vim.inspect(wl.target)
            )
        end
    end)

    it("rejects wikilinks inside inline backticks: `[[some note]]`", function()
        local note = find_fixture_note()
        assert.is_not_nil(note)

        local stems = {}
        for _, wl in ipairs(note.wikilinks) do
            stems[wl.target] = true
        end

        -- These appear inside backticks in the fixture
        assert.is_nil(stems["some note"], "should NOT extract [[some note]] from inline code")
        assert.is_nil(stems["another note"], "should NOT extract [[another note]] from double-backtick code")
        assert.is_nil(stems["embedded link"], "should NOT extract [[embedded link]] from inline code")
    end)

    it("extracts real tags but not tags inside inline backticks", function()
        local note = find_fixture_note()
        assert.is_not_nil(note)

        local tag_names = {}
        for _, tag in ipairs(note.tags) do
            tag_names[tag.name] = true
        end

        -- Real tags in the fixture
        assert.is_true(tag_names["real-tag"] ~= nil, "should extract #real-tag")
        assert.is_true(tag_names["shell-syntax"] ~= nil, "should extract #shell-syntax")
        assert.is_true(tag_names["inline-code-test"] ~= nil, "should extract #inline-code-test")

        -- Tag inside backticks should be skipped
        assert.is_nil(tag_names["not-a-tag"], "should NOT extract #not-a-tag from inline code")
    end)

    it("does not extract any wikilinks from fenced code blocks", function()
        local note = find_fixture_note()
        assert.is_not_nil(note)

        -- The fenced code block contains [[ -d "$TARGET_PATH" ]], [[ ! -f ... ]], etc.
        -- None should appear (fenced code skip is existing behavior)
        local stems = {}
        for _, wl in ipairs(note.wikilinks) do
            stems[wl.target] = true
        end

        assert.is_nil(stems[' -d "$TARGET_PATH" '], "fenced block bash should not be extracted")
        assert.is_nil(stems['"$var" =~ ^[0-9]+$ '], "fenced block bash should not be extracted")
    end)

    it("total wikilink count is exactly 3 (the three real links)", function()
        local note = find_fixture_note()
        assert.is_not_nil(note)
        assert.equals(3, #note.wikilinks, "should have exactly 3 real wikilinks, got: " .. vim.inspect(note.wikilinks))
    end)
end)

-- ─── Config ignore list ─────────────────────────────────────────────────────

describe("Default ignore list includes node_modules:", function()
    before_each(function()
        setup_vault()
    end)

    it("default ignore patterns contain node_modules/*", function()
        local config = require("vault.config")
        local ignores = config.options.ignore or {}
        local found = false
        for _, pat in ipairs(ignores) do
            if pat:match("node_modules") then
                found = true
                break
            end
        end
        assert.is_true(found, "ignore list should include node_modules/*")
    end)

    it("node_modules directory is not traversed by scanner", function()
        -- Create a temp node_modules dir with a .md file inside the fixture vault
        local nm_dir = fixture_root .. "/node_modules/fake-pkg"
        vim.fn.mkdir(nm_dir, "p")
        local fake_md = nm_dir .. "/README.md"
        vim.fn.writefile({ "---", "---", "# Fake package", "See [[fake-link]]" }, fake_md)

        -- Scan
        local core = require("vault_core")
        local config = require("vault.config")
        local root = vim.fn.expand(config.options.root)
        local ignores = config.options.ignore or {}
        local data = core.scan(root, ignores)

        -- Verify the fake note is NOT in results
        local found = false
        for _, note in ipairs(data) do
            if note.path:match("node_modules") then
                found = true
                break
            end
        end

        -- Cleanup
        vim.fn.delete(fixture_root .. "/node_modules", "rf")

        assert.is_false(found, "node_modules files should be ignored by scanner")
    end)
end)
