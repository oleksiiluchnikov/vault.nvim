---@param opts? telescope_popup_options.vault.Notes|table<string, any>
---@return Picker?
return function(opts)
    return require("telescope._extensions.vault.pickers.notes")(
        vim.tbl_extend("force", opts or {}, {
            _dynamic = true,
            _notes_provider = function()
                local state = require("vault.core.state")
                local cached = state.get_global_key("notes.linked")
                if type(cached) == "table" and type(cached.map) == "table" then
                    return cached
                end

                return require("vault.notes")():linked()
            end,
        })
    )
end
