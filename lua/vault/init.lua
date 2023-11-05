local Job = require("plenary.job")
local Tag = require("vault.tag")


---@class Vault
---@field setup function - Setup the vault plugin.
---@field notes function|Note[] - Retrieve notes from vault.
---@field notes_with_tags function|Note[] - Retrieve notes from vault with tags.
---@field tags function|Tag[] - Retrieve tags from vault.
local Vault = {}

---Create a new Vault object.
---@return Vault
function Vault:new()
	local o = {}
	setmetatable(o, self)
	self.__index = self
	return o
end

local config

---Setup the vault plugin.
function Vault.setup()
	config = require("vault.config")
	require("vault.commands")
	require("vault.cmp").setup()
end

---@param line string - The line to parse.
---@param tbl table - The table to extend.
---@return table? - The table with the tags.
local function parse_line_with_tags(line, tbl)
	local path, line_with_tag = line:match("^(.*" .. config.ext .. "):(.+)")
	if path == nil or line_with_tag == nil then
		return
	end

	for tag_value in line:gmatch("#([A-Za-z0-9_][A-Za-z0-9-_/]+)") do
		if Tag.is_tag(tag_value) == false then
			goto continue
		end

		if tbl[tag_value] == nil then
			local tag = Tag:new({ value = tag_value, notes_paths = { path } })
			tbl[tag_value] = tag
		else
			vim.list_extend(tbl[tag_value].notes_paths, { path })
		end
		::continue::
	end
	return tbl
end

---Retrieve notes from vault.
---@return Note[] - Array of Note objects.
function Vault.notes()
	local notes = {}

	local paths = vim.fn.globpath(config.dirs.root, "**/*" .. config.ext, true, true)
	for _, path in ipairs(paths) do
		local note = require("vault.note"):new({
			path = path,
		})
		table.insert(notes, note)
	end

	return notes
end

---Filter notes from vault.
---@param k string - Key to filter.
---@param v string - Value to filter.
function Vault.notes_filter(k, v)
	local notes = Vault.notes()
	local filtered_notes = {}
	for _, note in ipairs(notes) do
		-- if key contains value
		if type(v) == "string" then
			if note[k]:find(v) then
				table.insert(filtered_notes, note)
			end
		end
	end
	return filtered_notes
end

-- Define the match functions outside the main function
local match_functions = {
	["EXACT"] = function(a, b)
		return a == b
	end,
	["CONTAINS"] = function(a, b)
		return string.find(a, ".*" .. b .. ".*")
	end,
	["STARTSWITH"] = function(a, b)
		return string.sub(a, 1, #b) == b
	end,
	["ENDSWITH"] = function(a, b)
		return string.sub(a, -#b) == b
	end,
	["REGEX"] = function(a, b)
		return string.match(a, b)
	end,
}

-- The perform_match function now takes an additional parameter, the match type
local function perform_match(a, b, match)
	return match_functions[match](a, b)
end

---Collects all tags matching the specified tag values.
local function collect_matching_tags(tbl, values, match)
	for _, value in ipairs(values) do
		local matching_tags = Vault.tags(value, match)
		for k, v in pairs(matching_tags) do
			tbl[k] = v
		end
	end
	return tbl
end

--- Retrieves notes from the vault based on specified tags, behavior, and matching criteria.
---@param tag_values string[] - Array of tag values to filter notes.
---@param behavior string? - Behavior for filtering notes (optional). Options: "AND", "OR", "NOT".
---@param match string? - Match type for filtering notes (optional). Options: "EXACT", "CONTAINS", "STARTSWITH", "ENDSWITH", "REGEX".
---@return Note[] - Array of Note objects matching the criteria.
function Vault.notes_with_tags(tag_values, match, behavior)
	behavior = behavior or "AND"
	match = match or "EXACT"

	local valid_behaviors = { "AND", "OR", "NOT" }
	local valid_matches = { "EXACT", "CONTAINS", "STARTSWITH", "ENDSWITH", "REGEX" }

	if not vim.tbl_contains(valid_behaviors, behavior) then
		error("Invalid behavior: " .. behavior .. ". Valid behaviors are: " .. table.concat(valid_behaviors, ", "))
	end

	if not vim.tbl_contains(valid_matches, match) then
		error("Invalid match: " .. match .. ". Valid matches are: " .. table.concat(valid_matches, ", "))
	end

	local Note = require("vault.note")
	local all_tags = {}
	local notes_matching_tags = {}
	local added_notes = {}

	---Handles the AND behavior for filtering notes.
	---@param tag Tag - The tag to filter notes.
	local function handle_and_behavior(tag)
		for _, note_path in ipairs(tag.notes_paths) do
			local note = Note:new({ path = note_path })
			local note_tags = note:tags()

			local contains_all_tags = true
			for _, value in ipairs(tag_values) do
				local contains_tag = false
				for _, note_tag in ipairs(note_tags) do
					if perform_match(note_tag.value, value, match) then
						contains_tag = true
						break
					end
				end
				if not contains_tag then
					contains_all_tags = false
					break
				end
			end

			if contains_all_tags and not added_notes[note.path] then
				table.insert(notes_matching_tags, note)
				added_notes[note.path] = true
			end
		end
	end

	---Handles the OR behavior for filtering notes.
	---@param tag Tag - The tag to filter notes.
	---@param tag_value string - The tag value to filter notes.
	local function handle_or_behavior(tag, tag_value)
    --- Make sure that tag.notes_paths is table
		if perform_match(tag.value, tag_value, match) then
      ---@type table
			for _, note_path in ipairs(tag.notes_paths) do
				local note = Note:new({ path = note_path })
				local note_tags = note:tags()

				for _, note_tag in ipairs(note_tags) do
					if perform_match(note_tag.value, tag_value, match) and not added_notes[note.path] then
						table.insert(notes_matching_tags, note)
						added_notes[note.path] = true
					end
				end
			end
		end
	end

	local all_notes = Vault.notes()

	---Handles the NOT behavior for filtering notes.
	---Exclude notes that perform_match the tag_value.
	---@param tag Tag - The tag to filter notes.
	---@param notes Note[] - The notes to filter.
	local function handle_not_behavior(notes, tag)
		for _, note_path in ipairs(tag.notes_paths) do
			for i, note in ipairs(notes) do
				if note.path == note_path then
          table.remove(notes, i)
				end
			end
		end
	end

	---Handles the specified behavior for filtering notes.
	---@param tag_value string - The tag value to filter notes.
	local function handle_behavior(tag_value, tags)
		for _, tag in pairs(tags) do
			if behavior == "AND" then
				handle_and_behavior(tag)
			elseif behavior == "OR" then
				handle_or_behavior(tag, tag_value)
			elseif behavior == "NOT" then
				handle_not_behavior(all_notes, tag)
			end
		end
	end

	all_tags = collect_matching_tags(all_tags, tag_values, match)
	for _, tag_value in ipairs(tag_values) do
		handle_behavior(tag_value, all_tags)
	end

  if behavior == "NOT" then
    notes_matching_tags = all_notes
  end

	return notes_matching_tags
end

---Retrieve notes from vault with contains tags. (if tag_value contains in note tag value. e.g. #foobar contains #foo)
---@param tag_values string[] - Array of tag values.
---@return Note[] - Array of Note objects.
function Vault.notes_with_contains_tags(tag_values)
	local Note = require("vault.note")
	local tags = {}
	local notes_with_tags = {}

	local added_notes = {}

	local function is_contains_all_tags(note_tags)
		for _, v in ipairs(tag_values) do
			local contains_tag = false
			for _, note_tag in ipairs(note_tags) do
				if note_tag.value:find(v) then
					contains_tag = true
					break
				end
			end
			if not contains_tag then
				return false
			end
		end
		return true
	end

	-- Collecting all tags into a single table
	for _, tag_value in ipairs(tag_values) do
		local tags_with_value = Vault.tags(tag_value)
		for k, v in pairs(tags_with_value) do
			tags[k] = v
		end
	end

	if next(tags) == nil then
		error("No tags found in the vault")
	end

	for _, tag_value in ipairs(tag_values) do
		for _, tag in pairs(tags) do
			if tag.value:find(tag_value) then
				for _, note_path in ipairs(tag.notes_paths) do
					local note = Note:new({ path = note_path })
					local note_tags = note:tags()

					if is_contains_all_tags(note_tags) and not added_notes[note.path] then
						table.insert(notes_with_tags, note)
						added_notes[note.path] = true
					end
				end
				break
			end
		end
	end

	return notes_with_tags
end

--- Retrieve tags from your vault.
---@param tag_prefix string? - Prefix to filter tags (optional).
---@param match string? - Match to filter tags (optional).
---@return Tag[] - Array of Tag objects.
function Vault.tags(tag_prefix, match)
	match = match or "EXACT"
	local cmd = "rg"
	local tag_pattern = [[#[A-Za-z0-9_][A-Za-z0-9-_/]+]]
	local root_dir = config.dirs.root
	local args = {
		"--no-heading",
		tag_pattern,
		root_dir,
	}

	local stdout = {}

	Job:new({
		command = cmd,
		args = args,
		cwd = config.dirs.root,

		on_exit = function(j, return_val)
			if return_val ~= 0 then
				return
			end

			stdout = j:result()
		end,
	}):sync()

	local tags = {}

	for _, line in pairs(stdout) do
		if Tag.is_tag_context(line) == false then
			goto continue
		end
		local tags_from_line = parse_line_with_tags(line, tags)
		if tags_from_line == nil then
			goto continue
		end
		vim.tbl_extend("force", tags, tags_from_line)
		::continue::
	end

	if tag_prefix ~= nil then
		for tag_value, _ in pairs(tags) do
			-- if tag_value:sub(1, #tag_prefix) ~= tag_prefix then
			if not perform_match(tag_value, tag_prefix, match) then
				tags[tag_value] = nil
			end
		end
	end

	return tags
end

function Vault.test()
	vim.cmd("lua package.loaded['vault'] = nil")
	local notes = Vault.notes()
	---@diagnostic disable-next-line
	P(notes)
end

return Vault
