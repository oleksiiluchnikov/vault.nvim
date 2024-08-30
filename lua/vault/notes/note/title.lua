local Object = require("vault.core.object")
local Note = require("vault.notes.note")
-- local NoteBasename = require("vault.notes.note.basename")

--- Sync title with filename and update {inlinks}.
--- @class vault.Note.Title
--- @field text string
--- @field __index string
local Title = Object("VaultNoteTitle")

--- @param str string
function Title:init(str)
    if not str then
        error("missing argument: str")
    end

    if type(str) ~= "string" then
        error("str must be a string")
    end
    self.text = str
end

--- @param path string
function Title:sync(path)
    if path == nil then
        local bufpath = vim.fn.expand("%:p")
        if type(bufpath) ~= "string" then
            return
        end
        path = bufpath
    end

    local note = Note({
        path = path,
    })

    local title = note.data.title
    if title == nil then
        return
    end

    local new_path = vim.fn.fnamemodify(path, ":h") .. "/" .. title .. ".md"
    if vim.fn.filereadable(new_path) == 1 then
        vim.notify("File already exists: " .. new_path, vim.log.levels.ERROR, {
            title = "Knowledge",
            timeout = 200,
        })
        return
    end

    --- @type integer
    local rename_success = vim.fn.rename(path, new_path)
    if rename_success == 0 then
        vim.notify("Renamed: " .. path .. " -> " .. new_path, vim.log.levels.INFO, {
            title = "Knowledge",
            timeout = 200,
        })

        local inlinks = note.inlinks(path)
        if #inlinks > 0 then
            note.update_inlinks(path)
        end
    else
        vim.notify("Failed to rename: " .. path .. " -> " .. new_path, vim.log.levels.ERROR, {
            title = "Knowledge",
            timeout = 200,
        })
        return
    end

    -- Open the renamed file.
    vim.cmd("e " .. new_path)
end

function Title:__tostring()
    return self.__index
end

--- Create a title from a string.
--- @param str string - The string to create the title from.
function Title:from_string(str)
    if not str then
        error("Vault: Title:from_string() - s is nil.")
    end

    if str:match("^#") then
        str = str:gsub("^#", "")
    end

    str = str:gsub("%s+", " ")

    -- Remove trailing whitespace
    str = str:gsub("%s+$", "")

    -- Remove leading whitespace
    str = str:gsub("^%s+", "")

    self.text = str
end

--- Convert a title to a basename.
--- @return vault.Note.Data.basename
function Title:to_basename()
    local str = self.__index

    if not str then
        error("Vault: Title:to_basename() - s is nil.")
    end

    return require("vault.notes.note.basename"):new(str)
end

--- @alias VaultNoteTitle.constructor fun(str: string): vault.Note.Title
--- @type VaultNoteTitle.constructor|vault.Note.Title
local VaultNoteTitle = Title

return VaultNoteTitle
