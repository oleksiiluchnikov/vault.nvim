local cfg = require("vault.config").options or {}
local telescope_opts = (cfg.telescope and cfg.telescope.pickers) or {}

---@param method_name string
---@param cache_key? string
---@return fun(opts?: table<string, any>): Picker?
local function note_group_picker(method_name, cache_key)
    return function(opts)
        return require("telescope._extensions.vault.pickers.notes")(
            vim.tbl_deep_extend("force", opts or {}, {
                _dynamic = true,
                _notes_provider = function()
                    local state = require("vault.core.state")
                    local cached = cache_key and state.get_global_key(cache_key) or nil
                    if type(cached) == "table" and type(cached.map) == "table" then
                        return cached
                    end

                    local notes = require("vault.notes")()
                    return notes[method_name](notes)
                end,
            })
        )
    end
end

return setmetatable(
    vim.tbl_deep_extend("force", telescope_opts, {
        linked = require("telescope._extensions.vault.pickers.linked"),
        orphans = require("telescope._extensions.vault.pickers.orphans"),
        leaves = note_group_picker("leaves", "notes.leaves"),
        internals = note_group_picker("internals", "notes.internals"),
        with_outlinks_resolved_only = note_group_picker("with_outlinks_resolved_only"),
        with_outlinks_unresolved = note_group_picker("with_outlinks_unresolved"),
    }),
    {
        __index = function(_, key)
            return function(opts)
                local mod_path = string.format("telescope._extensions.vault.pickers.%s", key)
                local ok, picker = pcall(require, mod_path)
                if not ok then
                    local log = require("vault.log").scope("telescope")
                    log.error(
                        "Unknown picker '%s' (failed to require '%s'): %s",
                        key,
                        mod_path,
                        tostring(picker)
                    )
                    error(string.format("vault: unknown picker '%s'", key))
                    return
                end
                return picker(opts)
            end
        end,
    }
)
