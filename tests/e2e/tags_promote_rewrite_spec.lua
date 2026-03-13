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

describe("vault.e2e tags promote existing-target", function()
    it("promotes a tag to an existing note via the resolve picker rewrite path", function()
        local source_root = make_vault("vault-e2e-tags-promote-rewrite", {
            ["Inbox/using-tag.md"] = {
                "---",
                'title: "using tag"',
                "tags:",
                "  - promote-target-tag",
                "---",
                "",
                "# Using tag",
                "This mentions #promote-target-tag inline.",
            },
            ["Reference/existing-canonical.md"] = {
                "---",
                'title: "existing canonical"',
                "---",
                "",
                "# Existing canonical",
                "This is the canonical note for the concept.",
            },
        })

        with_session(source_root, "tags-promote-rewrite", function(session)
            -- Open tags promote
            driver.command(session, "Vault tags promote promote-target-tag")

            -- Wait for the resolve picker
            assert.is_true(driver.wait_for(session, function()
                local ft = driver.expr(session, "&filetype")
                return ft == "TelescopePrompt"
            end, { timeout_ms = 8000 }))

            -- Type the existing canonical note name and select it
            driver.keys(session, "existing-canonical<CR>")

            -- Wait for the rewrite to complete
            assert.is_true(driver.wait_for(session, function()
                local content = table.concat(vim.fn.readfile(session.root .. "/Inbox/using-tag.md"), "\n")
                -- After promote, inline #tag should be rewritten to a wikilink
                return content:find("existing%-canonical", 1) ~= nil
                    or content:find("%[%[", 1) ~= nil
            end, { timeout_ms = 10000 }))
        end)
    end)
end)
