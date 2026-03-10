--- Core domain aliases shared across vault.nvim.

--- Absolute path to a file inside or outside the vault.
--- @alias vault.path string

--- Path relative to the vault root.
--- @alias vault.relpath string

--- Canonical note identifier without extension.
--- @alias vault.slug string

--- Filename without extension.
--- @alias vault.stem string

--- Generic string-keyed map.
--- @generic T
--- @alias vault.map table<string, T>

--- Generic list.
--- @generic T
--- @alias vault.List T[]

--- Indexed list of absolute paths.
--- @alias vault.list.paths vault.path[]

--- Indexed list of relative paths.
--- @alias vault.list.relpaths vault.relpath[]

--- Mapping of absolute paths to their existence state.
--- @alias vault.map.paths table<vault.path, boolean>

--- Mapping of relative paths to their existence state.
--- @alias vault.map.relpaths table<vault.relpath, boolean>

--- Mapping of note slugs to their existence state.
--- @alias vault.Notes.Data.slugs table<vault.slug, boolean>

--- Lightweight collection entry data requirement.
--- @class vault.CollectionEntryData
--- @field slug vault.slug

--- Lightweight collection entry requirement.
--- @class vault.CollectionEntryLike
--- @field data vault.CollectionEntryData

--- Map of collection entries keyed by slug.
--- @generic T: vault.CollectionEntryLike
--- @alias vault.CollectionMap table<vault.slug, T>

--- Groups collection entries by a derived string value.
--- @generic T
--- @alias vault.GroupedValuesMap table<string, T[]>

--- Lookup map created from collection values.
--- @alias vault.CollectionValueLookup table<string, boolean|number|string>

--- Source occurrence map produced by collections.
--- @generic T
--- @alias vault.CollectionSourcesMap table<vault.slug, table<string, T>>

--- Status reported by `vault.checkhealth()`.
--- @alias vault.HealthStatus "ok"|"error"

--- Single health issue.
--- @class vault.HealthIssue
--- @field status "error"
--- @field message string

--- Successful health summary.
--- @class vault.HealthSummary
--- @field status "ok"
--- @field message string

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

--- Configuration option specifying the root directory of the vault
--- The path to the root of the vault.
--- @alias vault.Config.options.root vault.path
--- @usage local root = "~/vaults/knowledge"
