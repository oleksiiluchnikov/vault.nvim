--- Represents information about a vault entry
--- @class vault.EntryInfo {path: vault.path, slug: vault.slug, relpath: vault.relpath, basename: string}
--- @field path vault.path The absolute path to the entry
--- @field slug vault.slug The unique identifier for the entry
--- @field relpath vault.relpath The relative path from the vault root
--- @field basename string The filename without path
--- @see vault.path
--- @see vault.slug
--- @see vault.relpath

--- Mapping of slugs to entry information
--- @alias vault.EntryInfoMap table<vault.slug, vault.EntryInfo>
--- @see vault.EntryInfo
--- @see vault.slug

--- Represents a path relative to the vault root directory
--- The relative path to the `VaultPathRoot`
--- @alias vault.relpath string
--- @usage local relpath = "notes/example.md"

--- Configuration option specifying the root directory of the vault
--- The path to the root of the vault.
--- @alias vault.Config.options.root vault.path
--- @usage local root = "~/vaults/knowledge"

--- Generic key-value mapping structure
--- @alias vault.map table<string, any>
--- @see table

--- Mapping of note slugs to their existence state
--- @alias vault.Notes.Data.slugs table<vault.slug, boolean>
--- @see vault.slug

--- Mapping of absolute paths to their existence state
--- @alias vault.map.paths table<vault.path, boolean>
--- @see vault.path

--- Mapping of relative paths to their existence state
--- @alias vault.map.relpaths table<vault.relpath, boolean>
--- @see vault.relpath

--- Generic indexed list structure
--- @alias vault.List table<integer, any>
--- @see table

--- Indexed list of absolute paths
--- @alias vault.list.paths table<integer, vault.path>
--- @see vault.path

--- Indexed list of relative paths
--- @alias vault.list.relpaths table<integer, vault.relpath>
--- @see vault.relpath
