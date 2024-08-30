local api = {}
local state = require("vault.core.state")
local fetcher = require("vault.fetcher")
--- @type vault.Note.constructor|vault.Note
local Note = require("vault.notes.note")
--- @type vault.Notes.constructor|vault.Notes
local Notes = require("vault.notes")
local utils = require("vault.utils")

function api.open_notes_picker()
    require("vault.pickers").notes()
end

return api
