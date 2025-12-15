-- Disable loading of personal config
vim.opt.runtimepath:remove(vim.fn.expand("~/.config/nvim"))
vim.opt.packpath:remove(vim.fn.expand("~/.config/nvim"))

-- Get the plugin root directory
local plugin_root = vim.fn.getcwd()

-- Function to download and set up dependencies
local function ensure_dependency(repo, directory)
    local install_path = vim.fn.stdpath("data") .. "/site/pack/deps/start/" .. directory
    if vim.fn.empty(vim.fn.glob(install_path)) > 0 then
        print("Downloading " .. repo .. " to " .. install_path)
        vim.fn.system({
            "git",
            "clone",
            "--depth",
            "1",
            "https://github.com/" .. repo .. ".git",
            install_path,
        })
    end
    vim.opt.runtimepath:prepend(install_path)
end

-- Install required dependencies
ensure_dependency("nvim-lua/plenary.nvim", "plenary.nvim")
ensure_dependency("MunifTanjim/nui.nvim", "nui.nvim") -- If you're using nui.nvim

-- Add the plugin to the runtimepath
-- Ensure plugin_root is defined (fallback to cwd) so tests don't accidentally
-- fall back to loading the user's real Neovim config (~/.config/nvim/init.lua)
if plugin_root == nil then
    plugin_root = vim.fn.getcwd()
end
vim.opt.runtimepath:prepend(plugin_root)

-- Set up package path for lua modules
package.path = plugin_root .. "/lua/?.lua;" .. package.path
package.path = plugin_root .. "/lua/?/init.lua;" .. package.path


local luassert = require("luassert")

require("plenary.busted")
require("luaassert.spy")
require("luaassert.stub")

-- Make assert available globally
_G.assert = luassert

-- Configure Neovim settings for testing
vim.opt.swapfile = false
vim.opt.backup = false
vim.opt.writebackup = false
vim.opt.hidden = true
vim.opt.termguicolors = true
vim.opt.showmode = false
vim.opt.laststatus = 2

-- Create a test configuration
local test_config = {
    vault_dir = vim.fn.getcwd() .. "/tests/fixtures/vault",
    notes = {
        extension = ".md",
    },
    templates = {
        subdir = "templates",
        date_format = "%Y-%m-%d",
        time_format = "%H:%M",
    },
    mappings = {
        -- Add your default mappings here
    },
}

-- Initialize the plugin with test configuration
require("vault").setup(test_config)

-- Create helper functions for tests
_G.t = {
    -- Helper function to create a test buffer with content
    create_test_buffer = function(content)
        local buf = vim.api.nvim_create_buf(true, true)
        vim.api.nvim_buf_set_lines(buf, 0, -1, true, vim.split(content or "", "\n"))
        return buf
    end,

    -- Helper function to clean up test buffers
    clean_buffer = function(buf)
        if buf and vim.api.nvim_buf_is_valid(buf) then
            vim.api.nvim_buf_delete(buf, { force = true })
        end
    end,

    -- Helper to create test files
    create_test_file = function(path, content)
        local full_path = test_config.vault_dir .. "/" .. path
        vim.fn.mkdir(vim.fn.fnamemodify(full_path, ":h"), "p")
        local file = io.open(full_path, "w")
        if file then
            file:write(content or "")
            file:close()
        end
    end,

    -- Helper to clean up test files
    clean_test_file = function(path)
        local full_path = test_config.vault_dir .. "/" .. path
        os.remove(full_path)
    end,
}

-- Ensure test vault directory exists
vim.fn.mkdir(test_config.vault_dir, "p")
