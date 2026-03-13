local driver = require("tests.e2e.helpers.driver")
local fixture = require("tests.e2e.helpers.fixture")
local artifacts = require("tests.e2e.helpers.artifacts")

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
        driver.stop(session)
        error(err)
    end
    driver.stop(session)
end

describe("vault.e2e classify scoped variants", function()
    local source_root
    before_each(function()
        source_root = make_vault("vault-e2e-classify-scoped", {
            ["Inbox/inbox-item.md"] = {
                "---",
                'title: "inbox item"',
                "---",
                "",
                "# Inbox item",
            },
            ["Reference/ref-item.md"] = {
                "---",
                'title: "ref item"',
                "---",
                "",
                "# Ref item",
            },
        })
    end)

    it("classify all shows notes from all directories", function()
        with_session(source_root, "classify-all", function(session)
            driver.command(session, "Vault classify all")
            assert.is_true(driver.wait_for(session, function()
                local body = driver.current_buffer_text(session)
                -- Should show notes from both directories
                return body:find("inbox item", 1, true) ~= nil
                    or body:find("ref item", 1, true) ~= nil
            end, { timeout_ms = 10000 }))
        end)
    end)

    it("classify with dir scope shows only that directory", function()
        with_session(source_root, "classify-dir", function(session)
            driver.command(session, "Vault classify Reference")
            assert.is_true(driver.wait_for(session, function()
                local body = driver.current_buffer_text(session)
                return body:find("ref item", 1, true) ~= nil
            end, { timeout_ms = 10000 }))
        end)
    end)
end)
