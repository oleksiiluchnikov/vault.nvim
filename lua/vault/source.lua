--- Mapping of line numbers to source occurrences
--- @alias vault.source.lnums table<integer, vault.source.occurence>
--- @see vault.source.occurence

--- Represents a matched line in source code
--- @class vault.source.match {line: string, lnum_start: integer, ["end"]: number}
--- @field line string The content of the matched line
--- @field lnum_start integer The starting line number (1-based)
--- @field ["end"] number The ending position
--- @usage local match = { line = "Example content", lnum_start = 1, ["end"] = 15 }

--- Mapping of slugs to their corresponding line number occurrences
--- @alias vault.Sources.map table<vault.slug, vault.source.lnums>
--- @see vault.slug
--- @see vault.source.lnums

--- Represents the position of a source code occurrence
--- @class vault.source.occurence
--- @field lnum integer The starting line number (1-based)
--- @field end_lnum? integer Optional ending line number (1-based)
--- @field col integer The starting column number (1-based)
--- @field end_col? integer Optional ending column number (1-based)
--- @usage local occurrence = { lnum = 1, end_lnum = 2, col = 1, end_col = 10 }
