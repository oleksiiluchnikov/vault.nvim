local Object = require("nui.object")
local Job = require("plenary.job")
local config = require("vault.config")
local utils = require("vault.utils")
local FilterOpts = require("vault.filter_opts")
local utils_line = require("vault.utils.line")
local Tag = require("vault.tags.tag")

local function match(...)
  local Matcher = require("vault.utils.matcher")()
  return Matcher:match(...)
end

---@param line string - The line to parse.
---@return table<string, string[]>? - Table of tag names and their notes paths. E.g., { ["status"] = { "foo.md", "bar.md" } }
local function parse_line_for_tags(line)
  local tags_map_from_line = {}
  local path, line_with_tag = line:match("^(.*" .. config.ext .. "):(.+)")
  if path == nil or line_with_tag == nil then
    return
  end

  for tag_name in line:gmatch("#([A-Za-z0-9_][A-Za-z0-9-_/]+)") do
    if utils.is_tag(tag_name) == false then
      goto continue
    end

    if tags_map_from_line[tag_name] == nil then
      tags_map_from_line[tag_name] = {}
    end

    if not vim.tbl_contains(tags_map_from_line[tag_name], path) then
      vim.list_extend(tags_map_from_line[tag_name], { path })
    end

    ::continue::
  end
  return tags_map_from_line
end

---Tags
---@class VaultTags - Retrieve tags from vault.
local Tags = Object("VaultTags")

---Retrieve all tags names from your vault.
---@param filter_opts? table - Filter options for tags.
function Tags:init(filter_opts)

  local cmd = "rg" -- TODO: Make this configurable.
  local tag_pattern = [[#[A-Za-z0-9_][A-Za-z0-9-_/]+]] -- TODO: Make this configurable.
  local root_dir = config.dirs.root
  local args = {
    "--no-heading",
    tag_pattern,
    root_dir,
  }

  local stdout = {}

  ---@type Job
  Job:new({
    command = cmd,
    args = args,
    cwd = root_dir,

    on_exit = function(j, _, _)
      stdout = j:result()
    end,
  }):sync()

  assert(stdout, "rg failed to run")

  ---@type table<string, VaultTag>
  local tags_map = {}
  for _, line in pairs(stdout) do
    if utils_line.has_tag(line) == false then
      goto continue
    end
    ---@type table<string, string[]>? - Table of tag names and their notes paths. E.g., { ["status"] = { "foo.md", "bar.md" } }
    local tags_map_from_line = parse_line_for_tags(line)

    if tags_map_from_line == nil or vim.tbl_isempty(tags_map_from_line) then
      goto continue
    end

    for tag_name, notes_paths_from_line in pairs(tags_map_from_line) do
      if not tags_map[tag_name] then
        tags_map[tag_name] = Tag({
          name = tag_name,
          notes_paths = notes_paths_from_line,
        })
      end
      for _, path in pairs(notes_paths_from_line) do
        -- if not vim.tbl_contains(tags_map[tag_name], path) then
        --   vim.list_extend(tags_map[tag_name], { path })
        -- end
        tags_map[tag_name]:add_path(path)
      end
    end
  ::continue::
  end

  ---@type table<integer, VaultTag> - List of tags.
  if filter_opts then
      filter_opts = FilterOpts(filter_opts)
    for tag_name, _ in pairs(tags_map) do

      if next(filter_opts.include) then
        for _, query in ipairs(filter_opts.include) do
          if match(tag_name, query, filter_opts.match_opt) == false then
            if tags_map[tag_name] then
              tags_map[tag_name] = nil
            end
          end
        end
      end

      if next(filter_opts.exclude) then
        for _, query in ipairs(filter_opts.exclude) do
          if match(tag_name, query, filter_opts.match_opt) == true then
            if tags_map[tag_name] then
              tags_map[tag_name] = nil
            end
          end
        end
      end
    end
  end

  self.map = {}
  for _, tag in pairs(tags_map) do
    self.map[tag.data.name] = tag
  end

end

---@param key string - The key to get values for.
---@return string[] - The values for the key.
---@see VaultTag
function Tags:values_by_key(key)
  local values = {}
  for _, tag in pairs(self.map) do
    if tag.data[key] then
      table.insert(values, tag.data[key])
    end
  end
  return values
end

function Tags:list()
  local list = {}
  for _, tag in pairs(self.map) do
    if type(tag) ~= "table" then
      goto continue
    end
    table.insert(list, tag)
    ::continue::
  end
  return list
end

-- function Tags:nested(root_tag_name)
--   local tags = self:list()
--   local nested_tags = {}
--   for _, v in pairs(tags) do
--     if next(v.children) then
--        table.insert(nested_tags, v)
--     end
--   end
--   return nested_tags
-- end
--

---@param key string - The key to filter by.
---| "'name'" # Filter by tag name.
---| "'notes_paths'" # Filter by notes paths.
---@param value string? - The value to filter by.
---@param match_opt? string - The match option to use.
---@return table<string, VaultTag> - The list of tags.
function Tags:by(key, value, match_opt)
  assert(key, "missing `key` argument: string")
  local tags = self:list()
  local tags_by = {}
  for _, tag in pairs(tags) do
    if tag[key] and not value then
      table.insert(tags_by, tag)
    elseif tag[key] and value then
      if match(tag[key], value, match_opt) then
        table.insert(tags_by, tag)
      end
    end
  end
  return tags_by
end

-- function Tags:traverse(root_tag_name)
--   local map = self.map
--   local root_tag = map[root_tag_name]
--   if not root_tag then
--     return
--   end
--   local nested_tags = {}
--   for _, v in pairs(root_tag.children) do
--     if next(v.children) then
--        table.insert(nested_tags, v)
--     end
--   end
--   return nested_tags
-- end

-- ---@param root_tag_names string|table? - The root tag name to traverse.
-- ---@return string[]? - The list of tag names.
-- function Tags:traverse(root_tag_names)
--   local map = self.map
--   if type(root_tag_names) == "string" then
--     root_tag_names = { root_tag_names }
--   end
--
--   local root_tags = vim.tbl_keys(map)
--   local root_tags_names = vim.tbl_keys(map)
--   for _, tag_name in ipairs(root_tag_names) do
--     if not vim.tbl_contains(root_tags, tag_name) then
--       table.insert(root_tags, tag_name)
--     end
--   end
--
--   local nested_tags = {}
--   for _, v in pairs(root_tag.children) do
--     if next(v.children) then
--         table.insert(nested_tags, v)
--     end
--   end
--   return nested_tags
-- end

---@alias VaultTags.constructor fun(filter_opts?: table): VaultTags
---@type VaultTags.constructor|VaultTags
local VaultTags = Tags

return VaultTags
