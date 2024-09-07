--- @alias vault.relpath string -- The relative path to the `VaultPathRoot`
--- @alias vault.Config.options.root vault.path -- The path to the root of the vault.

--- @alias vault.map table<string, any>
--- @alias vault.Notes.Data.slugs table<vault.slug, boolean>
--- @alias vault.map.paths table<vault.path, boolean>
--- @alias vault.map.relpaths table<vault.relpath, boolean>

--- @alias vault.List table<integer, any>
--- @alias vault.list.paths table<integer, vault.path>
--- @alias vault.list.relpaths table<integer, vault.relpath>

--- @alias vault.source.lnums table<integer, vault.source.occurence>

--- @alias vault.source.match {line: string, lnum_start: integer, ["end"]: number}

--- @alias vault.Sources.map table<vault.slug, vault.source.lnums>

--- @class vault.source.occurence
--- @field lnum integer
--- @field end_lnum? integer
--- @field col integer
--- @field end_col? integer
