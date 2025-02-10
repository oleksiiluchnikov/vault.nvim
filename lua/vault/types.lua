--- Represents information about a vault entry
--- @class vault.EntryInfo {path: vault.path, slug: vault.slug, relpath: vault.relpath, basename: string}
--- @field path vault.path The absolute path to the entry
--- @field slug vault.slug The unique identifier for the entry
--- @field relpath vault.relpath The relative path from the vault root
--- @field basename string The filename without path

--- @alias vault.EntryInfoMap table<vault.slug, vault.EntryInfo>

--- Represents a path relative to the vault root directory
--- The relative path to the `VaultPathRoot`
--- @alias vault.relpath string

--- Configuration option specifying the root directory of the vault
--- The path to the root of the vault.
--- @alias vault.Config.options.root vault.path

--- Generic key-value mapping structure
--- @alias vault.map table<string, any>

--- Mapping of note slugs to their existence state
--- @alias vault.Notes.Data.slugs table<vault.slug, boolean>

--- Mapping of absolute paths to their existence state
--- @alias vault.map.paths table<vault.path, boolean>

--- Mapping of relative paths to their existence state
--- @alias vault.map.relpaths table<vault.relpath, boolean>

--- Generic indexed list structure
--- @alias vault.List table<integer, any>

--- Indexed list of absolute paths
--- @alias vault.list.paths table<integer, vault.path>

--- Indexed list of relative paths
--- @alias vault.list.relpaths table<integer, vault.relpath>

--- Mapping of line numbers to source occurrences
--- @alias vault.source.lnums table<integer, vault.source.occurence>

--- Represents a matched line in source code
--- @class vault.source.match {line: string, lnum_start: integer, ["end"]: number}
--- @field line string The content of the matched line
--- @field lnum_start integer The starting line number
--- @field ["end"] number The ending position

--- Mapping of slugs to their corresponding line number occurrences
--- @alias vault.Sources.map table<vault.slug, vault.source.lnums>

--- Represents the position of a source code occurrence
--- @class vault.source.occurence
--- @field lnum integer The starting line number
--- @field end_lnum? integer Optional ending line number
--- @field col integer The starting column number
--- @field end_col? integer Optional ending column number
