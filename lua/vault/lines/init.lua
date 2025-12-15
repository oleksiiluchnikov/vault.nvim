local state = require("vault.core.state")

local function scanner()
    return require("vault.scanner")
end

local Collection = require("vault.core.collection")

-- Aliases
--- @alias vault.Lines.map table<string, vault.Line> - Map of lines.
--- @alias vault.Lines.list table<integer, vault.Line> - Map of lines.

--- @alias VaultMap.lines.sources vault.Sources.map - Map of sources.

--- @alias VaultLinesGroup vault.Lines - Lines that have children.

--- VaultLines class represents a collection of lines loaded from vault.
--- @class vault.Lines: vault.Object - Retrieve lines from vault.
--- @field map vault.Lines.map - Map of lines.
--- @field nested VaultLinesGroup -- Lines that have children.
--- @field sources fun(self: vault.Lines): VaultMap.lines.sources - Get all sources from lines.
--- @field list fun(self: vault.Lines): vault.Lines.list - Return `VaultLines` as a `VaultArray`.
local Lines = Collection:extend("VaultLines")

--- Initializes the VaultLines object by scanning all lines from the vault.
--- Sets the lines map and registers the lines globally.
--- @return nil
function Lines:init()
    self.map = scanner().lines()
    state.set_global_key("lines", self)
end

--- @alias VaultLines.constructor fun(filter_opts?: table): vault.Lines
--- @type VaultLines.constructor|vault.Lines
local VaultLines = Lines

state.set_global_key("class.vault.Lines", VaultLines)
return VaultLines
