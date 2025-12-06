local state = require("vault.core.state")
local error_formatter = require("vault.utils.error")
--- @type vault.Lines.constructor|vault.Lines
local Lines = state.get_global_key("class.vault.Lines") or require("vault.notes")

--- @class vault.Lines.Group: vault.Lines
--- @field init fun(self: vault.Lines.Group, notes: vault.Lines)
--- @diagnostic disable-next-line: assign-type-mismatch
local LinesGroup = Lines:extend("VaultLinesGroup")

--- @param notes vault.Lines
function LinesGroup:init(notes)
    if not notes then
        error(error_formatter.MISSING_PARAMETER("notes"))
    end

    self.map = notes.map
end

--- @alias VaultLinesGroup.constructor fun(notes: vault.Lines): vault.Lines.Group
--- @type VaultLinesGroup.constructor|vault.Lines.Group
local VaultLinesGroup = LinesGroup

state.set_global_key("class.vault.LinesGroup", VaultLinesGroup)
return VaultLinesGroup
