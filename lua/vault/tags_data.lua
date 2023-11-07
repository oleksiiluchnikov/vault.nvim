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
---@return table<string, string[]> - Table of tag values and their notes paths. E.g., { ["status"] = { "foo.md", "bar.md" } }
function TagsData:fetch()
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
    ---@type string[]?
    local tags_values_from_line = Utils.parse_line_for_tags(line, tags_data)
    if tags_values_from_line == nil then
      goto continue
    end
    ::continue::
  end
  self.data = tags_data
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
    local should_include = false
    local should_exclude = false

    for _, query in ipairs(filter_opts.include) do
      if FilterOptions.has_match(tag_value, query, filter_opts.match_opt) then
        should_include = true
        break
      end
    end

    for _, query in ipairs(filter_opts.exclude) do
      if FilterOptions.has_match(tag_value, query, filter_opts.match_opt) then
        should_exclude = true
        break
      end
    end

    if should_include and not should_exclude then
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
