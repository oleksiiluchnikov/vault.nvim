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

describe("vault.e2e process advanced filters", function()
    local source_root

    before_each(function()
        source_root = make_vault("vault-e2e-process-advanced-filters", {
            ["Inbox/missing-tags.md"] = {
                "---",
                'title: "missing tags"',
                'status: "active"',
                "---",
                "",
                "# Missing tags",
            },
            ["Inbox/has-tags.md"] = {
                "---",
                'title: "has tags"',
                'status: "active"',
                'tags: "tagged"',
                "---",
                "",
                "# Has tags",
            },
            ["Reference/done-note.md"] = {
                "---",
                'title: "done note"',
                'status: "done"',
                "---",
                "",
                "# Done note",
            },
        })
    end)

    it("opens a filtered process grid for notes without tags", function()
        with_session(source_root, "process-advanced-without-property", function(session)
            driver.command(session, "Vault process title,status without-property=tags")

            assert.is_true(driver.wait_for(session, function()
                local body = driver.current_buffer_text(session)
                return body:find("missing tags", 1, true) ~= nil
                    and body:find("done note", 1, true) ~= nil
                    and body:find("has tags", 1, true) == nil
            end, { timeout_ms = 10000 }))
        end)
    end)

    it("opens a grouped process grid", function()
        with_session(source_root, "process-advanced-group-by", function(session)
            driver.command(session, "Vault process title,status group_by=status")

            assert.is_true(driver.wait_for(session, function()
                local body = driver.current_buffer_text(session)
                return body:find("missing tags", 1, true) ~= nil
                    and body:find("has tags", 1, true) ~= nil
                    and body:find("done note", 1, true) ~= nil
            end, { timeout_ms = 10000 }))

            assert.is_true(driver.wait_for(session, function()
                local fold_count = tonumber(driver.expr(session, "luaeval('vim.fn.foldlevel(2)')")) or 0
                local fold_enabled = driver.expr(session, "&foldenable")
                return fold_enabled == "1" or fold_count > 0
            end, { timeout_ms = 5000 }))
        end)
    end)
end)
