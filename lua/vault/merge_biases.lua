local config = require("vault.config")
local log = require("vault.log").scope("merge_biases")

local M = {}

local DEFAULT_PATH = vim.fn.stdpath("data") .. "/vault/merge_conflict_biases.lua"
local VALID_BIASES = {
    a = true,
    b = true,
    earliest = true,
    latest = true,
}

---@class vault.merge_biases.Config
---@field enabled boolean
---@field path string
---@field behavior "preselect"|"auto_apply"

---@return vault.merge_biases.Config
local function settings()
    local configured = config.options.merge and config.options.merge.learned_conflict_biases or {}
    return {
        enabled = configured.enabled ~= false,
        path = configured.path or DEFAULT_PATH,
        behavior = configured.behavior == "preselect" and "preselect" or "auto_apply",
    }
end

---@param path string
local function ensure_parent_dir(path)
    local dir = vim.fn.fnamemodify(path, ":h")
    if vim.fn.isdirectory(dir) == 0 then
        vim.fn.mkdir(dir, "p")
    end
end

---@param bias any
---@return boolean
function M.is_valid_bias(bias)
    return VALID_BIASES[tostring(bias)] == true
end

---@return string
function M.path()
    return settings().path
end

---@return boolean
function M.enabled()
    return settings().enabled
end

---@return "preselect"|"auto_apply"
function M.behavior()
    return settings().behavior
end

---@param biases table<string, string>
---@return string[]
local function serialize_biases(biases)
    local keys = vim.tbl_keys(biases)
    table.sort(keys)

    local lines = {
        "-- Learned conflict bias preferences for vault.nvim.",
        '-- Valid values: "a", "b", "earliest", "latest".',
        "-- Edit this file directly or use :Vault merge biases.",
        "return {",
    }

    for _, key in ipairs(keys) do
        local bias = biases[key]
        if M.is_valid_bias(bias) then
            lines[#lines + 1] = string.format("  [%q] = %q,", key, bias)
        end
    end

    lines[#lines + 1] = "}"
    return lines
end

---@return nil
function M.ensure_file()
    local path = M.path()
    if vim.fn.filereadable(path) == 1 then
        return
    end

    ensure_parent_dir(path)
    vim.fn.writefile(serialize_biases({}), path)
end

---@return table<string, string>
function M.load()
    if not M.enabled() then
        return {}
    end

    local path = M.path()
    if vim.fn.filereadable(path) == 0 then
        return {}
    end

    local chunk, err = loadfile(path)
    if not chunk then
        log.warn("Could not load learned conflict biases from %s: %s", path, tostring(err))
        return {}
    end

    local ok, loaded = pcall(chunk)
    if not ok then
        log.warn("Error evaluating learned conflict biases from %s: %s", path, tostring(loaded))
        return {}
    end
    if type(loaded) ~= "table" then
        log.warn("Learned conflict biases file must return a table: %s", path)
        return {}
    end

    ---@type table<string, string>
    local result = {}
    for key, bias in pairs(loaded) do
        if type(key) == "string" and M.is_valid_bias(bias) then
            result[key] = tostring(bias)
        end
    end
    return result
end

---@param biases table<string, string>
---@return nil
function M.save(biases)
    local path = M.path()
    ensure_parent_dir(path)
    vim.fn.writefile(serialize_biases(biases), path)
end

---@param field string
---@param bias string
---@return nil
function M.remember(field, bias)
    if not M.enabled() or not M.is_valid_bias(bias) then
        return
    end

    local biases = M.load()
    biases[field] = bias
    M.save(biases)
end

---@param field string
---@return string|nil
function M.get(field)
    return M.load()[field]
end

---@return nil
function M.open()
    M.ensure_file()
    vim.cmd("edit " .. vim.fn.fnameescape(M.path()))
end

return M
