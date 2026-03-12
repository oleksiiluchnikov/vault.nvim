---@class vault.e2e.Artifacts

local M = {}

local function system_capture(cmd, opts)
    return vim.system(cmd, vim.tbl_extend("force", { text = true }, opts or {})):wait()
end

---@param scenario string
---@return string
function M.create_dir(scenario)
    local root = vim.fn.getcwd() .. "/tests/.artifacts/e2e"
    vim.fn.mkdir(root, "p")
    local safe = (scenario or "scenario"):gsub("[^A-Za-z0-9._-]", "-")
    local dir = string.format("%s/%s-%s", root, os.date("%Y%m%d%H%M%S"), safe)
    vim.fn.mkdir(dir, "p")
    return dir
end

---@param dir string
---@param name string
---@param text string
function M.write_text(dir, name, text)
    vim.fn.mkdir(dir, "p")
    vim.fn.writefile(vim.split(text or "", "\n", { plain = true }), dir .. "/" .. name)
end

---@param dir string
---@param source_root string
---@param clone_root string
function M.write_vault_diff(dir, source_root, clone_root)
    local result = system_capture({ "git", "diff", "--no-index", "--", source_root, clone_root })
    local diff = result.stdout or ""
    if result.code ~= 0 and diff == "" then
        diff = result.stderr or ""
    end
    M.write_text(dir, "vault-diff.txt", diff)
end

return M
