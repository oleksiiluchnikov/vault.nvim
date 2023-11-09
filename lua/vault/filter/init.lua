local Filter = {}
---@class NotesFilterOpts: FilterOpts -- Filter options for notes.
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
local NotesFilterOpts = {}

---@enum FilterMode
local FilterMode = {
  "all",
  "any",
}

---@enum FilterKey
local FilterKey = {
  "tags",
  "title",
  "body",
}


---@return NotesFilterOpts
function NotesFilterOpts:new(this)
  this = this or {}
  if type(this[1]) == "string" then
    this.keys = { this[1] }
  else
    this.keys = this[1] or {}
    if #this.keys == 0 then
      error("No keys provided: " .. vim.inspect(self) .. " Opts: " .. vim.inspect(FilterKey))
    end
    for _, key in ipairs(this.keys) do
      if not vim.tbl_contains(FilterKey, key) then
        error("invalid key: `" .. key .. "` not in " .. vim.inspect(FilterKey))
      end
    end
  end

  this.mode = this[5] or "all"
  if type(this.mode) ~= "string" then
    error("invalid mode: `" .. this.mode .. "` not in " .. vim.inspect(FilterMode))
  end
  if not vim.tbl_contains(FilterMode, this.mode) then
    error("invalid mode: `" .. this.mode .. "` not in " .. vim.inspect(FilterMode))
  end

  this.match_opt = this[4] or "exact"

  local Match = require("vault.filter.match")
  local match_opts = Match.opts
  if not match_opts.is_valid(this.match_opt) then
    error("invalid match_opt: `" .. this.match_opt .. "` not in " .. vim.inspect(match_opts.MatchOpts))
  end

  this.include = this[2] or {}
  this.exclude = this[3] or {}

  if type(this.include) ~= "table" then
    error("include must be a table")
  end

  if type(this.exclude) ~= "table" then
    error("exclude must be a table")
  end

  if #this.include == 0 and #this.exclude == 0 then
    error("include and exclude cannot both be empty")
  end
  setmetatable(this, self)
  self.__index = self
  return this
end
--
function NotesFilterOpts:validate()
  -- local valid_keys = { "tags", "title", "body" }
  -- local valid_match_opts = { "exact", "contains", "startswith", "endswith", "regex", "fuzzy" }
  -- local valid_modes = { "all", "any" }

  ---@type string[]|string
  local keys = self.keys or {}
  if not vim.tbl_contains(valid_modes, self.mode) then
    error("invalid mode: `" .. self.mode .. "` not in " .. vim.inspect(valid_modes))
  end
end
---Tags filter options.
---@class TagsFilterOpts: FilterOpts - Filter options for tags.
---@field include string[]? - Array of tag values to include (optional).
---@field exclude string[]? - Array of tag values to exclude (optional).
---@field match_opt string? - Match type for filtering notes (optional). Opts: "exact", "contains", "startswith", "endswith", "regex". "fuzzy"
---|"'exact'" # Matches exact value. E.g., "foo" matches "foo" but not "foobar".
---|"'contains'" # Matches value if it contains the query. E.g., "foo" matches "foo" and "foobar".
---|"'startswith'" # Matches value if it starts with the query. E.g., "foo" matches "foo" and "foobar".
---|"'endswith'" # Matches value if it ends with the query. E.g., "foo" matches "foo" and "barfoo".
---|"'regex'" # Matches value if it matches the query as a regex. E.g., "foo" matches "foo" and "barfoo".
---@field mode string? - Behavior for filtering notes (optional). Opts: "all", "any"
---|"'all'"  # Matches all values.
---|"'any'" # Matches any value.
local TagsFilterOpts = {}

function TagsFilterOpts:new(this)
  this = this or {}
  setmetatable(this, self)
  this.include = this.include or this[1] or {}
  this.exclude = this.exclude or this[2] or {}
  this.match_opt = this.match_opt or this[3] or "exact"
  this.mode = this.mode or this[4] or "all"
  self.__index = self
  this:validate()
  return this
end

function TagsFilterOpts:__tostring()
  return vim.inspect(self)
end

---Check if an object is an instance of TagsFilterOpts.
---@return boolean
function TagsFilterOpts:is_instance()
  return getmetatable(self) == TagsFilterOpts
end




function TagsFilterOpts:validate()
  local valid_match_opts = { "exact", "contains", "startswith", "endswith", "regex", "fuzzy" }
  local valid_modes = { "all", "any" }
  if self.include and type(self.include) ~= "table" then
    error("include must be a table")
  end
  if self.exclude and type(self.exclude) ~= "table" then
    error("exclude must be a table")
  end
  if not vim.tbl_contains(valid_match_opts, self.match_opt) then
    error("invalid match_opt: `" .. self.match_opt .. "` not in " .. vim.inspect(valid_match_opts))
  end
  if not vim.tbl_contains(valid_modes, self.mode) then
    error("invalid mode: `" .. self.mode .. "` not in " .. vim.inspect(valid_modes))
  end
end


---Filter options.
---@class FilterOpts
---@field include string[]? - Array of values to include.
---@field exclude string[]? - Array of values to exclude.
---@field match_opt string? - Match type for filtering notes (optional). Opts: "exact", "contains", "startswith", "endswith", "regex". "fuzzy"
---|"'exact'" # Matches exact value. E.g., "foo" matches "foo" but not "foobar".
---|"'contains'" # Matches value if it contains the query. E.g., "foo" matches "foo" and "foobar".
---|"'startswith'" # Matches value if it starts with the query. E.g., "foo" matches "foo" and "foobar".
---|"'endswith'" # Matches value if it ends with the query. E.g., "foo" matches "foo" and "barfoo".
---|"'regex'" # Matches value if it matches the query as a regex. E.g., "foo" matches "foo" and "barfoo".
---@field mode string? - Behavior for filtering notes (optional). Opts: "all", "any"
---|"'all'"  # Matches all values.
---|"'any'" # Matches any value.
local FilterOpts = {}

function FilterOpts:new(this)
  this = this or {}
  setmetatable(this, self)
  self.__index = function(_, key)
    if key == "tags" then
      return TagsFilterOpts:new(this)
    elseif key == "notes" then
      return NotesFilterOpts:new(this)
    end
  end
  return this
end

function Filter:new(opts)
  opts = opts or {}
  setmetatable(opts, self)
  self.__index = function(_, key)
    if key == "opts" then
    print("opts")
      return FilterOpts:new(opts)
    end
  end
  return opts
end

-- Filter.opts = function(opts)
--   return FilterOpts:new(opts).tags
-- end
-- print(vim.inspect(Filter:new({ {"tags"}, {"title"}, "exact", "all" }).opts.tags))


return Filter
