-- tests/minimal_init.lua

-- 1. ISOLATION
-- Prevent loading user's personal config
vim.env.NVIM_APPNAME = "nvim-test"
vim.opt.runtimepath:remove(vim.fn.expand("~/.config/nvim"))
vim.opt.packpath:remove(vim.fn.expand("~/.local/share/nvim/site"))

-- 2. DEPENDENCY MANAGEMENT
-- Define a local directory for test dependencies
local root_cwd = vim.fn.getcwd()
local test_dir = root_cwd .. "/.tests"
local pack_dir = test_dir .. "/site/pack/deps/start"

-- Ensure directory exists
vim.fn.mkdir(pack_dir, "p")
vim.opt.packpath = test_dir .. "/site"

local function ensure_plugin(repo)
    local name = vim.fn.fnamemodify(repo, ":t")
    local install_path = pack_dir .. "/" .. name
    if vim.fn.isdirectory(install_path) == 0 then
        print("Installing " .. repo .. "...")
        vim.fn.system({ "git", "clone", "--depth=1", "https://github.com/" .. repo, install_path })
    end
    vim.opt.runtimepath:append(install_path)
end

-- Install required plugins
ensure_plugin("nvim-lua/plenary.nvim")
ensure_plugin("nvim-telescope/telescope.nvim")
ensure_plugin("MunifTanjim/nui.nvim")
ensure_plugin("hrsh7th/nvim-cmp")
-- Custom dependencies found in your code
ensure_plugin("oleksiiluchnikov/gradient.nvim")
ensure_plugin("oleksiiluchnikov/dates.nvim")

-- Add teolog.nvim to runtimepath (structured logging backend)
local teolog_path = vim.fn.expand("~/projects/teolog.nvim")
if vim.fn.isdirectory(teolog_path) == 1 then
  vim.opt.runtimepath:append(teolog_path)
end

-- Add current plugin to runtimepath
vim.opt.runtimepath:prepend(root_cwd)

-- 3. CONFIGURATION
vim.opt.swapfile = false
vim.opt.termguicolors = true
vim.o.hidden = true

-- Make assertions available globally for convenience
_G.assert = require("luassert")

-- 4. SETUP VAULT WITH FIXTURES
local fixture_root = root_cwd .. "/tests/fixtures/demo-vault"

-- Ensure the fixture directory actually exists to prevent crashes
if vim.fn.isdirectory(fixture_root) == 0 then
    vim.notify("Warning: Demo vault not found at " .. fixture_root, vim.log.levels.WARN)
    vim.fn.mkdir(fixture_root, "p")
end

require("vault").setup({
    root = fixture_root,
    ext = ".md",

    -- Disable features that might cause async noise during tests
    features = {
        cmp = false, -- Enable if testing completions specifically
        commands = true,
        watcher = false, -- Watchers rely on uv loop, can be flaky in simple tests
    },

    tags = {
        valid = { hex = true },
    },

    -- Ensure we don't write to standard cache paths during test
    search_tool = "rg",
})

-- 5. TEST HELPERS
_G.t = {}

-- Helper to read file content for assertions
function _G.t.read_file(path)
    local p = fixture_root .. "/" .. path
    if vim.fn.filereadable(p) == 0 then
        return nil
    end
    return vim.fn.readfile(p)
end

-- Helper to get absolute path in demo vault
function _G.t.path(relpath)
    return fixture_root .. "/" .. relpath
end
