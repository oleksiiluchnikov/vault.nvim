---@class vault.e2e.Fixture

local M = {}

local function system_ok(cmd, opts)
    local result = vim.system(cmd, vim.tbl_extend("force", { text = true }, opts or {})):wait()
    if result.code ~= 0 then
        error((result.stderr and result.stderr ~= "" and result.stderr) or (result.stdout or "command failed"))
    end
    return result
end

---@param path string
---@return string
local function expand(path)
    return vim.fn.resolve(vim.fn.expand(path))
end

---@return string
function M.repo_root()
    return vim.fn.getcwd()
end

---@return string
function M.default_source_vault()
    return M.repo_root() .. "/tests/fixtures/demo-vault"
end

---@param path string
---@return boolean
function M.is_live_knowledge_root(path)
    return expand(path) == expand("~/knowledge")
end

---@param path string
function M.assert_not_live_target(path)
    if M.is_live_knowledge_root(path) then
        error("E2E must never target the live ~/knowledge vault")
    end
end

---@param prefix string
---@return string
function M.make_temp_dir(prefix)
    local dir = vim.fn.tempname() .. "-" .. (prefix or "vault-e2e")
    vim.fn.mkdir(dir, "p")
    return dir
end

---@param source_root string
---@param opts? { prefix?: string }
---@return string
function M.clone_vault(source_root, opts)
    opts = opts or {}
    source_root = expand(source_root)
    if vim.fn.isdirectory(source_root) == 0 then
        error("Source vault does not exist: " .. source_root)
    end
    local clone_root = M.make_temp_dir(opts.prefix or "vault-e2e-vault")
    M.assert_not_live_target(clone_root)
    system_ok({ "cp", "-R", source_root .. "/.", clone_root })
    return clone_root
end

return M
