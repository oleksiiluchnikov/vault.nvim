local state = require("vault.core.state")
local function scanner()
    return require("vault.scanner")
end
local Collection = require("vault.core.collection")

-- Aliases
--- @alias vault.Dirs.map table<string, vault.Dir> - Map of dirs.
--- @alias vault.Dirs.list table<integer, vault.Dir> - Map of dirs.

--- @alias VaultMap.dirs.sources vault.Sources.map - Map of sources.

--- @alias VaultDirsGroup vault.Dirs - Dirs that have children.

--- VaultDirs class represents a collection of dirs loaded from vault.
--- @class vault.Dirs: vault.Object - Retrieve dirs from vault.
--- @field map vault.Dirs.map - Map of dirs.
--- @field nested VaultDirsGroup -- Dirs that have children.
--- @field sources fun(self: vault.Dirs): VaultMap.dirs.sources - Get all sources from dirs.
--- @field list fun(self: vault.Dirs): vault.Dirs.list - Return `VaultDirs` as a `VaultArray`.
local Dirs = Collection:extend("VaultDirs")

--- Initializes the VaultDirs object by scanning all dirs from the vault.
--- Sets the dirs map and registers the dirs globally.
--- @return nil
function Dirs:init()
    self.map = scanner().dirs()
    state.set_global_key("dirs", self)
end

--- @alias VaultDirs.constructor fun(filter_opts?: table): vault.Dirs
--- @type VaultDirs.constructor|vault.Dirs
local VaultDirs = Dirs

state.set_global_key("class.vault.Dirs", VaultDirs)
return VaultDirs
