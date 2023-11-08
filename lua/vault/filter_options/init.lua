---@enum MatchOptions
local MatchOptions = {
  "exact",
  "contains",
  "startswith",
  "endswith",
  "regex",
}

---@enum ModeOptions
local ModeOptions = {
  "all",
  "any",
}

---Filter options.
---@class FilterOptions
---@field include string[]? - Array of values to include.
---@field exclude string[]? - Array of values to exclude.
---@field match_opt string? - Match type for filtering notes (optional). Options: "exact", "contains", "startswith", "endswith", "regex". "fuzzy"
---|"'exact'" # Matches exact value. E.g., "foo" matches "foo" but not "foobar".
---|"'contains'" # Matches value if it contains the query. E.g., "foo" matches "foo" and "foobar".
---|"'startswith'" # Matches value if it starts with the query. E.g., "foo" matches "foo" and "foobar".
---|"'endswith'" # Matches value if it ends with the query. E.g., "foo" matches "foo" and "barfoo".
---|"'regex'" # Matches value if it matches the query as a regex. E.g., "foo" matches "foo" and "barfoo".
---@field mode string? - Behavior for filtering notes (optional). Options: "all", "any"
---|"'all'"  # Matches all values.
---|"'any'" # Matches any value.
local FilterOptions = {}

function FilterOptions:new(this)
  this = this or {}
  this.include = this.include or {}
  this.exclude = this.exclude or {}
  this.match_opt = this.match_opt or "exact"
  this.mode = this.mode or "all"
  setmetatable(this, self)
  self.__index = self
  this:validate()
  return this
end

function FilterOptions:validate()
  local valid_match_opts = { "exact", "contains", "startswith", "endswith", "regex", "fuzzy" }
  local valid_modes = { "all", "any" }
  if self.include and type(self.include) ~= "table" then
    error("include must be a table")
  end
  if self.exclude and type(self.exclude) ~= "table" then
    error("exclude must be a table")
  end
  if not vim.tbl_contains(valid_match_opts, self.match_opt) then
    error("invalid match_opt: `" .. self.match_opt .. "` not in " .. vim.inspect(valid_match_opts))
  end
  if not vim.tbl_contains(valid_modes, self.mode) then
    error("invalid mode: `" .. self.mode .. "` not in " .. vim.inspect(valid_modes))
  end
end


-- The perform_match function now takes an additional parameter, the match type
---@param a string - The value to filter notes.
---@param b string - The value to filter notes.
---@param match_opt MatchOptions - The match type for filtering notes.
---|"'exact'" # Matches exact value. E.g., "foo" matches "foo" but not "foobar".
---|"'contains'" # Matches value if it contains the query. E.g., "foo" matches "foo" and "foobar".
---|"'startswith'" # Matches value if it starts with the query. E.g., "foo" matches "foo" and "foobar".
---|"'endswith'" # Matches value if it ends with the query. E.g., "foo" matches "foo" and "barfoo".
---|"'regex'" # Matches value if it matches the query as a regex. E.g., "foo" matches "foo" and "barfoo".
---@return boolean
function FilterOptions.has_match(a, b, match_opt)
  local result = false
  if match_opt == "exact" then
    if a == b then
      result = true
    end
  elseif match_opt == "contains" then
    if string.find(a, ".*" .. b .. ".*") then
      result = true
    end
  elseif match_opt == "startswith" then
    if string.sub(a, 1, #b) == b then
      result = true
    end
  elseif match_opt == "endswith" then
    if string.sub(a, -#b) == b then
      result = true
    end
  elseif match_opt == "regex" then
    if string.match(a, b) then
      result = true
    end
  else
    error("Invalid match: " .. match_opt .. ". Valid matches are: exact, contains, startswith, endswith, regex")
    return false
  end
  return result
end


---Handles the any mode for filtering notes.
---@param mode string - The mode to filter notes.
---|"'all'" # Matches all values.
---|"'any'" # Matches any value.
---@param tbl table - The value to filter notes.
---@param key string - The key to filter notes.
---@param a string - The value to filter notes.
---@param b string - The value to filter notes.
---@param match_opt string - The match type for filtering notes.
---|"'exact'" # Matches exact value. E.g., "foo" matches "foo" but not "foobar".
---|"'contains'" # Matches value if it contains the query. E.g., "foo" matches "foo" and "foobar".
---|"'startswith'" # Matches value if it starts with the query. E.g., "foo" matches "foo" and "foobar".
---|"'endswith'" # Matches value if it ends with the query. E.g., "foo" matches "foo" and "barfoo".
---|"'regex'" # Matches value if it matches the query as a regex. E.g., "foo" matches "foo" and "barfoo".
---@param notes Notes - The notes to filter.
---@param existing_notes table<string, boolean> - The existing notes.
function FilterOptions.handle_mode(mode, tbl, key, a, b, match_opt, notes, existing_notes)
  mode = mode or "all"
  for _, opt in ipairs(ModeOptions) do
    if mode ~= opt then
      error("Invalid mode: " .. mode .. ". Valid modes are: " .. table.concat(ModeOptions, ", "))
      return false
    end
  end
  if FilterOptions.has_match(tbl, b, match_opt) then
    ---@type table
    for _, note_path in ipairs(tbl.notes_paths) do
      local note = require("vault.note"):new({ path = note_path })
      local note_tags = note:tags()

      for _, note_tag in ipairs(note_tags) do
        if FilterOptions.has_match(note_tag.value, b, match_opt) and not existing_notes[note.path] then
          table.insert(notes, note)
          existing_notes[note.path] = true
        end
      end
    end
  end
end



---Handles the all mode for filtering notes.
--- It should include all query tags_values and exclude all exclude tags_values
---@param tag_value string - The tag value to filter notes.
---@param notes_paths string[] - The notes paths to filter.
function FilterOptions.handle_mode_all(tag_value, notes_paths, filter_options)
  for _, note_path in ipairs(notes_paths) do
    local note = require('vault.note'):new({ path = note_path })
    local note_tags = note:tags()

    local contains_all_tags = true
    for _, query in ipairs(filter_options.include) do
      for _, query in ipairs(filter_options.exclude) do
        local contains_tag = false
        for _, note_tag in ipairs(note_tags) do
          if FilterOptions.has_match(note_tag.value, query, filter_options.match_opt) then
            contains_tag = true
            break
          end
        end
        if not contains_tag then
          contains_all_tags = false
          break
        else
          contains_all_tags = true
        end
      end
    end

    if contains_all_tags and not seen_notes[note_path] then
      table.insert(filtered_notes, note)
      seen_notes[note.path] = true
    end
  end
end

	---Handles the any mode for filtering notes.
	local function handle_mode_any(tag, tag_value)
		--- Make sure that tag.notes_paths is table
		if FilterOptions.has_match(tag.value, tag_value, match_opt) then
			---@type table
			for _, note_path in ipairs(tag.notes_paths) do
				local note = Note:new({ path = note_path })
				local note_tags = note:tags()

				for _, note_tag in ipairs(note_tags) do
					if FilterOptions.has_match(note_tag.value, tag_value, match_opt) and not seen_notes[note.path] then
						table.insert(filtered_notes, note)
						seen_notes[note.path] = true
					end
				end
			end
		end
	end

function FilterOptions.match_all(tbl, b, match_opt)
  -- for _, opt in ipairs(MatchOptions) do
  --   if match_opt ~= opt then
  --     error("Invalid match: " .. match_opt .. ". Valid matches are: " .. table.concat(MatchOptions, ", "))
  --     return false
  --   end
  -- end
  local result = true
  for _, a in ipairs(tbl) do
    if not FilterOptions.has_match(a, b, match_opt) then
      result = false
      break
    end
  end
  return result
end

return FilterOptions
