local Object = require("nui.object")

---@enum FilterOptMatch
local FilterOptMatch = {
  "exact",
  "contains",
  "startswith",
  "endswith",
  "regex",
  "fuzzy",
}

---@enum NotesFilterOptMode
local FilterOptMode = {
  "all",
  "any",
}

---Filter options.
---@class VaultFilterOpts - Filter options for tags.
---@field include string[]? - Array of tag names to include (optional).
---@field exclude string[]? - Array of tag names to exclude (optional).
---@field match_opt string? - Match type for filtering notes (optional). Opts: "exact", "contains", "startswith", "endswith", "regex". "fuzzy"
---|"'exact'" # Matches exact value. E.g., "foo" matches "foo" but not "foobar".
---|"'contains'" # Matches value if it contains the query. E.g., "foo" matches "foo" and "foobar".
---|"'startswith'" # Matches value if it starts with the query. E.g., "foo" matches "foo" and "foobar".
---|"'endswith'" # Matches value if it ends with the query. E.g., "foo" matches "foo" and "barfoo".
---|"'regex'" # Matches value if it matches the query as a regex. E.g., "foo" matches "foo" and "barfoo".
---|"'fuzzy'" # Matches value if it matches the query fuzzily. E.g., "foo" matches "foo" and "barfoo".
---@field mode string? - Behavior for filtering notes (optional). Opts: "all", "any"
---|"'all'"  # Matches all names.
---|"'any'" # Matches any value.
local FilterOpts = Object("VaultFilterOpts")

---Create a new FilterOpts object.
---@param ... any
function FilterOpts:init(...)
  local args = { ... }
  if #args == 1 then
    args = args[1]
    -- if args.include then
    --   args[1] = args.include
    -- end
    -- if args.exclude then
    --   args[2] = args.exclude
    -- end
    -- if args.match_opt then
    --   args[3] = args.match_opt
    -- end
    -- if args.mode then
    --   args[4] = args.mode
    -- end
  end

  args[1] = args.include or args[1] or {}

  if type(args[1]) == "string" then
    args[1] = { args[1] }
  end

  if type(args[1]) == "table" then
    for _, v in ipairs(args[1]) do
      if type(v) ~= "string" then
        error("invalid key `include`: must be a string: " .. vim.inspect(v) .. " " .. type(v))
      end
    end
  end

	self.include = args[1]

  args[2] = args.exclude or args[2] or {}

  if type(args[2]) == "string" then
    args[2] = { args[2] }
  end

  if type(args[2]) == "table" then
    for _, v in ipairs(args[2]) do
      if type(v) ~= "string" then
        error("invalid key `exclude`: must be a string: " .. vim.inspect(v))
      end
    end
  end

	self.exclude = args[2]

  -- assert(type(self_match_opt) == "string" or type(self_match_opt) == "nil", "invalid key `match_opt`: must be a string or nil: " .. vim.inspect(self_match_opt))
  if #args[1] == nil and #args[2] == nil then
    error("key `include` and `exclude` cannot both be empty: " .. vim.inspect(args))
  end

  if args[1] and args[2] then
    for _, v in ipairs(args[1]) do
      if vim.tbl_contains(args[2], v) then
        error("key `include` and `exclude` cannot contain the same value: " .. vim.inspect(args))
      end
    end
  end

  args[3] = args.match_opt or args[3] or "exact"

	self.match_opt = args[3]

  if type(self.match_opt) ~= "string" then
    error("invalid key `match_opt`: must be a string: " .. vim.inspect(self.match_opt))
  end

  if not vim.tbl_contains(FilterOptMatch, self.match_opt) then
    error("invalid key `match_opt`: must be one of 'exact', 'contains', 'startswith', 'endswith', 'regex', 'fuzzy': " .. vim.inspect(self.match_opt))
  end

  args[4] = args.mode or args[4] or "all"

	self.mode = args[4]

  if type(self.mode) ~= "string" then
    error("invalid key `mode`: must be a string: " .. vim.inspect(self.mode))
  end

  if not vim.tbl_contains(FilterOptMode, self.mode) then
    error("invalid key `mode`: must be one of 'all' or 'any': " .. vim.inspect(self.mode))
  end

end

---@alias VaultFilterOpts.constructor fun(...): VaultFilterOpts
---@type VaultFilterOpts.constructor|VaultFilterOpts
local VaultFilterOpts = FilterOpts

return VaultFilterOpts
