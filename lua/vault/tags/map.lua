local config = require("vault.config")
local Job = require("plenary.job")
local Tag = require("vault.tags.tag")


local function match(...)
  return require("vault.filter.match").opts.match(...)
end

---Tags values. Object to hold tags values and their notes paths. E.g., { ["status"] = { "foo.md", "bar.md" } }
---@class TagsMap
---@field map table<string, string[]> - Table of tag values and their notes paths. E.g., { ["status"] = { "foo.md", "bar.md" } }
---@field fetch function - Fetch tags values from vault.
---@field to_tags function - TagsMap into Tags.
local TagsMap = {}

---Create a new TagsMap object.
---@param this? table - The table to create the TagsMap object from.
---@return TagsMap
function TagsMap:new(this)
  this = this or {}
  setmetatable(this, self)
  self.__index = self
  return this
end


---Retrieve all tags values from your vault.
---@param filter_opts? TagsFilterOpts? - Filter options for tags.
---@return table<string, string[]> - Table of tag values and their notes paths. E.g., { ["status"] = { "foo.md", "bar.md" } }
function TagsMap:fetch(filter_opts)
  if filter_opts then
    if not filter_opts.include then
      filter_opts = require('vault.filter'):new(filter_opts).opts.tags
    end
  end
  local cmd = "rg" -- TODO: Make this configurable.
  local tag_pattern = [[#[A-Za-z0-9_][A-Za-z0-9-_/]+]] -- TODO: Make this configurable.
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
    cwd = root_dir,

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

  ---@param line string - The line to parse.
  ---@return table<string, string[]>? - Table of tag values and their notes paths. E.g., { ["status"] = { "foo.md", "bar.md" } }
  local function parse_line_for_tags(line)
    local tags_map_from_line = {}
    local path, line_with_tag = line:match("^(.*" .. config.ext .. "):(.+)")
    if path == nil or line_with_tag == nil then
      return
    end

    for tag_value in line:gmatch("#([A-Za-z0-9_][A-Za-z0-9-_/]+)") do
      if require('vault.tags.tag').is_tag(tag_value) == false then
        goto continue
      end

      if tags_map_from_line[tag_value] == nil then
        tags_map_from_line[tag_value] = {}
      end

      if not vim.tbl_contains(tags_map_from_line[tag_value], path) then
        vim.list_extend(tags_map_from_line[tag_value], { path })
      end

      ::continue::
    end
    return tags_map_from_line
  end

  local tags_map = {}
  for _, line in pairs(stdout) do
    if Tag.is_tag_context(line) == false then
      goto continue
    end
    ---@type table<string, string[]>? - Table of tag values and their notes paths. E.g., { ["status"] = { "foo.md", "bar.md" } }
    local tags_map_from_line = parse_line_for_tags(line)

    if tags_map_from_line == nil or vim.tbl_isempty(tags_map_from_line) then
      goto continue
    end

    for tag_value, notes_paths_from_line in pairs(tags_map_from_line) do
      if tags_map[tag_value] == nil then
        tags_map[tag_value] = {}
      end
      for _, path in pairs(notes_paths_from_line) do
        if not vim.tbl_contains(tags_map[tag_value], path) then
          vim.list_extend(tags_map[tag_value], { path })
        end
      end
    end
  ::continue::
  end

  if not filter_opts or vim.tbl_isempty(filter_opts) or (#filter_opts.include == 0 and #filter_opts.exclude == 0) then
    return setmetatable(tags_map, self)
  end



  -- for tag_value,_ in pairs(tags_map) do
  for _, tag_value in ipairs(vim.tbl_keys(tags_map)) do

      if #filter_opts.include > 0 then
        for _, query in ipairs(filter_opts.include) do
          if match(tag_value, query, filter_opts.match_opt) == false then
            if tags_map[tag_value] then
              tags_map[tag_value] = nil
            end
          end
        end
      end

      if #filter_opts.exclude > 0 then
        for _, query in ipairs(filter_opts.exclude) do
          if match(tag_value, query, filter_opts.match_opt) == true then
            if tags_map[tag_value] then
              tags_map[tag_value] = nil
            end
          end
        end
      end

  end


  return setmetatable(tags_map, self)
end

---TagsMap into Tags
---@param filter_opts TagsFilterOpts? - Filter options for tags.
---@return Tags - Tags object.
function TagsMap:to_tags(filter_opts)
  local Tags = require("vault.tags")
  if filter_opts then
    if not filter_opts.include then
      filter_opts = require('vault.filter'):new(filter_opts).opts.tags
    end
  end

  if not filter_opts or vim.tbl_isempty(filter_opts) or (#filter_opts.include == 0 and #filter_opts.exclude == 0) then
    return Tags:new(self)
  end

  local tags_map = {}
  for tag_value, tag_map in pairs(self) do
    local is_match = false
    local is_ignored = false

    for _, query in ipairs(filter_opts.include) do
      if match(tag_value, query, filter_opts.match_opt) then
        is_match = true
        break
      end
    end

    for _, query in ipairs(filter_opts.exclude) do
      if match(tag_value, query, filter_opts.match_opt) then
        is_ignored = true
        break
      end
    end

    if is_match and not is_ignored then
      tags_map[tag_value] = Tag:new({
        value = tag_value,
        notes_paths = tag_map,
      })
    elseif #filter_opts.include == 0 and #filter_opts.exclude == 0 then
      tags_map[tag_value] = Tag:new({
        value = tag_value,
        notes_paths = tag_map,
      })
    end
  end
  return Tags:new(tags_map)
end

function TagsMap:into_values()
  local tags_values = {}
  for tag_value, _ in pairs(self) do
    table.insert(tags_values, tag_value)
  end
  return tags_values
end

TagsMap._test = function()
  vim.cmd("lua package.loaded['vault'] = nil")
  vim.cmd("lua require('vault').setup()")
  vim.cmd("lua package.loaded['vault.tags.map'] = nil")
  local tags_map = TagsMap:new():fetch()
  -- local include_only = tags_map:fetch({{'class'},{}, 'startswith', 'all'})
  -- print("INCLUDE ONLY:" .. vim.inspect(vim.tbl_keys(include_only)))
  -- local exclude_only = tags_map:fetch({{},{'class'}, 'startswith', 'all'})
  -- print("EXCLUDE ONLY:" .. vim.inspect(vim.tbl_keys(exclude_only)))
  -- assert(vim.tbl_keys(include_only) ~= vim.tbl_keys(exclude_only))
  -- local exclude_and_include = tags_map:fetch({{'status'},{'status/TODO'}, 'startswith', 'all'})
  -- print("EXCLUDE AND INCLUDE:" .. vim.inspect(vim.tbl_keys(exclude_and_include)))
  
  print("TAGS MAP:" .. vim.inspect(tags_map))

end


return TagsMap
