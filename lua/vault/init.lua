---Plugin entrypoint.
local vault = {}
local FleetingNote = require("vault.popups.fleeting_note")
local Notes = require("vault.notes")
local Tags = require("vault.tags")
local FilterOpts = require("vault.filter_opts")

---Setup the vault plugin.
---@param opts table? - Configuration options (optional).
function vault.setup(opts)
  opts = opts or {}
	require("vault.config")
	require("vault.commands")
	-- require("vault.cmp").setup()
end

---Retrieve notes from vault.
---@param filter_opts VaultNotesFilterOpts? - Filter options (optional).
---@return VaultNotes
function vault.notes(filter_opts)
  return Notes(filter_opts)
end

---Retrieve tags from your vault.
---@param include string[]? - Array of tag names to include (optional).
---@param exclude string[]? - Array of tag names to exclude (optional).
---@param match_opt string? - Match to filter tags (optional).
---|"'exact'" # Matches exact value. E.g., "foo" matches "foo" but not "foobar".
---|"'contains'" # Matches value if it contains the query. E.g., "foo" matches "foo" and "foobar".
---|"'startswith'" # Matches value if it starts with the query. E.g., "foo" matches "foo" and "foobar".
---|"'endswith'" # Matches value if it ends with the query. E.g., "foo" matches "foo" and "barfoo".
---|"'regex'" # Matches value if it matches the query as a regex. E.g., "foo" matches "foo" and "barfoo".
---@return VaultTag[] - Array of Tag objects.
function vault.tags(include, exclude, match_opt, mode)
  local filter_opts = FilterOpts({
    include = include,
    exclude = exclude,
    match_opt = match_opt,
    mode = mode,
  })
	return Tags(filter_opts)
end

---Shows a popup markdown empty buffer for quick note taking.
function vault.fleeting_note()
  FleetingNote()
end

return vault
