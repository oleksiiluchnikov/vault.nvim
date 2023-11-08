---@class Vault
---@field setup function - Setup the vault plugin.
---@field notes function|Note[] - Retrieve notes from vault.
---@field notes_with_tags function|Note[] - Retrieve notes from vault with tags.
---@field tags function|Tag[] - Retrieve tags from vault.
local Vault = {}
local NotesData = require("vault.notes_data")

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
---@param filter_opts FilterOptions? - Filter options (optional).
---@return Notes
function Vault.notes(filter_opts)
  return NotesData:new():fetch(filter_opts):to_notes()
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
	local TagsData = require("vault.tags_data")
	include = include or {}
	exclude = exclude or {}
	match_opt = match_opt or "exact"

	local filter_opts = {
		include = include,
		exclude = exclude,
		match_opt = match_opt,
	}
	return TagsData:new():fetch(filter_opts):to_tags()
end

---Test function.
function Vault.test()
	vim.cmd("lua package.loaded['vault'] = nil")
	vim.cmd("lua require('vault').setup({})")
	-- local output= Vault.tags({ "status", "class" }, {"status/TODO"}, "startswith")
	-- local output = Vault.notes_filter_by_tags({ "status" }, { "status/TODO" }, "startswith", "all")
	-- local output = Vault.tags({ "status" }, { "status/TODO" }, "startswith")
	-- require("vault.pickers").notes({},output)
	vim.cmd("lua package.loaded['vault.notes_data'] = nil")
	vim.cmd("lua package.loaded['vault.tags_data'] = nil")
	vim.cmd("lua package.loaded['vault.utils'] = nil")
	vim.cmd("lua package.loaded['vault.filter_options'] = nil")
	vim.cmd("lua package.loaded['vault.notes'] = nil")
	vim.cmd("lua package.loaded['vault.pickers'] = nil")
	-- local output = NotesData:new():fetch():to_notes()[44]:tags()
	local output = Vault.notes({'tags',{},{'class'}, "startswith", "all"}).data
  print(vim.inspect(#vim.tbl_keys(output)))
  for k,v in pairs(output) do
    print(k,v)
  end
end

return Vault
