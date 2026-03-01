local Object = require("vault.core.object")
local error_formatter = require("vault.utils.error")
local utils = require("vault.utils")
local state = require("vault.core.state")

-- -- local config = require("vault.config")
-- local data = require("vault.dirs.dir.data")

--- @class vault.Dir.Data: vault.Object
local DirData = Object("VaultDirData")

--- @alias vault.Dir.Data.partial table - The partial Data of the dir.

--- @param this vault.Dir.Data.partial
function DirData:init(this)
    this = this or {}
    self.name = this.name or vim.fn.fnamemodify(this.path, ":t") or this.path
    self.path = this.path
    self.relpath = utils.path_to_relpath(this.path)
end

--- @class vault.Dir: vault.Object
--- @field data vault.Dir.Data - The Data of the dir.
--- @field init fun(self: vault.Dir, this: vault.Dir.Data.name|vault.Dir.Data.partial): vault.Dir
--- @field add_relpath fun(self: vault.Dir, relpath: string): vault.Dir - Add a relpath to the `self.Data.sources` table.
local Dir = Object("VaultDir")

--- Create a new |vault.Dir| instance.
--- @param this vault.Dir.Data.name|vault.Dir.Data.partial
function Dir:init(this)
    if not this then
        error(error_formatter.MISSING_PARAMETER("this"), 2)
    end
    if type(this) == "string" then
        this = { path = this }
    end

    if not this.path then
        error(error_formatter.MISSING_PARAMETER("path"), 2)
    end

    self.data = DirData(this)
end

--- Rename the dir. and update all occurences of the dir in the notes.
--- @param name vault.Dir.Data.name
--- @param verbose? boolean
--- @return vault.Dir
function Dir:rename(name, verbose)
    if name == nil or name == "" then
        error("Invalid name: " .. vim.inspect(name))
    end
    if name == self.data.name then
        return self
    end
    verbose = verbose or true
    --- @type vault.Note.constructor
    local Note = state.get_global_key("class.vault.Note") or require("vault.notes.note")

    --- @type table<string, vault.source.lnums> - A table of paths to update.
    local paths_to_update = {}
    for relpath, lnums in pairs(self.data.sources) do
        local path = utils.relpath_to_path(relpath)
        paths_to_update[path] = lnums
    end

    local old_name = self.data.relpath
    local new_name = name

    local message = ""
    if verbose == true then
        message = self.data.relpath .. " -> " .. name
    end

    -- Update connected notes
    for path, lnums in pairs(paths_to_update) do
        --- @type vault.Note
        local note = Note(path)
        note:update_content(old_name, new_name, lnums)

        if verbose == true then
            message = message
                .. "\n"
                .. self.data.relpath
                .. " -> "
                .. name
                .. " in "
                .. note.data.relpath
        end
    end
    self.data.relpath = name
    if verbose == false then
        return self
    end

    vim.notify(message, vim.log.levels.INFO, {
        title = "Vault Rename",
        timeout = 200,
    })
    -- require("vault.dirs").reset()
    return self
end

--- Add a relpath to the |vault.Dir.Data.sources|
---
--- @param relpath vault.relpath
--- @return vault.Dir
function Dir:add_relpath(relpath)
    if not self.data.sources[relpath] then
        -- FIXME: Should add the |vault.Source| to the |vault.Dir.data.sources| table, not the |boolean| value.
        self.data.sources[relpath] = true
    end
    return self
end

--- @alias vault.Dir.constructor fun(this: vault.Dir|table|string): vault.Dir
--- @type vault.Dir.constructor|vault.Dir
local VaultDir = Dir

state.set_global_key("class.VaultDir", VaultDir)
return VaultDir
