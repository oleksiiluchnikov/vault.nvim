---@class Notes - Retrieve notes from vault.
---@field data Note[] - Array of Note objects.
local Notes = {}

---Create a new Notes object.
---@param this? table - The table to create the Notes object from.
---@return Notes
function Notes:new(this)
  this = this or {}
  setmetatable(this, self)
  self.__index = self
  return this
end

---@class NotesFilterOptions: FilterOptions -- Filter options for notes.
---@field keys string[]? - Array of keys to filter notes.
---|"'title'" # Matches note title.
---|"'tags'" # Matches note tags.
---|"'content'" # Matches note content.
local NotesFilterOptions = {
  keys = {},
  include = {},
  exclude = {},
  match_opt = "exact",
  mode = "all",
}

function NotesFilterOptions:new(this)
  this = this or {}
  setmetatable(this, self)
  self.__index = self
  return this
end
