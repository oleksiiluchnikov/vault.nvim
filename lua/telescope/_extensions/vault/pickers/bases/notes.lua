--- @class telescope_popup_options.vault.BaseNotes: telescope_popup_options
--- @field base? vault.Base
--- @field notes? vault.Notes

--- Show matched notes for a specific base (Level 2 picker).
--- Reuses the notes picker with the base's filter applied.
--- @param opts? telescope_popup_options.vault.BaseNotes|table<string, any>
--- @return Picker?
return function(opts)
    opts = opts or {}

    if not opts.base then
        vim.notify("[vault] BaseNotes picker requires a base", vim.log.levels.ERROR)
        return
    end

    --- @type vault.Base
    local base = opts.base

    -- Load notes and apply the base filter
    local Notes = require("vault.notes")
    local notes_collection = opts.notes or Notes()

    local matched = base:match_notes(notes_collection.map)

    -- Build a new Notes collection from matched results
    local filtered_notes = Notes()
    filtered_notes.map = matched
    filtered_notes._map = matched

    -- Delegate to the notes picker with the filtered set
    local notes_picker = require("telescope._extensions.vault.pickers.notes")

    return notes_picker({
        notes = filtered_notes,
        prompt_title = base.data.name,
    })
end
