local state = require("vault.core.state")
local Collection = require("vault.core.collection")
local Base = require("vault.bases.base")

local function scanner()
    return require("vault.scanner")
end

--- @class vault.Bases: vault.Collection
--- @field map table<string, vault.Base> Map of base name -> Base object
local Bases = Collection:extend("VaultBases")


--- Initialize the Bases collection by scanning for .base files.
--- @return nil
function Bases:init()
    state.set_global_key("bases", nil)

    self.map = {}
    self._map = {}

    self:load()

    self._map = self.map

    state.set_global_key("bases", self)
end


--- Load bases from the filesystem via the Rust scanner.
--- @return vault.Bases
function Bases:load()
    local raw_bases = scanner().base_files()

    for _, raw in ipairs(raw_bases) do
        local base = Base(raw)
        self.map[base.data.name] = base
        self._map[base.data.name] = base
    end

    return self
end


--- Override push to use name as key instead of slug.
--- @param base vault.Base
function Bases:push(base)
    if not base then
        return
    end
    if not base.data then
        error("Item must have a data field")
    end
    local key = base.data.name
    if not key or key == "" then
        error("Base must have a name")
    end
    self._map[key] = base
    self.map[key] = base
end


--- Get a base by name.
--- @param name string
--- @return vault.Base|nil
function Bases:get(name)
    return self.map[name]
end


--- Get list of all base names.
--- @return string[]
function Bases:names()
    return vim.tbl_keys(self.map)
end


--- Match notes against a specific base's filters.
--- Convenience method that loads notes and runs the base filter.
---
--- @param base_name string Name of the base to match against
--- @param notes? table<string, vault.Note> Optional pre-loaded notes map
--- @return table<string, vault.Note> matched notes
function Bases:match_notes(base_name, notes)
    local base = self:get(base_name)
    if not base then
        error("Base not found: " .. tostring(base_name))
    end

    if not notes then
        local Notes = require("vault.notes")
        local notes_collection = Notes()
        notes = notes_collection.map
    end

    return base:match_notes(notes)
end


--- Reset the collection.
--- @return vault.Bases
function Bases:reset()
    self.map = self._map
    return self
end


--- @alias vault.Bases.constructor fun(): vault.Bases
--- @type vault.Bases|vault.Bases.constructor
local VaultBases = Bases

state.set_global_key("class.vault.Bases", VaultBases)
return VaultBases
