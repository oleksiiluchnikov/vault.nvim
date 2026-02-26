--[[


--]]
--- @class telescope_popup_options.vault.Orphans: telescope_popup_options
--- @field notes? vault.Notes
--- @field sort_by? string

--- Search for notes in vault
--- @param opts? telescope_popup_options.vault.Orphans|table<string, any>
--- @return Picker?
return function(opts)
    return require("telescope._extensions.vault.pickers.notes")(
        vim.tbl_extend("force", opts or {}, { notes = require("vault.notes")():orphans() })
    )
end
