local Object = require("nui.object")

local config = require("vault.config")

local Note = require("vault.notes.note")
local Tags = require("vault.tags")
local FilterOpts = require("vault.filter_opts")
local NotesFilterOpts = require("vault.notes.filter_opts")


---@class VaultNotes - Retrieve notes from vault.
---@field map table<string, VaultNote> - The map of notes.
---@field list VaultNote[] - The list of notes.
---@field average_content_length number - The average content length of notes.
local Notes = Object("VaultNotes")

---Create a new Notes object.
---@param filter_opts table|VaultNotesFilterOpts? -- Optional: The filter options to use.
function Notes:init(filter_opts)
  ---@type table<string, VaultNote>
  self.map = {}
  ---@type table<integer, string> - List of paths to notes.
  local paths = vim.fn.globpath(config.dirs.root, "**/*" .. config.ext, true, true)

  if filter_opts then
    paths = self:filter(paths, filter_opts)
  end

  paths = vim.tbl_flatten(paths)

  local ignore_patterns = config.ignore

  ---@type table<string, boolean>
  local seen_paths = {}
  for _, path in ipairs(paths) do
    for _, ignore_pattern in ipairs(ignore_patterns) do
      if string.match(path, ignore_pattern) then
        goto continue
      end
    end

    if seen_paths[path] then
      goto continue
    end

    self:add_note(
      Note(path)
    )
    seen_paths[path] = true
    ::continue::
  end
end

---@param note VaultNote - The note to add.
function Notes:add_note(note)

  if not note then
    error("`note` argument is required.")
  end

  local relpath = note.data.relpath
  if not relpath then
    error("`note.data.relpath` is not set: " .. vim.inspect(note))
  end

  if self.map[relpath] then
    error("Note already exists: " .. vim.inspect(self.map[relpath]) .. " compared to " .. vim.inspect(note))
  end

  note.data.relpath = relpath

  self.map[relpath] = note
end

function Notes:__index(key)
  if type(key) == "number" then
    ---@type VaultNote
    return self.map[key]
  end

  if key == "list" then
    ---@type VaultNote[]
    local list = vim.tbl_values(self.map)
    return list

  elseif key == "average_content_length" then
    local total_content_length = 0
    for _, note in pairs(self.map) do
      local note_content_length = #note.data.content or 0
      total_content_length = total_content_length + note_content_length
    end
    return total_content_length /  self:__len()
  else
    return rawget(self, key)
  end
end

function Notes:random()
  local random_index = math.random(self:__len())
  return self.map[random_index]
end

---Get length of notes.
---@return number
function Notes:__len()
  return vim.tbl_count(self.map)
end

---Filter notes paths.
---@param paths table<integer, string> - List of paths to notes.
---@param filter_opts VaultNotesFilterOpts - The filter options.
---@return table<integer, string> - List of paths to notes.
function Notes:filter(paths, filter_opts)
  if not paths then
    error("`paths` argument is required.")
  end

  if not filter_opts then
    error("`filter_opts` argument is required.")
  end

  local notes_filter_opts = NotesFilterOpts(filter_opts)

  local filter_by = notes_filter_opts.by
  if type(filter_by) == "string" then
    filter_by = { filter_by }
  end

  for _, key in ipairs(filter_by) do
    if key == "tags" then
      local is_exclude_only = false

      local note_filter_opts_tbl_copy = vim.deepcopy(notes_filter_opts)
      note_filter_opts_tbl_copy.by = nil

      local tags_filter_opts_tbl = note_filter_opts_tbl_copy
      if #notes_filter_opts.include == 0 and #notes_filter_opts.exclude > 0 then
        tags_filter_opts_tbl.include = notes_filter_opts.exclude
        tags_filter_opts_tbl.exclude = {}
        is_exclude_only = true
      end

      local tags_filter_opts = FilterOpts(tags_filter_opts_tbl)

      ---@type VaultTags
      local tags = Tags(tags_filter_opts)
      if is_exclude_only then
        -- local notes_paths_to_exclude = tags:by("notes_paths")
        local notes_paths_to_exclude = vim.tbl_flatten(tags:values_by_key("notes_paths"))
        paths = vim.tbl_filter(function(path)
          for _, note_path in ipairs(notes_paths_to_exclude) do
            if path == note_path then
              return false
            end
          end
          return true
        end, paths)
      else
        paths = tags:values_by_key("notes_paths")
      end
    elseif "basename" then
      paths = vim.tbl_filter(function(path)
        path = path:lower()
        local path_basename = vim.fn.fnamemodify(path, ":t")
        local is_exclude_only = false
        if next(notes_filter_opts.include) == nil and next(notes_filter_opts.exclude) ~= nil then
          is_exclude_only = true
        end
        if is_exclude_only then
          return not vim.tbl_contains(notes_filter_opts.exclude, path_basename)
        else
          return vim.tbl_contains(notes_filter_opts.include, path_basename)
        end
      end, paths)
    end
  end

  return paths
end

---Get map of the duplicated notes.
---@return table<string, table<string, string>> - The list of tables with duplicate pathes
function Notes:duplicates()
  local duplicates = {}
  local notes_with_count = {}
  for _, note in pairs(self.map) do
    if not notes_with_count[note.data.basename] then
      notes_with_count[note.data.basename] = {}
    end
    table.insert(notes_with_count[note.data.basename], note.data.path)

    if #notes_with_count[note.data.basename] > 1 then
      duplicates[note.data.basename] = notes_with_count[note.data.basename]
    end
  end
  return duplicates
end

---Get list of notes by key.
---@param key string - The key to search by.
---| "basename" - The basename of the note.data. (e.g. "note.md")
---| "title" - The title of the note. (e.g. "Note")
---@param value string - The value to search by.
---@param match_opt string? - The match option to use.
---| "exact" - Match the exact value.
---| "startswith" - Match the value if it starts with the value.
---| "contains" - Match the value if it contains the value.
---@return VaultNote[]
function Notes:by(key, value, match_opt, list)
  if not key then
    error("`key` argument is required.")
  end
  key = key:lower()
  if not value then
    error("`value` argument is required.")
  end
  value = value:lower()
  match_opt = match_opt or "exact"

  ---@type VaultNote[]
  list = list or self.map

  for _, note in pairs(list) do
    if note.data[key] then
      if type(note.data[key]) ~= "string" then
        goto continue
      end
      local note_value = note.data[key]:lower()
      if match_opt == "exact" then
        if note_value == value then
          table.insert(list, note)
        end
      elseif match_opt == "startswith" then
        if note_value:find("^" .. value) then
          table.insert(list, note)
        end
      elseif match_opt == "contains" then
        if note_value:find(".*" .. value .. ".*") then
          table.insert(list, note)
        end
      else
        error("Invalid `match_opt` argument: " .. vim.inspect(match_opt))
      end
    end
    ::continue::
  end
  return list
end

---Get list of notes values by key.
---@param key string - The key to get the list of notes by.
---@return table - The liso of values.
function Notes:values_by_key(key)
  if not key then
    error("`key` argument is required.")
  end

  local values = {}
  for _, note in pairs(self.map) do
    if note.data[key] then
      table.insert(values, note.data[key])
    end
  end
  return values
end

---Check if note exists.
---@param key string - The key to search by.
---| "basename" - The basename of the note. (e.g. "note.md")
---| "title" - The title of the note. (e.g. "Note")
---@param value string - The value to search by.
---@param match_opt string? - The match option to use.
---| "exact" - Match the exact value.
---| "startswith" - Match the value if it starts with the value.
---| "contains" - Match the value if it contains the value.
---@return boolean
function Notes:has_note(key, value, match_opt)
  if not key then
    error("`key` argument is required.")
  end

  if not value then
    error("`value` argument is required.")
  end

  key = key:lower()
  value = value:lower()
  match_opt = match_opt or "exact"

  for _, note in pairs(self.map) do
    local data = note.data
    if data[key] then
      if type(data[key]) ~= "string" then
        goto continue
      end
      local note_data_value = data[key]:lower()
      if match_opt == "exact" then
        if note_data_value == value then
          return true
        end
      elseif match_opt == "startswith" then
        if note_data_value:find("^" .. value) then
          return true
        end
      elseif match_opt == "contains" then
        if note_data_value:find(".*" .. value .. ".*") then
          return true
        end
      else
        error("Invalid `match_opt` argument: " .. vim.inspect(match_opt))
      end
    end
    ::continue::
  end
  return false
end

---Get list of notes where title not matches basename.
---@return VaultNote[]
---@see Notes:by
---@see Notes:values_by_key
function Notes:list_with_mismatched_title_and_basename()
  local notes_list = self.map
  local notes_with_different_title = {}
  for _, note in pairs(notes_list) do
    if note.data.title .. config.ext ~= note.data.basename then
      local compared_note = {
        title = note.data.title,
        basename = note.data.basename:gsub(config.ext .. "$", ""),
      }
      table.insert(notes_with_different_title, compared_note)
    end
  end
  return notes_with_different_title
end

---@alias VaultNotes.constructor fun(filter_opts: VaultNotesFilterOpts?): VaultNotes
---@type VaultNotes|VaultNotes.constructor
local VaultNotes = Notes

-- print(vim.inspect(VaultNotes():values_by_key("basename")))

return VaultNotes
