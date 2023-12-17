local Object = require("vault.core.object")
local config = require("vault.config")

---@class VaultNote.data.basename
local NoteBasename = Object("VaultNoteBasename")

---@param s string
---@return VaultNote.data.basename
function NoteBasename:init(s)
    if not s then
        error("NoteBasename:init() requires a string")
    end

    --- Special characters that are not allowed in filenames
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
