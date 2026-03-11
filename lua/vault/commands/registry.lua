---@class vault.commands.Registry
---@field build fun(extra_tree?: table): table
---@field children_of fun(path?: string[]): table<string, table>

local M = {}

local function deep_merge_tree(dst, src)
    for key, value in pairs(src or {}) do
        if type(value) == "table" then
            if type(dst[key]) ~= "table" then
                dst[key] = {}
            end
            deep_merge_tree(dst[key], value)
        else
            dst[key] = value
        end
    end
    return dst
end

local function load_tree_from(module_name)
    local ok, mod = pcall(require, module_name)
    if not ok or type(mod) ~= "table" or type(mod.spec) ~= "function" then
        return {}
    end
    local ok_spec, spec = pcall(mod.spec)
    if not ok_spec or type(spec) ~= "table" then
        return {}
    end
    return spec
end

function M.build(extra_tree)
    local tree = {}
    deep_merge_tree(tree, load_tree_from("vault.notes.commands"))
    deep_merge_tree(tree, load_tree_from("vault.tags.commands"))
    deep_merge_tree(tree, load_tree_from("vault.properties.commands"))
    deep_merge_tree(tree, load_tree_from("vault.tasks.commands"))
    deep_merge_tree(tree, load_tree_from("vault.bases.commands"))
    deep_merge_tree(tree, load_tree_from("vault.taxonomy.commands"))
    deep_merge_tree(tree, extra_tree or {})
    return tree
end

function M.children_of(path)
    local node = M.build()
    for _, part in ipairs(path or {}) do
        local child = node[part]
        if type(child) ~= "table" then
            return {}
        end
        node = child
    end
    local out = {}
    for key, value in pairs(node) do
        if type(value) == "table" and key ~= "run" and key ~= "complete" then
            out[key] = value
        end
    end
    return out
end

return M
