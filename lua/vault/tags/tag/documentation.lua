local Job = require("plenary.job")
local config = require("vault.config")

---Tag documentation.
---A tag documentation is an object that represents a documentation file for a tag.
---@class TagDocumentation
---@field description string
---@field path string
---@field exists boolean
---@field content string|function
local TagDocumentation = {}

---@param tag_name string
---@return TagDocumentation
function TagDocumentation:new(tag_name)
  local doc_path = config.dirs.docs .. "/" .. tag_name .. config.ext
  local tag_documentation = {
    description = "",
    path = config.dirs.docs .. "/" .. tag_name .. config.ext,
    exists = vim.fn.filereadable(doc_path) == 1,
  }
  setmetatable(tag_documentation, self)
  self.__index = self
  return tag_documentation
end

function TagDocumentation:open()
	if self.exists then
		vim.cmd("edit " .. self.path)
	else
		TagDocumentation:write(self.path)
	end
end

function TagDocumentation:write(path)
  local root_dir = config.dirs.root
	local parent_dir = vim.fn.fnamemodify(path, ":h")
	Job:new({
		command = "mkdir",
		args = { "-p", parent_dir },
	}):sync()
	vim.cmd("edit " .. vim.fn.fnameescape(path))
	local current_bufnr = vim.api.nvim_get_current_buf()
	local is_empty = vim.api.nvim_buf_get_lines(current_bufnr, 0, -1, false)[1] == ""
	if not is_empty then
		return
	end
	---title should be last part of path without extension
	local title = vim.fn.fnamemodify(path, ":t:r")
	local content = "# " .. title .. "\n\n"
	content = content .. "class:: #class/Meta/Tag\n"
	local relpath = parent_dir:gsub(root_dir .. "/", "") -- e.g. docs/software/Blender or docs/software
	content = content .. "parent:: [[" .. relpath .. "]]\n"
	vim.api.nvim_buf_set_lines(current_bufnr, 0, -1, false, vim.split(content, "\n"))
	vim.cmd("write")
	vim.cmd("normal! Go")
end

---Fetch content of tag documentation.
---@param tag_name string
---@return string
function TagDocumentation:content(tag_name)
  local docs_dir = config.dirs.docs
  local path = docs_dir .. "/" .. tag_name .. ".md"
  local f = io.open(path, "r")
  if f == nil then
    return ""
  end
  local content = f:read("*all")
  f:close()
  return content
end

TagDocumentation.__call = function(self, tag_name)
  return TagDocumentation:new(tag_name)
end

TagDocumentation = setmetatable(TagDocumentation, TagDocumentation)

return function(tag_name)
  return TagDocumentation(tag_name)
end
