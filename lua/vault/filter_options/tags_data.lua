---Tags filter options.
---@class TagsDataFilterOptions: FilterOptions - Filter options for tags.
---@field include string[]? - Array of tag values to include (optional).
---@field exclude string[]? - Array of tag values to exclude (optional).
---@field match_opt string? - Match type for filtering notes (optional). Options: "exact", "contains", "startswith", "endswith", "regex". "fuzzy"
---|"'exact'" # Matches exact value. E.g., "foo" matches "foo" but not "foobar".
---|"'contains'" # Matches value if it contains the query. E.g., "foo" matches "foo" and "foobar".
---|"'startswith'" # Matches value if it starts with the query. E.g., "foo" matches "foo" and "foobar".
---|"'endswith'" # Matches value if it ends with the query. E.g., "foo" matches "foo" and "barfoo".
---|"'regex'" # Matches value if it matches the query as a regex. E.g., "foo" matches "foo" and "barfoo".
---@field mode string? - Behavior for filtering notes (optional). Options: "all", "any"
---|"'all'"  # Matches all values.
---|"'any'" # Matches any value.
local TagsDataFilterOptions = {}

function TagsDataFilterOptions:new(this)
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


function TagsDataFilterOptions:validate()
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

return TagsDataFilterOptions
