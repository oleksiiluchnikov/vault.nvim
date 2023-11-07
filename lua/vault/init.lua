local NotesData = require("vault.notes_data")

---@class Vault
---@field setup function - Setup the vault plugin.
---@field notes function|Note[] - Retrieve notes from vault.
---@field notes_with_tags function|Note[] - Retrieve notes from vault with tags.
---@field tags function|Tag[] - Retrieve tags from vault.
local Vault = {}

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
---@return Note[] - Array of Note objects.
function Vault.notes()
	return require("vault.notes_data"):new():fetch():to_notes()
end

---Retrieve notes from vault with certain tag options.
---@param include string[] - Array of tag values to include.
---@param exclude string[] - Array of tag values to exclude.
---@param match_opt string? - Match type for filtering notes (optional). Options: "exact", "contains", "startswith", "endswith", "regex". "fuzzy"
---@param mode string? - Behavior for filtering notes (optional). Options: "all", "any"
---@return Note[] - Array of Note objects.
function Vault.notes_filter_by_tags(include, exclude, match_opt, mode)
	include = include or {}
	exclude = exclude or {}
	match_opt = match_opt or "exact"
	mode = mode or "all"

	local FilterOptions = require("vault.filter_options")

	local valid_modes = { "all", "any" }
	local valid_matches = { "exact", "contains", "startswith", "endswith", "regex" }

	if not vim.tbl_contains(valid_modes, mode) then
		error("Invalid mode: " .. mode .. ". Valid modes are: " .. table.concat(valid_modes, ", "))
	end
	if not vim.tbl_contains(valid_matches, match_opt) then
		error("Invalid match: " .. match_opt .. ". Valid matches are: " .. table.concat(valid_matches, ", "))
	end

  ---@type table<string, boolean>
	local seen_notes = {}

  ---@type Note[]
	local filtered_notes = {}

  ---@type <string, <string[]>> - Map of tag values to note paths.
  local tags_map = require("vault.tags_data"):new():fetch().data

	for tag_value, notes_paths in pairs(tags_map) do
		if mode == "all" then
      -- It should include all query tags_values and exclude all exclude tags_values
      local contains_tag = false
      local contains_all_tags = true
      for _, query in ipairs(include) do
        for i, note_path in pairs(notes_paths) do
          local note = require("vault.note"):new({ path = note_path })
          local note_tags = note:tags()
          for _, note_tag in ipairs(note_tags) do
            if FilterOptions.has_match(note_tag.value, query, match_opt) then
              contains_tag = true
            end
          end

          if not contains_tag then
            contains_all_tags = false
            break
          else
            contains_all_tags = true
          end

          if contains_all_tags and not seen_notes[note_path] then
            table.insert(filtered_notes, note)
            seen_notes[note_path] = true
          end

        end
      end
      for _, query in ipairs(exclude) do
        for i, note_path in ipairs(notes_paths) do
          local note = require("vault.note"):new({ path = note_path })
          local note_tags = note:tags()
          -- If the note contains any of the exclude tags_values, then it should be excluded
          for _, note_tag in ipairs(note_tags) do
            if FilterOptions.has_match(note_tag.value, query, match_opt) then
              contains_tag = true
            end
          end

          if contains_tag then
            contains_all_tags = false
            break
          else
            contains_all_tags = true
          end

          if contains_all_tags and not seen_notes[note_path] then
            table.insert(filtered_notes, note)
            seen_notes[note_path] = true
          end
        end
      end
		elseif mode == "any" then
      -- It should include any query tags_values and exclude any exclude tags_values
      for _, query in ipairs(include) do
        for i, note_path in ipairs(notes_paths) do
          local note = require("vault.note"):new({ path = note_path })
          local note_tags = note:tags()
          for _, note_tag in ipairs(note_tags) do
            if FilterOptions.has_match(note_tag.value, query, match_opt) and not seen_notes[note_path] then
              table.insert(filtered_notes, note)
              seen_notes[note_path] = true
              goto continue
            end
          end
          ::continue::
        end
      end
      for _, query in ipairs(exclude) do
        for i, note_path in ipairs(notes_paths) do
          local note = require("vault.note"):new({ path = note_path })
          local note_tags = note:tags()
          for _, note_tag in ipairs(note_tags) do
            if FilterOptions.has_match(note_tag.value, query, match_opt) and not seen_notes[note_path] then
              tags_map[tag_value] = nil
              seen_notes[note_path] = true
              goto continue
            end
          end
          ::continue::
        end
      end
		end
	end

	return filtered_notes
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
	return TagsData:new():fetch():to_tags(filter_opts)
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
	-- local output = NotesData:new():fetch():to_notes()[44]:tags()
  local output = Vault.notes_filter_by_tags({ }, {"class"}, "startswith", "all")
	P(output)
end

return Vault
