local Job = require("plenary.job")
local Tag = require("vault.tag")

---@class Vault
---@field notes function|Note[]
---@field tags Tag[]
---@field setup function
local Vault = {}

---Create a new Vault object.
---@return Vault
function Vault:new()
  local o = {
  }
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
---@return table|nil - The table with the tags.
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
  Job:new({
    command = "find",
    args = {
      ".",
      "-type",
      "f",
      "-name",
      "*" .. config.ext,
      "-not",
      "-path",
      "*/\\.[^_]*",
    },
    cwd = config.dirs.root,
    on_exit = function(j, return_val)
      if return_val ~= 0 then
        return
      end
      local stdout = j:result()
      for _, path in ipairs(stdout) do
        local relpath = path.sub(path, 3)
        local note = require("vault.note"):new({
          path = config.dirs.root .. "/" .. relpath,
          relpath = relpath
        })
        table.insert(notes, note)
      end
    end
  }):sync()

  return notes
end

--- Retrieve tags from your vault.
---@param tag_prefix string|nil - Prefix to filter tags (optional).
---@return Tag[] - Array of Tag objects.
function Vault.get_tags(tag_prefix)
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
      if tag_value:sub(1, #tag_prefix) ~= tag_prefix then
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
