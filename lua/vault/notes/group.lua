local state = require("vault.core.state")
local error_formatter = require("vault.utils.fmt.error")
--- @type vault.Notes.constructor|vault.Notes
local Notes = state.get_global_key("class.vault.Notes") or require("vault.notes")

--- @class vault.Notes.Group: vault.Notes
--- @field init fun(self: vault.Notes.Group, notes: vault.Notes)
--- @diagnostic disable-next-line: assign-type-mismatch
local NotesGroup = Notes:extend("VaultNotesGroup")

--- @param notes vault.Notes
function NotesGroup:init(notes)
    if not notes then
        error(error_formatter.missing_parameter("notes"))
    end

    self.map = notes.map
end

--- @alias VaultNotesGroup.constructor fun(notes: vault.Notes): vault.Notes.Group
--- @type VaultNotesGroup.constructor|vault.Notes.Group
local VaultNotesGroup = NotesGroup

state.set_global_key("class.vault.NotesGroup", VaultNotesGroup)
return VaultNotesGroup
