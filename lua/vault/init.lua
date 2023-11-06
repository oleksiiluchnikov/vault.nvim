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
---@param tag_values table - The table to store the tag values.
---@return string[]? - Array of tag values.
local function parse_line_for_tags(line, tag_values)
	local path, line_with_tag = line:match("^(.*" .. config.ext .. "):(.+)")
	if path == nil or line_with_tag == nil then
		return
	end

	for tag_value in line:gmatch("#([A-Za-z0-9_][A-Za-z0-9-_/]+)") do
		if Tag.is_tag(tag_value) == false then
			goto continue
		end

		if tag_values[tag_value] == nil then
			-- Initialize tag_values[tag_value] as table
			tag_values[tag_value] = { path }
		elseif not vim.tbl_contains(tag_values[tag_value], path) then
			vim.list_extend(tag_values[tag_value], { path })
		end
		-- elseif not vim.tbl_contains(tag_values[tag_value], path) then
		--     vim.tbl_extend("force", tag_values[tag_value], { path })
		-- end
		::continue::
	end
	return tag_values
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
	["exact"] = function(a, b)
		return a == b
	end,
	["contains"] = function(a, b)
		return string.find(a, ".*" .. b .. ".*")
	end,
	["startswith"] = function(a, b)
		return string.sub(a, 1, #b) == b
	end,
	["endswith"] = function(a, b)
		return string.sub(a, -#b) == b
	end,
	["regex"] = function(a, b)
		return string.match(a, b)
	end,
}

-- The perform_match function now takes an additional parameter, the match type
local function has_match(a, b, match_opt)
	return match_functions[match_opt](a, b)
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

	local valid_modes = { "all", "any" }
	local valid_matches = { "exact", "contains", "startswith", "endswith", "regex" }

	if not vim.tbl_contains(valid_modes, mode) then
		error(
			"Invalid mode: "
				.. mode
				.. ". Valid modes are: "
				.. table.concat(valid_modes, ", ")
		)
	end

	if not vim.tbl_contains(valid_matches, match_opt) then
		error("Invalid match: " .. match_opt .. ". Valid matches are: " .. table.concat(valid_matches, ", "))
	end

	local Note = require("vault.note")
	local added_notes = {}
	local filtered_notes = {}

  ---@type table<string, Tag>
	local tags = Vault.tags(include, exclude, match_opt)

	---Handles the all mode for filtering notes.
	---@param tag Tag - The tag to filter notes.
	local function handle_all_mode(tag)
		for _, note_path in ipairs(tag.notes_paths) do
			local note = Note:new({ path = note_path })
			local note_tags = note:tags()

			local contains_all_tags = true

			for _, value in ipairs(include) do
				local contains_tag = false
				for _, note_tag in ipairs(note_tags) do
					if has_match(note_tag.value, value, match_opt) then
						contains_tag = true
						break
					end
				end
				if not contains_tag then
					contains_all_tags = false
					break
				end
			end

			for _, value in ipairs(exclude) do
				local contains_tag = false
				for _, note_tag in ipairs(note_tags) do
					if has_match(note_tag.value, value, match_opt) then
						contains_tag = true
						break
					end
				end
				if contains_tag then
					contains_all_tags = false
					break
				end
			end

			if contains_all_tags and not added_notes[note.path] then
				table.insert(filtered_notes, note)
				added_notes[note.path] = true
			end
		end
	end

	---Handles the any mode for filtering notes.
	local function handle_any_mode(tag, tag_value)
		--- Make sure that tag.notes_paths is table
		if has_match(tag.value, tag_value, match_opt) then
			---@type table
			for _, note_path in ipairs(tag.notes_paths) do
				local note = Note:new({ path = note_path })
				local note_tags = note:tags()

				for _, note_tag in ipairs(note_tags) do
					if has_match(note_tag.value, tag_value, match_opt) and not added_notes[note.path] then
						table.insert(filtered_notes, note)
						added_notes[note.path] = true
					end
				end
			end
		end
	end

	for _, tag in pairs(tags) do
		if mode == "all" then
			handle_all_mode(tag)
		elseif mode == "any" then
			for _, tag_value in ipairs(include) do
				handle_any_mode(tag, tag_value)
			end
		end
	end

	return filtered_notes
end

--- Retrieve tags from your vault.
---@param include string[]? - Array of tag values to include (optional).
---@param exclude string[]? - Array of tag values to exclude (optional).
---@param match_opt string? - Match to filter tags (optional).
---@return Tag[] - Array of Tag objects.
function Vault.tags(include, exclude, match_opt)
	include = include or {}
	exclude = exclude or {}
	match_opt = match_opt or "exact"

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

	---@type table<string, string[]> - Table of tag values and their notes paths.
	local tags_values = {}
	for _, line in pairs(stdout) do
		if Tag.is_tag_context(line) == false then
			goto continue
		end
		---@type string[]?
		local tags_values_from_line = parse_line_for_tags(line, tags_values)
		if tags_values_from_line == nil then
			goto continue
		end

		::continue::
	end

	for tag_value, _ in pairs(tags_values) do
		local should_include = false
		local should_exclude = false

		for _, query in ipairs(include) do
			if has_match(tag_value, query, match_opt) then
				should_include = true
				break
			end
		end

		for _, query in ipairs(exclude) do
			if has_match(tag_value, query, match_opt) then
				should_exclude = true
				break
			end
		end

		if should_include and not should_exclude then
			tags[tag_value] = Tag:new({
				value = tag_value,
				notes_paths = tags_values[tag_value],
			})
    elseif #include == 0 and #exclude == 0 then
      tags[tag_value] = Tag:new({
        value = tag_value,
        notes_paths = tags_values[tag_value],
      })
      end
	end
	return tags
end

function Vault.test()
	vim.cmd("lua package.loaded['vault'] = nil")
	vim.cmd("lua require('vault').setup({})")
	-- local output= Vault.tags({ "status", "class" }, {"status/TODO"}, "startswith")
	local output = Vault.notes_filter_by_tags({ "status" }, { "status/TODO" }, "startswith", "all")
	require("vault.pickers").notes(output)
end

return Vault
