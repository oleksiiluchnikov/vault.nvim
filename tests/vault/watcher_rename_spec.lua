local Watcher = require("vault.watcher")
local config = require("vault.config")
local scanner = require("vault.scanner")
local uv = vim.loop

local tmp_vault = "./tests/tmp_vault"
local function setup_tmp_vault()
    os.execute(string.format("rm -rf %s && mkdir -p %s", tmp_vault, tmp_vault))
    -- create notes
    local f1 = io.open(tmp_vault .. "/note1.md", "w")
    f1:write("This links to [[note-old]] and [[note-old|alias]]\n")
    f1:close()

    local f2 = io.open(tmp_vault .. "/note-old.md", "w")
    f2:write("---\nslug: note-old\n---\n# Title\nContent")
    f2:close()
end

local function teardown_tmp_vault()
    os.execute(string.format("rm -rf %s", tmp_vault))
end

describe("vault.watcher rename handler", function()
    before_each(function()
        setup_tmp_vault()
        config.setup({ root = tmp_vault, features = { watcher = true }, watcher = { prompt_on_rename = false, frontmatter_key = "slug" } })
        -- refresh scanner after config is setup so it picks up the test vault root
        package.loaded["vault.scanner"] = nil
        scanner = require("vault.scanner")
        scanner._paths = nil
    end)

    after_each(function()
        teardown_tmp_vault()
    end)


    it("updates wikilinks and frontmatter on rename", function()
        local w = Watcher()
        w:start()
        -- simulate rename
        local old = tmp_vault .. "/note-old.md"
        local new = tmp_vault .. "/note-new.md"
        os.rename(old, new)
        -- call handler directly
        local patched = w:handle_rename(old, new)
        assert.are.equal(1, patched)

        -- check note1.md content
        local f = io.open(tmp_vault .. "/note1.md", "r")
        local content = f:read("*all")
        f:close()
        assert.is_true(content:match("%[%[note%-new") ~= nil)

        -- check frontmatter in new file
        local f2 = io.open(new, "r")
        local ncontent = f2:read("*all")
        f2:close()
        assert.is_true(ncontent:match("slug:%s*note%-new") ~= nil)

        w:stop()
    end)
end)
