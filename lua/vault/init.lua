---@class Vault
local Vault = {}
local NotesMap = require("vault.notes.map")

---Create a new Vault object.
---@return Vault
function Vault:new()
	local this = {}
	setmetatable(this, self)
	self.__index = self
	return this
end

---Setup the vault plugin.
function Vault.setup()
	require("vault.config")
	require("vault.commands")
	-- require("vault.cmp").setup()
end

---Retrieve notes from vault.
---@param filter_opts FilterOpts? - Filter options (optional).
---@return Notes
function Vault.notes(filter_opts)
  return require('vault.notes'):new(filter_opts)
end

---Retrieve tags from your vault.
---@param include string[]? - Array of tag values to include (optional).
---@param exclude string[]? - Array of tag values to exclude (optional).
---@param match_opt string? - Match to filter tags (optional).
---|"'exact'" # Matches exact value. E.g., "foo" matches "foo" but not "foobar".
---|"'contains'" # Matches value if it contains the query. E.g., "foo" matches "foo" and "foobar".
---|"'startswith'" # Matches value if it starts with the query. E.g., "foo" matches "foo" and "foobar".
---|"'endswith'" # Matches value if it ends with the query. E.g., "foo" matches "foo" and "barfoo".
---|"'regex'" # Matches value if it matches the query as a regex. E.g., "foo" matches "foo" and "barfoo".
---@return Tag[] - Array of Tag objects.
function Vault.tags(include, exclude, match_opt)
	local TagsMap = require("vault.tags.map")
	include = include or {}
	exclude = exclude or {}
	match_opt = match_opt or "exact"

	local filter_opts = {
		include = include,
		exclude = exclude,
		match_opt = match_opt,
	}
	return TagsMap:new():fetch(filter_opts):to_tags()
end

---Test function.
function Vault.test()
	vim.cmd("lua package.loaded['vault'] = nil")
	vim.cmd("lua require('vault').setup({})")
	-- local output= Vault.tags({ "status", "class" }, {"status/TODO"}, "startswith")
	-- local output = Vault.notes_filter_by_tags({ "status" }, { "status/TODO" }, "startswith", "all")
	-- local output = Vault.tags({ "status" }, { "status/TODO" }, "startswith")
	-- require("vault.pickers").notes({},output)
	vim.cmd("lua package.loaded['vault.notes.map'] = nil")
	vim.cmd("lua package.loaded['vault.tags.map'] = nil")
	vim.cmd("lua package.loaded['vault.utils'] = nil")
	vim.cmd("lua package.loaded['vault.filter'] = nil")
	vim.cmd("lua package.loaded['vault.notes'] = nil")
	vim.cmd("lua package.loaded['vault.pickers'] = nil")
	-- local output = NotesMap:new():fetch():to_notes()[44]:tags()
	local output = Vault.notes({'tags',{},{'class'}, "startswith", "all"}).map
  print(vim.inspect(#vim.tbl_keys(output)))
  for k,v in pairs(output) do
    print(k,v)
  end
end

return Vault
