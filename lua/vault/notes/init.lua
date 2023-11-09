
---@class Notes - Retrieve notes from vault.
---@field map Note[] - Array of Note objects.
local Notes = {}

--- Create a new Notes object.
---@param map? NotesMap - The table to create the Notes object from.
---@return Notes
function Notes:new(filter_opts)
   local NotesMap = require("vault.notes.map")
   local this = {}
  local map = NotesMap:new():fetch(filter_opts)
  this.map = map
  setmetatable(this, self)
  self:from_map(map)
  self.__index = self
  return this
end

--- Create a new Notes object from a map.
---@param map NotesMap? The table to create the Notes object from.
function Notes:from_map(map)
  local Note = require("vault.notes.note")
  map = map or self.map
  for note_path, note_map in pairs(map) do
    local note = Note:new(note_map)
    map[note_path] = note
  end
  return setmetatable(map, self)
end

--- Returns a note by its path
---@param k string - The key to get.
---@return Note
function Notes:get(path)
   local NotesMap = require("vault.notes.map")
  if not self.map then
    self.map = NotesMap:new():fetch()
  end
  return self.map[path]
end

return Notes
