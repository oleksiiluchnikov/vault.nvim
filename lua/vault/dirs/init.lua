local state = require("vault.core.state")
---@return { dirs: fun(opts?: { ignore: boolean|string[] }): vault.Dirs.map }
local function scanner()
    return require("vault.scanner")
end
local Collection = require("vault.core.collection")

---@param map vault.Dirs.map|nil
---@return vault.Dirs.map
local function copy_map(map)
    local copy = {}
    for key, value in pairs(map or {}) do
        copy[key] = value
    end
    return copy
end

-- Aliases
--- @alias vault.Dirs.map table<vault.relpath, vault.Dir> - Map of directories by vault-relative path.
--- @alias vault.Dirs.list table<integer, vault.Dir> - Ordered list of directories.

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
    local cached = state.get_global_key("dirs")
    if type(cached) == "table" and type(cached.map) == "table" then
        self.map = copy_map(cached.map)
        return
    end

    self.map = scanner().dirs()
    state.set_global_key("dirs", self)
end

--- @alias VaultDirs.constructor fun(filter_opts?: table): vault.Dirs
--- @type VaultDirs.constructor|vault.Dirs
local VaultDirs = Dirs

state.set_global_key("class.vault.Dirs", VaultDirs)
return VaultDirs
