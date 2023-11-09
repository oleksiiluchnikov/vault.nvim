local config = require("vault.config")
local Utils = require("vault.utils")
local TagsMap = require("vault.tags.map")

---@class NotesMap
local NotesMap = {}

---@return NotesMap
function NotesMap:new()
  local this = {}
  setmetatable(this, self)
  self.__index = self
  return this
end

---Retrieve all notes paths from your vault.
---@param filter_opts? NotesFilterOpts? - Filter options for notes.
function NotesMap:fetch(filter_opts)
  local paths = vim.fn.globpath(config.dirs.root, "**/*" .. config.ext, true, true)

  local notes_map = {}
  local seen_notes = {}

  if filter_opts and #filter_opts > 0 then
    local Filter = require("vault.filter")
    -- local FilterOpts = Filter:new(filter_opts).opts
    filter_opts = Filter:new(filter_opts).opts.notes
    for _, key in ipairs(filter_opts.keys) do
      if key == "tags" then

        local is_exclude_only = false

        if #filter_opts.include == 0 and #filter_opts.exclude > 0 then
          filter_opts.include = filter_opts.exclude
          filter_opts.exclude = {}
          is_exclude_only = true
        end

        local tags_filter_opts = Filter:new(filter_opts).opts.tags

        local tags_map = TagsMap:new():fetch(tags_filter_opts)
        if is_exclude_only then
          local paths_to_remove = vim.tbl_flatten(vim.tbl_values(tags_map))
          paths = vim.tbl_filter(function(path)
            return not vim.tbl_contains(paths_to_remove, path)
          end, paths)
        else
         paths = vim.tbl_flatten(vim.tbl_values(tags_map))
        end
      end
    end
  end

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

    local note_map ={
      path = path,
      relpath = relpath,
      basename = basename,
    }

    if notes_map[path] == nil then
      notes_map[path] = note_map
    end

    seen_notes[path] = true
    ::continue::
  end

  return setmetatable(notes_map, self)
end

---NotesValues into Notes.
---@return Notes - Notes object.
function NotesMap:to_notes()
  local Notes = require("vault.notes")
  local notes = Notes:new(self)
  return notes
end

NotesMap._test = function()
  vim.cmd("lua package.loaded['vault'] = nil")
  vim.cmd("lua require('vault').setup()")
  vim.cmd("lua package.loaded['vault.tags.map'] = nil")
  vim.cmd("lua package.loaded['vault.notes.map'] = nil")
  local notes_map = NotesMap:new()
  local notes_with_tags_included = notes_map:fetch({{'tags'},{'class'},{}, 'startswith', 'all'})
  print("NOTES with INCLUDED:" .. vim.inspect(#vim.tbl_keys(notes_with_tags_included) .. "\n"))
  local notes_with_tags_excluded = notes_map:fetch({{'tags'},{},{'class'}, 'startswith', 'all'})
  print("NOTES with EXCLUDED:" .. vim.inspect(#vim.tbl_keys(notes_with_tags_excluded) .. "\n"))
  local notes_with_tags_included_and_excluded = notes_map:fetch({{'tags'},{'status'},{'class'}, 'startswith', 'all'})
  print("NOTES with INCLUDED AND EXCLUDED:" .. vim.inspect(#vim.tbl_keys(notes_with_tags_included_and_excluded) .. "\n"))

end

return NotesMap
