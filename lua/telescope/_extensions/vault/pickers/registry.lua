local M = {}

local defaults = {
    { name = "notes", description = "Browse and search through all notes" },
    { name = "tasks", description = "Search and manage tasks across notes" },
    { name = "properties", description = "Search for properties and values" },
    { name = "dirs", description = "Browse notes by directory structure" },
    { name = "orphans", description = "Find notes without internal links" },
    { name = "tags", description = "Search and navigate through tags" },
    { name = "linked", description = "Find and navigate between linked notes" },
    { name = "wikilinks", description = "Find unresolved wikilinks and rewrite targets" },
    { name = "bases", description = "Browse Obsidian base database views" },
    { name = "dates", description = "Browse notes by date references" },
    { name = "grep", description = "Live grep inside the vault" },
    { name = "inbox", description = "Browse inbox notes" },
    { name = "lines", description = "Search note lines" },
    { name = "leaves", description = "Browse notes without outlinks" },
    { name = "internals", description = "Browse internally-linked notes" },
    {
        name = "with_outlinks_resolved_only",
        description = "Browse notes with only resolved outlinks",
    },
    { name = "with_outlinks_unresolved", description = "Browse notes with unresolved outlinks" },
}

local function configured_registry()
    local cfg = require("vault.config").options or {}
    local telescope = cfg.telescope or {}
    return telescope.picker_registry or telescope.pickers_meta or {}
end

local function configured_pickers()
    local cfg = require("vault.config").options or {}
    local telescope = cfg.telescope or {}
    return telescope.pickers or {}
end

local function normalize(name, spec)
    if type(spec) == "string" then
        return { name = name or spec, description = spec }
    end

    spec = type(spec) == "table" and vim.deepcopy(spec) or {}
    spec.name = spec.name or name
    spec.description = spec.description or ""
    return spec
end

function M.entries()
    local by_name = {}
    local out = {}

    local function add(name, spec)
        local entry = normalize(name, spec)
        if type(entry.name) ~= "string" or entry.name == "" then
            return
        end

        if by_name[entry.name] then
            by_name[entry.name] = vim.tbl_deep_extend("force", by_name[entry.name], entry)
            return
        end

        by_name[entry.name] = entry
        out[#out + 1] = entry
    end

    for _, spec in ipairs(defaults) do
        add(spec.name, spec)
    end

    for name, spec in pairs(configured_registry()) do
        add(name, spec)
    end

    for name, picker in pairs(configured_pickers()) do
        if type(name) == "string" and type(picker) == "function" and not by_name[name] then
            add(name, { description = "" })
        end
    end

    table.sort(out, function(a, b)
        local ai = tonumber(a.order or a.index or math.huge)
        local bi = tonumber(b.order or b.index or math.huge)
        if ai ~= bi then
            return ai < bi
        end
        return a.name < b.name
    end)

    return out
end

function M.resolve(name)
    local pickers = require("telescope._extensions.vault.pickers")
    return pickers[name]
end

return M
