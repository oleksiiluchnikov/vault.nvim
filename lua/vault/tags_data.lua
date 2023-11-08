local config = require("vault.config")
local Job = require("plenary.job")
local Tag = require("vault.tag")
local Utils = require("vault.utils")
local FilterOptions = require("vault.filter_options")

---Tags values. Object to hold tags values and their notes paths. E.g., { ["status"] = { "foo.md", "bar.md" } }
---@class TagsData
---@field data table<string, string[]> - Table of tag values and their notes paths. E.g., { ["status"] = { "foo.md", "bar.md" } }
---@field fetch function - Fetch tags values from vault.
---@field to_tags function - TagsData into Tags.
local TagsData = {}

---Create a new TagsData object.
---@param this? table - The table to create the TagsData object from.
---@return TagsData
function TagsData:new(this)
  this = this or {}
  setmetatable(this, self)
  self.__index = self
  return this
end

---Retrieve all tags values from your vault.
---@param filter_opts? TagsFilterOptions? - Filter options for tags.
---@return table<string, string[]> - Table of tag values and their notes paths. E.g., { ["status"] = { "foo.md", "bar.md" } }
function TagsData:fetch(filter_opts)
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


  if stdout == nil then
    error("rg failed to run")
    return {}
  end

  local tags_data = {}
  for _, line in pairs(stdout) do
    if Tag.is_tag_context(line) == false then
      goto continue
    end
    ---@type table<string, string[]>? - Table of tag values and their notes paths. E.g., { ["status"] = { "foo.md", "bar.md" } }
    local tags_data_from_line = Utils.parse_line_for_tags(line)
    if tags_data_from_line == nil or vim.tbl_isempty(tags_data_from_line) then
      goto continue
    end

    for tag_value, notes_paths_from_line in pairs(tags_data_from_line) do
      for _, note_path_from_line in pairs(notes_paths_from_line) do
        if tags_data[tag_value] == nil then
          tags_data[tag_value] = { note_path_from_line }
        elseif not vim.tbl_contains(tags_data[tag_value], note_path_from_line) then
          -- extend value table if it already exists
          vim.list_extend(tags_data[tag_value], notes_paths_from_line)
        end
      end
    end
  ::continue::
  end
  if not filter_opts or vim.tbl_isempty(filter_opts) or (#filter_opts.include == 0 and #filter_opts.exclude == 0) then
    self.data = tags_data
    return self
  end

  
  local tags_data_filtered = {}
  local paths_to_include = {}
  local paths_to_ignore = {}
  for tag_value, notes_paths in pairs(tags_data) do
    local include_value = false
    local ignore_value = false

    if #filter_opts.include > 0 then
      for _, query in ipairs(filter_opts.include) do
        if FilterOptions.has_match(tag_value, query, filter_opts.match_opt) == true then
          include_value = true
          vim.list_extend(paths_to_include, notes_paths)
        end
      end
    end

    if #filter_opts.exclude > 0 then
      for _, query in ipairs(filter_opts.exclude) do
        if FilterOptions.has_match(tag_value, query, filter_opts.match_opt) == true then
          tags_data[tag_value] = nil
          vim.list_extend(paths_to_ignore, notes_paths)
        end
      end
    end
    -- end

    if #paths_to_include > 0 and #paths_to_ignore > 0 then
      local seen_paths = {}
      local seen_tag_value = {}
      -- for tag_value, notes_paths in pairs(tags_data) do
      for i, note_path in ipairs(notes_paths) do
        for _, ignore_path in pairs(paths_to_ignore) do
          if note_path == ignore_path then
            tags_data[tag_value] = nil
          end
        end
      end
      if not seen_tag_value[tag_value] then
        tags_data_filtered[tag_value] = paths_to_include
      end
    end
    if (#paths_to_include == 0 or vim.tbl_isempty(paths_to_include)) and #paths_to_ignore > 0 then
      -- for tag_value, notes_paths in pairs(tags_data) do
      for i, note_path in ipairs(notes_paths) do
        for _, ignore_path in pairs(paths_to_ignore) do
          if note_path ~= ignore_path then
            table.insert(paths_to_include, note_path)
          end
        end
        if #notes_paths > 0 then
          tags_data_filtered[tag_value] = notes_paths
        end
      end
      paths_to_ignore = {}
    end
    if #paths_to_include > 0 and (#paths_to_ignore == 0 or vim.tbl_isempty(paths_to_ignore)) then
      local seen_paths = {}
      local seen_tag_value = {}
      -- for tag_value, notes_paths in pairs(tags_data) do
      for i, note_path in ipairs(notes_paths) do
        for _, include_path in pairs(paths_to_include) do
          if not seen_paths[note_path] then
            if note_path == include_path then
              -- print("include_path: " .. vim.inspect(include_path))
              table.insert(paths_to_include, note_path)
            else
              if not seen_paths[note_path] then
                table.remove(notes_paths, i)
              end
            end
            seen_paths[note_path] = true
          end
        end
      end
      if not seen_tag_value[tag_value] then
        tags_data_filtered[tag_value] = paths_to_include
      end
    end

  end
  if #paths_to_include == 0 and #paths_to_ignore == 0 then
    tags_data_filtered = tags_data
  end

  self.data = tags_data_filtered
  return self
end

---TagsData into Tags
---@param filter_opts TagsFilterOptions? - Filter options for tags.
---@return Tags - Tags object.
function TagsData:to_tags(filter_opts)
  local Tags = require("vault.tags")

  -- if filter_opts then
  --   self.data = self:fetch(filter_opts)
  -- else
  filter_opts = filter_opts or FilterOptions:new()
  -- end

  local tags_data = {}
  for tag_value, tag_data in pairs(self.data) do
    local is_match = false
    local is_ignored = false

    for _, query in ipairs(filter_opts.include) do
      if FilterOptions.has_match(tag_value, query, filter_opts.match_opt) then
        is_match = true
        break
      end
    end

    for _, query in ipairs(filter_opts.exclude) do
      if FilterOptions.has_match(tag_value, query, filter_opts.match_opt) then
        is_ignored = true
        break
      end
    end

    if is_match and not is_ignored then
      tags_data[tag_value] = Tag:new({
        value = tag_value,
        notes_paths = tag_data,
      })
    elseif #filter_opts.include == 0 and #filter_opts.exclude == 0 then
      tags_data[tag_value] = Tag:new({
        value = tag_value,
        notes_paths = tag_data,
      })
    end
  end
  return Tags:new(tags_data)
end

return TagsData
