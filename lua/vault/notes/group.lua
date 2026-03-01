local state = require("vault.core.state")
local error_formatter = require("vault.utils.error")

--- @type vault.Notes.constructor|vault.Notes
local Notes = state.get_global_key("class.vault.Notes") or require("vault.notes")

--- @class vault.Notes.Group: vault.Notes
local NotesGroup = Notes:extend("VaultNotesGroup")

--- @param notes vault.Notes
function NotesGroup:init(notes)
    if not notes then
        error(error_formatter.MISSING_PARAMETER("notes"))
    end

    self.map = {}
    for k, v in pairs(notes.map) do
        self.map[k] = v
    end
end

local VaultNotesGroup = NotesGroup

state.set_global_key("class.vault.NotesGroup", VaultNotesGroup)
return VaultNotesGroup
