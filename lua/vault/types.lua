---@alias VaultPath.absolute string
---@alias VaultNote.data.relpath string -- The relative path to the `VaultPathRoot`
---@alias VaultPath.root string -- The root directory of the vault

---@alias VaultMap table<string, any>
---@alias VaultMap.slugs table<VaultNote.data.slug, boolean>
---@alias VaultMap.paths table<VaultPath.absolute, boolean>
---@alias VaultMap.relpaths table<VaultNote.data.relpath, boolean>

---@alias VaultArray table<integer, any>
---@alias VaultArray.paths table<integer, VaultPath.absolute>
---@alias VaultArray.relpaths table<integer, VaultNote.data.relpath>

---@alias VaultSource table<string, VaultSource.match[]>

---@class VaultSource.match {line: string, start: number, ["end"]: number}
---@field line string - The line where the match was found.
---@field start number - The start position of the match.
---@field end number - The end position of the match.

---@alias VaultMap.sources table<VaultNote.data.slug, VaultSource>
