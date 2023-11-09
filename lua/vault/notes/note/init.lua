
local utils = require("vault.utils")
local list = require("vault.list")
local config = require("vault.config")


---Create a new note if it does not exist.
---@class Note
---@field path string - The absolute path to the note.
---@field relpath string - The relative path to the root directory of the note.
---@field basename string - The basename of the note.
---@field frontmatter string|function - The frontmatter of the note.
---@field content string|function - The content of the note.
---@field body string|function - The body of the note.
---@field title string|function - The title of the note.
---@field tags Tag[]|function - The tags of the note.
---@field inlinks string[]|function - List of inlinks to the note.
---@field outlinks string[]|function - List of outlinks from the note.
---@field class string|function - The class of the note.
---@field status string? - The status of the note.
local Note = {}

---@param obj table
---@return Note
function Note:new(obj)
	obj = obj or {}
	obj.relpath = obj.relpath or utils.to_relpath(obj.path)
	obj.basename = obj.basename or vim.fn.fnamemodify(obj.path, ":t")
	obj.content = obj.content or self:content(obj.path)
  obj.frontmatter = obj.frontmatter or self:frontmatter(obj.path, obj.content)
  obj.body = obj.body or self:body(obj.path, obj.content, obj.frontmatter)

	setmetatable(obj, self)
	self.__index = self

	return obj
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

--- Preview with Glow.nvim
function Note:preview()
	if vim.fn.executable("glow") == 0 and package.loaded["glow"] == nil then
		vim.notify("Glow is not installed")
		return
	end
	vim.cmd("Glow " .. self.path)
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

---Fetch frontmatter from the specified path.
---@param path string? - The path to the note to fetch frontmatter from.
---@param content string|function? - The content of the note.
---@return table?
function Note:frontmatter(path, content)
	path = path or self.path
	content = content or (type(self.content) == "function" and self:content()) or self.content
	if content == nil then
		return
	end
	local frontmatter = content:match([[^%s*(%-%-%-.*%-%-%-)%s*.*]])
	return frontmatter
end

---Fetch body from the specified path.
---@param path string? - The path to the note to fetch body from.
---@param content string|function? - The content of the note.
---@return string
function Note:body(path, content, frontmatter)
	path = path or self.path
	content = content or (type(self.content) == "function" and self:content()) or self.content
	if frontmatter == nil then
		if self.frontmatter == nil or type(self.frontmatter) == "function" then
			frontmatter = self:frontmatter(path, content)
		else
			frontmatter = self.frontmatter
		end
	end

	if frontmatter == nil then
		if type(content) == "string" then
			return content
		end
	end

	return content:sub(frontmatter:len() + 1)
end

---Fetch class from the specified path.
---@param path string? - The {absolute} path to the note to fetch class from.
---@param content string|function? - The content of the note.
---@return string
function Note:title(path, content)
	path = path or self.path
	content = content or (type(self.content) == "function" and self:content()) or self.content

	local title
	for line in content:gmatch("([^\n]*)\n?") do
		if line:sub(1, 1) == "#" then
			title = line:sub(3)
			break
		end
	end
	return title
end

---@param path string?
---@param body string|function?
---@return table --
function Note:tags(path, body)
	path = path or self.path
	body = body or (type(self.body) == "function" and self:body()) or self.body

	local Tag = require("vault.tags.tag")
	local tags = {}
	for match in body:gmatch([[#([A-Za-z0-9_][A-Za-z0-9-_/]+)]]) do
		local tag = Tag:new({
			value = match,
			notes_paths = { path },
		})
		table.insert(tags, tag)
	end
	return tags
end

---Check if note has an exact tag value.
---@param tag_value string - Exact tag value to search for.
function Note:has_tag(tag_value, body)
	body = body or (type(self.body) == "function" and self:body()) or self.body
	local pattern = config.search_pattern.tag
	if body:match(pattern) ~= nil then
		return true
	end
	return false
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
---Fetch mapview like keys from the specified path.
---@param path string?
---@return string[]?
function Note:keys(path, content)
	path = path or self.path
	content = content or self.content or self:content(path)
	if type(content) ~= "string" then
		return
	end

	local keys = {}
	local block_field_pattern = "([A-Za-z%-%_]+)::%s*%w+"
	local inline_field_pattern = "([A-Za-z%-%_]+)::%s*%w+"
	local frontmatter_key_pattern = "([A-Za-z%-%_]+):%s*%w+"

	local patterns = {
		block_field_pattern,
		inline_field_pattern,
		frontmatter_key_pattern,
	}

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

	local frontmatter = self.frontmatter or self:frontmatter()
  for key in frontmatter:gmatch(frontmatter_key_pattern) do
    if key ~= nil then
      keys[key] = {1, 1}
    end
  end

  local body = self.body or self:body()
  for key in body:gmatch(block_field_pattern) do
    if key ~= nil then
      keys[key] = {1, 1}
    end
  end

	return keys
end

---Fetch class from the specified path.
---@param content string - The content of the note.
---@return string?
function Note:class(content)
  content = content or (type(self.content) == "function" and self:content()) or self.content
	local class
	local pattern = config.search_pattern.class or "%s#class/([A-Za-z0-9_-]+)"
	local match = content:match(pattern)
	if match ~= nil then
		class = match
	end
	return class
end

function Note.test()
	vim.cmd("lua package.loaded['vault.notes.note'] = nil")
	local raw_content = string.gsub(
		[[
---
uuid: a2b3c4d5b6a7c8d9c0b1a2b3c4d5b6a7
title: Foo
created: 2021-01-01 00:00:00
modified: 2021-01-01 00:00:00
---
# Foo

class:: #class/Meta
tags:: #tag/foo, #tag/bar, #baz, #qux

inline:: 1
block:: 2 and online:: 4

Lorem ipsum dolor sit amet, consectetur adipiscing elit.
Donec a diam lectus. Sed sit amet ipsum mauris. Maecenas
congue ligula ac quam viverra nec consectetur ante hendrerit.
Donec et mollis dolor.
Praesent et diam eget libero egestas mattis sit amet vitae augue.

## Bar

Integer congue faucibus dapibus. Integer id nisl ut elit
]],
		"\n",
		"\\n"
	)

	local note = Note:new({
		path = os.getenv("HOME") .. "/knowledge/Practice/Play Guitar.md",
	})
  print(vim.inspect(note:keys()))
	-- local frontmatter = note.frontmatter or note:frontmatter()
 --  print("frontmatter:", vim.inspect(frontmatter))
	--
	-- local body = note:body()

	-- print("path: " .. note.path)
	-- print("relpath: " .. note.relpath)
	-- -- print("content: " .. note.content)
	-- print("basename: " .. note.basename)
	-- print("title: " .. note:title())
 --  print("has_tag:", note:has_tag("View"))
	--
	-- -- print("body: " .. body)
 --  print("outlinks:", vim.inspect(note:outlinks()))
end

return Note
