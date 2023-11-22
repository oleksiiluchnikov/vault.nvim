local Object = require("nui.object")

local utils = require("vault.utils")
local config = require("vault.config")
local Tag = require("vault.tags.tag")
local Matcher = require("vault.utils.matcher")
local NoteFrontmatter = require("vault.notes.note.frontmatter")
local metadata = require("vault.notes.note.metadata")


---Fetch content from the specified path.
---@param path string - The path to the note to fetch content from.
---@return string?
local function fetch_content(path)
	if path == nil then
		return
	end

	local f = io.open(path, "r")
	if f == nil then
		return
	end

	local content = f:read("*all")
	f:close()
	return content
end

---Fetch body from the specified path.
---@param path string - The path to the note to fetch body from.
---@param content string? - The content of the note.
---@param frontmatter string? - The frontmatter of the note.
---@return string?
local function fetch_body(path, content, frontmatter)
	content = content or fetch_content(path)
	if content == nil then
		return
	end

	frontmatter = frontmatter or NoteFrontmatter(content)

	local body = content
	if frontmatter ~= nil then
		body = content:gsub(frontmatter, "")
	end
	return body
end

---Fetch title from the specified path.
---@param path string - The path to the note to fetch title from.
---@param content string? - The content of the note.
---@return string?
local function fetch_title(path, content)
	if not path then
		return nil
	end
	content = content or fetch_content(path)

	if content == nil then
    return
	end

  --- For example: "---\nsome: frontmatter\n---\n# title\n\nbody" or "# title\n\nbody" or "# title\nbody"
  -- local title = content:match("#%s(.*)\n") -- it cahches also ## title, so we need to fix it
  -- local title = content:match("[\n\r^]#%s(.*)\n")
  local title = content:match("[\n\r^]#%s(.-)[\n\r$]")
  if not title then
    return
  end

  return title
end

---@param path string
---@param content string?
---@return table? - List of tags.
local function fetch_tags(path, content)
	if not path then
		return nil
	end
	content = content or fetch_content(path)
  if not content then
    return nil
  end
	local tags = {}
	for match in content:gmatch([[#([A-Za-z0-9_][A-Za-z0-9-_/]+)]]) do
		local tag = Tag({
			value = match,
			notes_paths = { path },
		})
		table.insert(tags, tag)
	end
	return tags
end

---Fetch class from the specified path.
---@param path string - The path to the note to fetch class from.
---@param content string - The content of the note.
---@return string? - The class of the note.
local function fetch_type(path, content)
  if not path then
    return nil
  end
  content = content or fetch_content(path)
	local class
	local pattern = config.search_pattern.note.type or "%s#class/([A-Za-z0-9_-]+)"
	local match = content:match(pattern)
	if not match then
    return nil
	end
  class = match
  return class
end

---Fetch status from the specified path.
---@parap path string - The path to the note to fetch status from.
---@param content string - The content of the note.
---@return string? - The status of the note.
local function fetch_status(path, content)
  if not path then
    return nil
  end
  content = content or fetch_content(path)
  local status
  local pattern = config.search_pattern.status or "%s#status/([A-Za-z0-9_-]+)"
  local match = content:match(pattern)
  if not match then
    return nil
  end
  status = match
  return status
end

-- FIXME: This function returns nil.
---Fetch mapview like keys from the specified path.
---@param path string?
---@return string[]?
local function fetch_keys(path, content)
  if not path then
    return nil
  end
	content = content or fetch_content(path)
	if type(content) ~= "string" then
		return
	end

	local keys = {}
	local block_field_pattern = "([A-Za-z%-%_]+)::%s*%w+"
	-- local inline_field_pattern = "([A-Za-z%-%_]+)::%s*%w+"
	local frontmatter_key_pattern = "([A-Za-z%-%_]+):%s*%w+"

	-- local patterns = {
	-- 	block_field_pattern,
	-- 	inline_field_pattern,
	-- 	frontmatter_key_pattern,
	-- }

	-- for line_number, line in ipairs(lines) do
	-- 	for _, pattern in ipairs(patterns) do
	-- 		for key in line:gmatch(pattern) do
	-- 			if key ~= nil then
	-- 				if keys[line_number] == nil then
	-- 					keys[line_number] = {}
	-- 				end
	-- 				local column_number = 0
	-- 				for i = 1, #line do
	-- 					if line:sub(i, i) == key:sub(1, 1) then
	-- 						column_number = i
	-- 						break
	-- 					end
	-- 				end
	-- 				keys[line_number] = {}
	-- 				table.insert(keys[line_number], {
	-- 					column_number,
	-- 				})
	-- 				keys[line_number][column_number] = key
	-- 			end
	-- 		end
	-- 	end
	-- end

	-- I want to return something like this:
	-- keys = {
	-- {
	--   ["title"] = {3,1} -- line_number, column_number
	--   ["created"] = {3,1}
	--   ["modified"] = {3,1}
	--   ["class"] = {3,1}
	--   ["tags"] = {3,1}
	--   ["inline"] = {3,1}
	--   ["block"] = {3,1}
	-- }
	-- }

  local frontmatter = NoteFrontmatter(content)
	for key in frontmatter:gmatch(frontmatter_key_pattern) do
		if key ~= nil then
			keys[key] = { 1, 1 }
		end
	end

	local body = fetch_body(path, content, frontmatter)
  if not body then
    return nil
  end
	for key in body:gmatch(block_field_pattern) do
		if key ~= nil then
			keys[key] = { 1, 1 }
		end
	end

	return keys
end


---@class VaultNoteData
---@field path string - The absolute path to the note.
---@field relpath string? - The relative path to the root directory of the note.
---@field basename string? - The basename of the note.
---@field frontmatter string? - The frontmatter of the note.
---@field content string? - The content of the note.
---@field body string? - The body of the note.
---@field title string? - The title of the note.
---@field tags VaultTag[]? - The tags of the note.
---@field inlinks string[]? - List of inlinks to the note.
---@field outlinks string[]? - List of outlinks from the note.
---@field type string? - The type of the note.
---@field status string? - The status of the note.
local NoteData = {}

---@param this VaultNoteData
function NoteData:new(this)
  this = this or {}
  for k, _ in pairs(this) do
    if not vim.tbl_contains(metadata.keys, k) then
      error("Invalid key: " .. vim.inspect(k) .. ". Valid keys: " .. vim.inspect(metadata.keys))
    end
  end
  setmetatable(this, self)
  return this
end

function NoteData:__index(key)

  if not vim.tbl_contains(metadata.keys, key) then
    return nil
  end

  if key == "relpath" then
    return utils.to_relpath(self.path)
  elseif key == "basename" then
    local basename = vim.fn.fnamemodify(self.path, ":t")
    if type(basename) ~= "string" then
      error("Invalid basename: " .. vim.inspect(basename))
    end
    self.basename = basename
    return basename
  elseif key == "frontmatter" then
    self.frontmatter = NoteFrontmatter(self.content)
    return self.frontmatter
  elseif key == "content" then
    self.content = fetch_content(self.path)
    return self.content
  elseif key == "body" then
    self.body = fetch_body(self.path, self.content, self.frontmatter)
    return self.body
  elseif key == "title" then
    -- return fetch_title(self.path, self.content)
    self.title = fetch_title(self.path, self.content)
    return self.title
  elseif key == "tags" then
    -- return fetch_tags(self.path, self.content)
    self.tags = fetch_tags(self.path, self.content)
    return self.tags
  elseif key == "type" then
    -- return fetch_type(self.path, self.content)
    self.type = fetch_type(self.path, self.content)
    return self.type
  elseif key == "status" then
    -- return fetch_status(self.path, self.content)
    self.status = fetch_status(self.path, self.content)
    return self.status
  else
    return rawget(self, key)
  end
end

---Create a new note if it does not exist.
---@class VaultNote
---@field data VaultNoteData - The data of the note.data.
local Note = Object("VaultNote")

---@param this VaultNoteData?
function Note:init(this)
	if type(this) == "string" then -- it's a possible path to the note
		local path = vim.fn.expand(this)
    -- assert(type(path) == "string", "Failed to expand path: " .. vim.inspect(path))
    if type(path) ~= "string" then
      error("Failed to expand path: " .. vim.inspect(path))
    end
		this = {
			path = path,
		}
	end
  if type(this) ~= "table" then
    error("Invalid argument: " .. vim.inspect(this))
  end

  if not this.path then
    error("missing `path` : " .. vim.inspect(this))
  end

  self.data = NoteData:new(this)
end

function Note:__tostring()
  return "VaultNote: " .. vim.inspect(self)
end


---Write note file to the specified path.
---@param path string?
---@param content string?
function Note:write(path, content)
  path = path or self.data.path

  if type(path) ~= "string" then
    error("Invalid path: " .. vim.inspect(path))
  end

  content = content or self.data.content

	local root_dir = config.dirs.root
	local ext = config.ext

  if not path:match(ext .. "$") then
    error("Invalid file extension: " .. vim.inspect(path))
  end

  if not path:match(root_dir) then
    error("Invalid path: " .. vim.inspect(path))
  end

	local basename = vim.fn.fnamemodify(path, ":t")
  if not basename then
    error("Invalid basename: " .. vim.inspect(path))
  end

	local f = io.open(path, "w")
  if not f then
    error("Failed to open file: " .. vim.inspect(path))
  end

	f:write(content)
	f:close()

	if config.notify.on_write == true then
		vim.notify("Note created: " .. path)
	end
end

---Edit note
---@class VaultNote
---@param path string
function Note:edit(path)
	path = path or self.data.path
	if vim.fn.filereadable(path) == 0 then
		error("File not found: " .. path)
		return
	end
	vim.cmd("e " .. path)
end

---Open a note in the vault
---@class VaultNote
---@param path string
function Note:open(path)
	path = path or self.data.path
	-- if path.sub(1, -4) ~= ".md" then
	local ext = config.ext
	local pattern = ext .. "$"
	if path:match(pattern) == nil then
		---@type VaultNote
		local note = Note({
			path = path,
		})
		if note == nil then
			return
		end
		path = note.data.path
	end

	vim.cmd("e " .. path)
end

---Preview with Glow.nvim
function Note:preview()
	if vim.fn.executable("glow") == 0 and package.loaded["glow"] == nil then
		vim.notify("Glow is not installed")
		return
	end
	vim.cmd("Glow " .. self.data.path)
end

---Check if note has an exact tag name.
---@param tag_name string - Exact tag name to search for.
---@param match_opt string? - Match option. @see utils.matcher
function Note:has_tag(tag_name, match_opt)
  if not tag_name then
    error("`tag_name` is required")
  end
  local note_tags = self.data.tags
  if not note_tags then
    return false
  end

  match_opt = match_opt or "exact"
  for _, tag in ipairs(note_tags) do
    if Matcher:match(tag.data.name, tag_name, match_opt) then
      return true
    end
  end
  return false
end

-- FIXME: This function is slow, and not working properly.
---@param path string?
---@return Wikilink[]?
function Note:inlinks(path)
	path = path or self.data.path
	-- local notes_paths = list.notes_paths(root_dir, config.ignore)
  local Notes = require("vault.notes")
	local notes_map = Notes().map
	local notes_paths = {}
	vim.tbl_map(function(note)
		table.insert(notes_paths, note.data.path)
	end, notes_map)

	local inlinks = {}
	for _, note_path in ipairs(notes_paths) do
		local f = io.open(note_path, "r")
		if f == nil then
			return
		end
		local line = f:read("*line")
		while line ~= nil do
			local link = line:match("%[%[([^%]]+)%]%]")
			if link ~= nil then
				local link_title = link
				local link_heading = nil
				local link_custom_title = nil

				local link_parts = vim.split(link, "|")
				if #link_parts == 2 then
					link_title = link_parts[1]
					link_custom_title = link_parts[2]
				end

				link_parts = vim.split(link_title, "#")
				if #link_parts == 2 then
					link_title = link_parts[1]
					link_heading = link_parts[2]
				end

				link_parts = vim.split(link_title, "/")
				if #link_parts > 1 then
					link_title = link_parts[#link_parts]
				end

				local relpath = utils.to_relpath(note_path)
				---if relpath contains .md then remove it
				if relpath:sub(#relpath - 2) == ".md" then
					relpath = relpath:sub(1, #relpath - 3)
				end

				if link_title == vim.fn.fnamemodify(note_path, ":t:r") then
					table.insert(inlinks, {
						line = line,
						link = link,
						source = {
							path = note_path,
							relpath = relpath,
							title = vim.fn.fnamemodify(note_path, ":t:r"),
						},
						heading = link_heading,
						custom_title = link_custom_title,
					})
				end
			end
			line = f:read("*line")
		end
		f:close()
	end
	return inlinks
end

-- FIXME: This function returns nil. It should return a list of outlinks.
---Fetch outlinks from the specified path.
---@param path string
---@return Wikilink[]?
function Note:outlinks(path, content)
	path = path or self.data.path
	content = content or self.data.content
	if type(content) ~= "string" then
		return
	end

	---@type Wikilink[]
	local outlinks = {}
	local pattern = config.search_pattern.wikilink

	for link in content:gmatch(pattern) do
		-- local wikilink_map = wikilink.parse(link)
		-- if wikilink_map == nil then
		-- 	goto continue
		-- end
		table.insert(outlinks, link)
	end

	return outlinks
end

-- TEST: This function is not tested.
---@param path string - The path to the note to update inlinks.
function Note:update_inlinks(path)
	local root_dir = config.dirs.root
	if type(root_dir) ~= "string" then
		return
	end

	if type(path) ~= "string" then
		return
	end

	local relpath = utils.to_relpath(path) -- current note path with relative path
	if relpath:sub(#relpath - 2) == ".md" then
		relpath = relpath:sub(1, #relpath - 3)
	end

	local inlinks = self.inlinks
	if inlinks == nil then
		return
	end

	for _, inlink in ipairs(inlinks) do
		local new_link = inlink.link
		local new_link_title = relpath -- new link title will be relative path to the current note
		if inlink.heading ~= nil then
			new_link_title = new_link_title .. "#" .. inlink.heading
		end
		if inlink.custom_title ~= nil then
			new_link_title = new_link_title .. "|" .. inlink.custom_title
		end
		new_link = new_link:gsub(inlink.link, new_link_title)
		local f = io.open(inlink.source.data.path, "r")
		if f == nil then
			return
		end
		local content = f:read("*all")
		f:close()
		content = content:gsub(inlink.link, new_link)
		f = io.open(inlink.source.data.path, "w")
		if f == nil then
			return
		end
		f:write(content)
		f:close()
		vim.notify(inlink.link .. " -> " .. new_link)
	end
end

---Compare two values of a note keys.
---@param a string
---@param b string
function Note:compare_values_of(a, b)
  assert(a, "missing a")
  assert(b, "missing b")

  if type(a) ~= "string" or type(b) ~= "string" then
    return false
  end

  if self[a] == nil or self[b] == nil then
    return false
  end

  if self[a] == self[b] then
    return true
  end

  return false
end

---@alias VaultNote.constructor fun(this: VaultNote|string): VaultNote
---@type VaultNote|VaultNote.constructor
local VaultNote = Note

return VaultNote-- [[@as VaultNote.constructor]]
