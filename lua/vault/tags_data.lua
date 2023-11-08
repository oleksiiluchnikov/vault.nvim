local config = require("vault.config")
local Job = require("plenary.job")
local Tag = require("vault.tag")
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
---@param filter_opts? FilterOptions? - Filter options for tags.
---@return table<string, string[]> - Table of tag values and their notes paths. E.g., { ["status"] = { "foo.md", "bar.md" } }
function TagsData:fetch(filter_opts)
  local TagsDataFilterOptions = require("vault.filter_options.tags_data")
  filter_opts = TagsDataFilterOptions:new(filter_opts) or nil
  if filter_opts then
    if #filter_opts.include == 0 and #filter_opts.exclude == 0 then
      filter_opts = nil
    end
  end

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

  local should_be_included = false
  local should_be_ignored = false
  local path_to_be_excluded = {}

  ---@param line string - The line to parse.
  ---@return table<string, string[]>? - Table of tag values and their notes paths. E.g., { ["status"] = { "foo.md", "bar.md" } }
  local function parse_line_for_tags(line)
    local tags_data_from_line = {}
    local path, line_with_tag = line:match("^(.*" .. config.ext .. "):(.+)")
    if path == nil or line_with_tag == nil then
      return
    end

    for tag_value in line:gmatch("#([A-Za-z0-9_][A-Za-z0-9-_/]+)") do
      if require('vault.tag').is_tag(tag_value) == false then
        goto continue
      end

      if tags_data_from_line[tag_value] == nil then
        tags_data_from_line[tag_value] = {}
      end

      if not vim.tbl_contains(tags_data_from_line[tag_value], path) then
        vim.list_extend(tags_data_from_line[tag_value], { path })
      end

      ::continue::
    end
    return tags_data_from_line
  end

  local tags_data = {}
  for _, line in pairs(stdout) do
    if Tag.is_tag_context(line) == false then
      goto continue
    end
    ---@type table<string, string[]>? - Table of tag values and their notes paths. E.g., { ["status"] = { "foo.md", "bar.md" } }
    local tags_data_from_line = parse_line_for_tags(line)

    if tags_data_from_line == nil or vim.tbl_isempty(tags_data_from_line) then
      goto continue
    end

    for tag_value, notes_paths_from_line in pairs(tags_data_from_line) do
      if tags_data[tag_value] == nil then
        tags_data[tag_value] = {}
      end
      for _, path in pairs(notes_paths_from_line) do
        if not vim.tbl_contains(tags_data[tag_value], path) then
          vim.list_extend(tags_data[tag_value], { path })
        end
      end
    end
  ::continue::
  end

  if not filter_opts or vim.tbl_isempty(filter_opts) or (#filter_opts.include == 0 and #filter_opts.exclude == 0) then
    self.data = tags_data
    return self
  end
  local ignored_paths = {}

  local ignored_values = {}
  for tag_value, notes_paths in pairs(tags_data) do
    for _, path in pairs(notes_paths) do

      if #filter_opts.include > 0 then
        for _, query in ipairs(filter_opts.include) do
          if FilterOptions.has_match(tag_value, query, filter_opts.match_opt) == false then
          --   if tags_data[tag_value] == nil then
          --     tags_data[tag_value] = {}
          --   end
          --   for _, path in pairs(notes_paths) do
          --     if not vim.tbl_contains(tags_data[tag_value], path) then
          --       vim.list_extend(tags_data[tag_value], { path })
          --     end
          --   end
          -- else
            if tags_data[tag_value] then
              tags_data[tag_value] = nil
            end
          end
        end
      end

      if #filter_opts.exclude > 0 then
        for _, query in ipairs(filter_opts.exclude) do
          if FilterOptions.has_match(tag_value, query, filter_opts.match_opt) == true then
            ignored_paths[path] = true
            if tags_data[tag_value] then
              tags_data[tag_value] = nil
              ignored_values[tag_value] = true
            end
          end
        end
      end

    end
  end


  self.data = tags_data
  return self
end

---TagsData into Tags
---@param filter_opts TagsDataFilterOptions? - Filter options for tags.
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

TagsData._test = function()
  vim.cmd("lua package.loaded['vault'] = nil")
  vim.cmd("lua require('vault').setup()")
  vim.cmd("lua package.loaded['vault.tags_data'] = nil")
  local tags_data = TagsData:new()
  local include_only = tags_data:fetch({{'class'},{}, 'startswith', 'all'})
  print("INCLUDE ONLY:" .. vim.inspect(vim.tbl_keys(include_only.data)))
  local exclude_only = tags_data:fetch({{},{'class'}, 'startswith', 'all'})
  print("EXCLUDE ONLY:" .. vim.inspect(vim.tbl_keys(exclude_only.data)))
  assert(vim.tbl_keys(include_only.data) ~= vim.tbl_keys(exclude_only.data))
  local exclude_and_include = tags_data:fetch({{'status'},{'status/TODO'}, 'startswith', 'all'})
  print("EXCLUDE AND INCLUDE:" .. vim.inspect(vim.tbl_keys(exclude_and_include.data)))
end


return TagsData
