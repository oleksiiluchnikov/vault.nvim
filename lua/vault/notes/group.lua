local state = require("vault.core.state")
local error_formatter = require("vault.utils.error_formatter")
---@type VaultNotes.constructor|VaultNotes
local Notes = state.get_global_key("_class.VaultNotes") or require("vault.notes")

---@class VaultNotesGroup: VaultNotes
---@field init fun(self: VaultNotesGroup, notes: VaultNotes)
---@diagnostic disable-next-line: assign-type-mismatch
local NotesGroup = Notes:extend("VaultNotesGroup")

---@param notes VaultNotes
function NotesGroup:init(notes)
    if not notes then
        error(error_formatter.missing_parameter("notes"))
    end

    self.map = notes.map
end

---@alias VaultNotesGroup.constructor fun(notes: VaultNotes): VaultNotesGroup
---@type VaultNotesGroup.constructor|VaultNotesGroup
local VaultNotesGroup = NotesGroup

state.set_global_key("_class.VaultNotesGroup", VaultNotesGroup)
return VaultNotesGroup
