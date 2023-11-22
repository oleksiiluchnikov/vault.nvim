local config = require("vault.config")

---@class NoteBasename
---@field __index string
---@field __tostring fun(self): string
---@field to_title fun(self): VaultNoteTitle
local NoteBasename = {}

---@param s string
---@return NoteBasename
function NoteBasename:new(s)
  if not s then
    error("Vault: NoteBasename:new() - s is nil.")
  end

  ---Special characters that are not allowed in filenames
  ---@type table<string, string>
  local replaces = {
    ["/"] = "-",
    [":"] = "-",
    ["*"] = "-",
    ["?"] = "-",
    ['"'] = "-",
    ["<"] = "-",
    [">"] = "-",
    ["|"] = "-",
    ["\n"] = "",
    ["\r"] = "",
    ["#"] = " ",
  }

  for k, v in pairs(replaces) do
    s = s:gsub(k, v)
  end

  local ext = config.ext

  if not s:match(ext .. "$") then
    s = s .. ext
  end

  local this = {}
  setmetatable(this, self)
  this.__index = s
  return this
end

function NoteBasename:__tostring()
  return self.__index
end

---@return VaultNoteTitle
function NoteBasename:to_title()
  local s = self.__index
  local Title = require("vault.notes.note.title")

  s = s:gsub(config.ext .. "$", "")

  ---@type VaultNoteTitle
  local title = Title:from_string(s)
  return title
end

return NoteBasename
