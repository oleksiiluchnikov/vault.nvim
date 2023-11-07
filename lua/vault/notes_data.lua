local config = require("vault.config")
local Utils = require("vault.utils")
local TagsValues = require("vault.tags_data")

---NotesValues
---@class NotesData
---@field data table<string, string[]> - Table of note paths and their tags values. E.g., { ["foo.md"] = { "status/TODO", "class/CS" } }
---@field fetch function - Fetch notes paths from vault.
---@field to_notes function - NotesValues into Notes.
local NotesData = {}

---Create a new NotesValues object.
---@param this? table - The table to create the NotesValues object from.
---@return NotesData
function NotesData:new(this)
  this = this or {}
  setmetatable(this, self)
  self.__index = self
  return this
end

---Retrieve all notes paths from your vault.
function NotesData:fetch()
  local FilterOptions = require("vault.filter_options")

  local paths = vim.fn.globpath(config.dirs.root, "**/*" .. config.ext, true, true)

  local notes_data = {}
  local existing_notes = {}
  for _, path in ipairs(paths) do

    -- Skip if note already exists in notes
    if existing_notes[path] then
      goto continue
    end

    -- Skip if note does not match config.ignore
    for _, ignore_pattern in ipairs(config.ignore) do
      if path:match(ignore_pattern) then
        goto continue
      end
    end

    local basename = vim.fn.fnamemodify(path, ":t:r")
    local relpath = Utils.to_relpath(path)


    if notes_data[basename] == nil then
      notes_data[basename] = {}
    end

    notes_data[basename].path = path
    notes_data[basename].relpath = relpath
    -- notes_values[basename].tags_values = {}
    --
    -- local tags_values = TagsValues:new():fetch()
    -- for tag_value, note_path in pairs(tags_values) do
    --   if FilterOptions.has_match(note_path, path, "exact") then
    --     table.insert(notes_values[basename].tags_values, tag_value)
    --   end
    -- end

    existing_notes[path] = true
    ::continue::
  end
  self.data = notes_data
  return self
end

---NotesValues into Notes
---@param filter_opts FilterOptions? - Filter options for notes.
---@return Notes - Notes object.
function NotesData:to_notes(filter_opts)
  local FilterOptions = require("vault.filter_options")
  filter_opts = filter_opts or FilterOptions:new()
  if not filter_opts then
    self.data = self.data or self:fetch(filter_opts)
  end

  local notes_data = {}
  for note_data, _ in pairs(self.data) do
    local should_include = false
    local should_exclude = false

    for _, query in ipairs(filter_opts.include) do
      if FilterOptions.has_match(note_data, query, filter_opts.match_opt) then
        should_include = true
        break
      end
    end

    for _, query in ipairs(filter_opts.exclude) do
      if FilterOptions.has_match(note_data, query, filter_opts.match_opt) then
        should_exclude = true
        break
      end
    end

    if should_include and not should_exclude then
      table.insert(notes_data, require("vault.note"):new(self.data[note_data]))
    elseif #filter_opts.include == 0 and #filter_opts.exclude == 0 then
      table.insert(notes_data, require("vault.note"):new(self.data[note_data]))
    end
  end
  return notes_data
end

local function test()
  local notes_values = NotesData:new()
  local notes = notes_values:to_notes()
  print(vim.inspect(notes))
end


return NotesData
