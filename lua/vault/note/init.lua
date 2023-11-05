---@class Note
local Note = {}

local utils = require("vault.utils")
local list = require("vault.list")
local config = require("vault.config")

---Create a new note if it does not exist.
---@class Note
---@field path string - The absolute path to the note.
---@field relpath string - The relative path to the root directory of the note.
---@field basename string - The basename of the note.
---@field title string|function - The title of the note.
---@field content string|function - The content of the note.
---@field tags Tag[]|function - The tags of the note.
---@field inlinks string[]|function - List of inlinks to the note.
---@field outlinks string[]|function - List of outlinks from the note.
---@field class string|function - The class of the note.
---@field status string? - The status of the note.

---@param obj table
---@return Note
function Note:new(obj)
  obj = obj or {}
  obj.relpath = obj.relpath or utils.to_relpath(obj.path)
  obj.basename = obj.basename or vim.fn.fnamemodify(obj.path, ":t")
  obj.content = obj.content or self:content(obj.path)
  obj.class = obj.class or self:class(obj.content)
  setmetatable(obj, self)
  self.__index = self
	return obj
end

---Fetch class from the specified path.
---@param content string - The content of the note.
---@return string?
function Note:class(content)
  content = content or self.content
  local class
  local pattern = config.search_pattern.class
  local match = content:match(pattern)
  if match ~= nil then
    class = match
  end
  return class
end

---Write note filet to the specified path.
---@param path string
---@param content string
---@return boolean
function Note:write(path, content)
	local root_dir = config.dirs.root
	local ext = config.ext

	if path.gmatch(path, ext) == nil then
		error("Invalid file extension: " .. path)
		return false
	end

	if path.gmatch(path, root_dir) == nil then
		error("Invalid path: " .. path)
		return false
	end

	local f = io.open(path, "r")
	if f ~= nil then
		f:close()
		error("File already exists: " .. path)
		return false
	end

	f = io.open(path, "w")
	if f == nil then
		error("Failed to open file: " .. path)
		return false
	end

	f:write(content)
	f:close()
	return true
end

---Fetch class from the specified path.
---@param path string - The {absolute} path to the note to fetch class from.
---@param content string - The content of the note.
---@return string
function Note:title(path, content)
  path = path or self.path
  content = content or self:content(path)

	local title = self.basename

  -- local pattern = "\n# (.*)\n"
  -- local match = content:match(pattern)
  -- if match ~= nil then
  --   title = match
  -- end

  for line in content:gmatch("([^\n]*)\n?") do
    if line:sub(1, 1) == "#" then
      title = line:sub(3)
      break
    end
  end
	return title
end


---Fetch content from the specified path.
---@param path string? - The path to the note to fetch content from.
---@return string?
function Note:content(path)
	path = path or self.path

	local f = io.open(path, "r")
	if f == nil then
		return
	end

	local content = f:read("*all")
	f:close()
	return content
end

--- Preview with Glow.nvim
function Note:preview()
	if vim.fn.executable("glow") == 0 and package.loaded["glow"] == nil then
		vim.notify("Glow is not installed")
		return
	end
	vim.cmd("Glow " .. self.path)
end

---@param path string?
---@param content string|function?
---@return table -- 
function Note:tags(path, content)
  path = path or self.path
  content = content or self.content or self:content(path)

  local Tag = require("vault.tag")
	local tags = {}
	for match in content:gmatch([[#([A-Za-z0-9_][A-Za-z0-9-_/]+)]]) do
    local tag = Tag:new({
      value = match,
      notes_paths = { path },
    })
    table.insert(tags, tag)
  end
	return tags
end

---@class Wikilink
---@field raw string - The raw link as it appears in the note. e.g. [[link|title]]
---@field link string - The link as it appears in the note. e.g. link
---@field source string - The path to the note that contains the link. e.g. /home/user/notes/link.md
---@field heading string? - The heading of the link. e.g. link#heading
---@field custom_title string? - The custom title of the link. e.g. link|title

-- FIXME: This function is slow, and not working properly.
---@param path string?
---@return Wikilink[]?
function Note:inlinks(path)
  path = path or self.path
	local root_dir = config.dirs.root


	local notes_paths = list.notes_paths(root_dir, config.ignore)
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
				--- if relpath contains .md then remove it
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
  path = path or self.path
  content = content or self.content or self:content(path)
	if type(content) ~= "string" then
		return
	end

	---@type Wikilink[]
	local outlinks = {}
	local pattern = config.search_pattern.wikilink

	for link in content:gmatch(pattern) do
		-- local wikilink_data = wikilink.parse(link)
		-- if wikilink_data == nil then
		-- 	goto continue
		-- end
		table.insert(outlinks, link)
	end

	return outlinks
end

-- TEST: This function is not tested.
---@param path string - The path to the note to update inlinks.
function Note.update_inlinks(path)
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

	local inlinks = Note.inlinks(path)
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
		local f = io.open(inlink.source.path, "r")
		if f == nil then
			return
		end
		local content = f:read("*all")
		f:close()
		content = content:gsub(inlink.link, new_link)
		f = io.open(inlink.source.path, "w")
		if f == nil then
			return
		end
		f:write(content)
		f:close()
		vim.notify(inlink.link .. " -> " .. new_link)
	end
end

-- FIXME: This function returns nil. 
---Fetch dataview like keys from the specified path.
---@param path string
---@return string[]?
function Note:keys(path, content)
  path = path or self.path
  content = content or self.content or Note.content(path)
	if type(content) ~= "string" then
		return
	end

	local keys = {}
	local block_field_pattern = "([A-Za-z%-%_]+)::%s*%w+"
	local inline_field_pattern = "([A-Za-z%-%_]+):%s*%w+"
	local frontmatter_key_pattern = "([A-Za-z%-%_]+):%s*%w+"

	for key in content:gmatch(block_field_pattern) do
		table.insert(keys, key)
	end

	for key in content:gmatch(frontmatter_key_pattern) do
		table.insert(keys, key)
	end

	for key in content:gmatch(inline_field_pattern) do
		table.insert(keys, key)
	end

	return keys
end


---Edit note
---@class Note
---@param path string
function Note:edit(path)
  path = path or self.path
	if vim.fn.filereadable(path) == 0 then
    error("File not found: " .. path)
		return
	end
	vim.cmd("e " .. path)
end

---Open a note in the vault
---@class Note
---@param path string
function Note:open(path)
	path = path or self.path
	-- if path.sub(1, -4) ~= ".md" then
  local ext = config.ext
  local pattern = ext .. "$"
  if path:match(pattern) == nil then

    ---@type Note
		local note = Note:new({
      path = path,
    })
		if note == nil then
			return
		end
		path = note.path
	end

	vim.cmd("e " .. path)
end

function Note.test_tags()
	vim.cmd("lua package.loaded['vault.note'] = nil")
	-- local Vault = require("vault")
	local path = config.dirs.root .. "/Aspiration/Incease my cognitive abilities.md"
	local note = Note:new(path)
 --  local content = note:content()
	local tags = note:tags()
  print(vim.inspect(tags))
end

---Check if note has an exact tag value.
---@param tag_value string - Exact tag value to search for.
function Note:has_tag(tag_value)
  local content = self:content()
  local pattern = config.search_pattern.tag
  for tag in content:gmatch(pattern) do
    if tag == tag_value then
      return true
    end
  end
  return false
end

function Note:frontmatter(content)
  content = content or self:content()
  local frontmatter = {}
  local pattern = "---\n(.-)---.*"
  for match in content:gmatch(pattern) do
    local key, value = match:match("([%w_]+):%s*(.*)")
    frontmatter[key] = value
  end
  return frontmatter
end

return Note
