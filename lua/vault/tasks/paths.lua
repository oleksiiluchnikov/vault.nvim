local M = {}

--- Return the absolute path to the vault root (with symlinks resolved).
--- @return string
function M.vault_root()
    local root = require("vault.config").options.root
    return vim.fn.resolve(vim.fn.expand(root))
end

--- Return the relative path of the tasks directory inside the vault.
--- @return string
function M.tasks_dir_rel()
    return require("vault.tasks.config").tasks_dir_rel()
end

--- Return the absolute filesystem path of the tasks directory.
--- @return string
function M.tasks_dir_abs()
    return M.vault_root() .. "/" .. M.tasks_dir_rel()
end

--- Extract the filename stem (no directory, no extension) from an absolute path.
--- @param path string Absolute filesystem path.
--- @return string
function M.stem_from_path(path)
    return vim.fn.fnamemodify(path, ":t:r")
end

return M
