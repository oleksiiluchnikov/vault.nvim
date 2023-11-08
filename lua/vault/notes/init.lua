---@class Notes - Retrieve notes from vault.
---@field data Note[] - Array of Note objects.
local Notes = {}
local Note = require("vault.note")

---Create a new Notes object.
---@param data? NotesData - The table to create the Notes object from.
---@return Notes
function Notes:new(data)
  data = data or {}
  for note_path, note_data in pairs(data) do
    local note = Note:new(note_data)
    data[note_path] = note
  end
  local this = {}
  this.data = data
  setmetatable(this, self)
  self.__index = self
  return this
end

-- function Notes:from_data(data)
--   return Notes:new(data)
-- end
return Notes
