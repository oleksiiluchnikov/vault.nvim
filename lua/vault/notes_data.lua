local config = require("vault.config")
local Log = require("plenary.log")
local Utils = require("vault.utils")
local TagsData = require("vault.tags_data")

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

---@class NotesDataFilterOptions: FilterOptions -- Filter options for notes.
---@field keys string[]|string - Array of keys to filter notes.
---| '"tags"' # Filter notes by tags.
---| '"title"' # Filter notes by title.
---@field include string[] - Array of queries to include notes.
---@field exclude string[] - Array of queries to exclude notes.
---@field match_opt string - Match option for queries.
---| '"exact"' # Match queries exactly.
---| '"contains"' # Match queries that contain.
---| '"startswith"' # Match queries that start with.
---| '"endswith"' # Match queries that end with.
---| '"regex"' # Match queries with regex.
---| '"fuzzy"' # Match queries fuzzily.
---@field mode string - Mode for queries.
local NotesDataFilterOptions = {}

function NotesDataFilterOptions:new(this)
  this = this or {}
  print(vim.inspect(this))
  if type(this[1]) == "string" then
    this.keys = { this[1] }
  else
    this.keys = this[1] or {}
  end
  this.include = this[2] or {}
  this.exclude = this[3] or {}
  this.match_opt = this[4] or "exact"
  this.mode = this[5] or "all"
  -- validate
  setmetatable(this, self)
  self.__index = self
  this:validate()
  return this
end

function NotesDataFilterOptions:validate()
  local valid_keys = { "tags", "title", "body" }
  local valid_match_opts = { "exact", "contains", "startswith", "endswith", "regex", "fuzzy" }
  local valid_modes = { "all", "any" }
    ---@type string[]|string
    local keys = self.keys
    if type(keys) ~= "string" then
      for _, key in ipairs(keys) do
        if not vim.tbl_contains(valid_keys, key) then
          error("invalid key: `" .. key .. "` not in " .. vim.inspect(valid_keys))
        end
      end
    end
  if not vim.tbl_contains(valid_match_opts, self.match_opt) then
    error("invalid match_opt: `" .. self.match_opt .. "` not in " .. vim.inspect(valid_match_opts))
  end
  if not vim.tbl_contains(valid_modes, self.mode) then
    error("invalid mode: `" .. self.mode .. "` not in " .. vim.inspect(valid_modes))
  end
end

---Retrieve all notes paths from your vault.
---@param filter_opts? NotesDataFilterOptions? - Filter options for notes.
function NotesData:fetch(filter_opts)
  local FilterOptions = require("vault.filter_options")
  local paths = vim.fn.globpath(config.dirs.root, "**/*" .. config.ext, true, true)

  local notes_data = {}
  local seen_notes = {}
  for _, path in ipairs(paths) do

    if seen_notes[path] then
      goto continue
    end

    for _, ignore_pattern in ipairs(config.ignore) do
      if path:match(ignore_pattern) then
        goto continue
      end
    end

    local basename = vim.fn.fnamemodify(path, ":t")
    local relpath = Utils.to_relpath(path)

    local note_data ={
      path = path,
      relpath = relpath,
      basename = basename,
    }

    if notes_data[path] == nil then
      notes_data[path] = note_data
    end

    seen_notes[path] = true
    ::continue::
  end


  if not filter_opts or vim.tbl_isempty(filter_opts) then
    self.data = notes_data
    return self
  end


  filter_opts = NotesDataFilterOptions:new(filter_opts)
  if #filter_opts.include == 0 and #filter_opts.exclude == 0 then
    self.data = notes_data
    return self
  end
  local filtered_notes_data = {}
  local note_count_before = #vim.tbl_keys(notes_data)
  for _, key in ipairs(filter_opts.keys) do
    if key == "tags" then
      local tags_filter_opts = FilterOptions:new({
        include = filter_opts.include,
        exclude = filter_opts.exclude,
        match_opt = filter_opts.match_opt,
        mode = filter_opts.mode,
      })
      ---@type table<string, string[]>
      local tags_data = TagsData:new():fetch(tags_filter_opts).data
      if not tags_data or vim.tbl_isempty(tags_data) then
        error("no tags found:" .. vim.inspect(filter_opts))
      end
      for tag_value, tag_notes_paths in pairs(tags_data) do
        for _, note_path in ipairs(tag_notes_paths) do
          if not filtered_notes_data[note_path] then
            filtered_notes_data[note_path] = notes_data[note_path]
          end
        end
      end
    elseif key == "title" then
      error("not implemented")
    elseif key == "body" then
      error("not implemented")
    else
      error("invalid key")
    end
  end
  notes_data = filtered_notes_data
  local note_count_after = #vim.tbl_keys(notes_data)
  if note_count_before == note_count_after then
    error("Notes not filtered: " .. vim.inspect(filter_opts))
  end
  self.data = notes_data
  return self
end

---NotesValues into Notes.
---@return Notes - Notes object.
function NotesData:to_notes()
  local Notes = require("vault.notes")
  local notes = Notes:new(self.data)
  return notes
end

local function test()
  local notes_values = NotesData:new()
  local notes = notes_values:to_notes()
  print(vim.inspect(notes))
end


return NotesData
