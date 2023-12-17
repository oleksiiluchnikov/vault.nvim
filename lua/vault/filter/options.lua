local Object = require("vault.core.object")
local enums = require("vault.utils.enums")

--- Filter options.

local FilterOptions = Object("VaultFilterOpts")

--- Create a new FilterOpts object.
---
---@param search_term string - Search term to filter on.
---@param include string[]? - Array of tag names to include (optional).
---@param exclude string[]? - Array of tag names to exclude (optional).
---@param match_opt string? - Match type for filtering notes (optional). Opts: "exact", "contains", "startswith", "endswith", "regex". "fuzzy"
---@param mode string? - Behavior for filtering notes (optional). Opts: "all", "any"
function FilterOptions:init(search_term, include, exclude, match_opt, mode)
    self.search_term = search_term
    self.include = include or {}
    self.exclude = exclude or {}
    self.match_opt = match_opt or "exact"
    self.mode = mode or "all"

    if type(self.search_term) ~= "string" then
        error("invalid key `search_term`: must be a string: " .. vim.inspect(self.search_term))
    end

    -- Deprecated:
    -- -- args = { search_term, include, exclude, match_opt, mode }
    -- local args = { ... }
    -- if #args == 1 then
    --     args = args[1]
    -- end
    -- args[1] = args.include or args[1] or {}
    -- if type(args[1]) == "string" then
    --     args[1] = { args[1] }
    -- end
    -- if type(args[1]) == "table" then
    --     for _, v in ipairs(args[1]) do
    --         if type(v) ~= "string" then
    --             error(
    --                 "invalid key `include`: must be a string: " .. vim.inspect(v) .. " " .. type(v)
    --             )
    --         end
    --     end
    -- end
    --
    -- self.include = args[1]
    --
    -- args[2] = args.exclude or args[2] or {}
    -- if type(args[2]) == "string" then
    --     args[2] = { args[2] }
    -- end
    -- if type(args[2]) == "table" then
    --     for _, v in ipairs(args[2]) do
    --         if type(v) ~= "string" then
    --             error("invalid key `exclude`: must be a string: " .. vim.inspect(v))
    --         end
    --     end
    -- end
    --
    -- self.exclude = args[2]
    --
    -- args[3] = args.match_opt or args[3] or "exact"
    --
    -- self.match_opt = args[3]
    --
    -- if type(self.match_opt) ~= "string" then
    --     error("invalid key `match_opt`: must be a string: " .. vim.inspect(self.match_opt))
    -- end
    --
    -- if not enums.match_opts[self.match_opt] then
    --     error(
    --         "invalid key `match_opt`: must be one of 'exact', 'contains', 'startswith', 'endswith', 'regex', 'fuzzy': "
    --             .. vim.inspect(self.match_opt)
    --     )
    -- end
    --
    -- args[4] = args.mode or args[4] or "all"
    --
    -- self.mode = args[4]
    --
    -- if type(self.mode) ~= "string" then
    --     error("invalid key `mode`: must be a string: " .. vim.inspect(self.mode))
    -- end
    --
    -- if not enums.filter_mode[self.mode] then
    --     error("invalid key `mode`: must be one of 'all' or 'any': " .. vim.inspect(self.mode))
    -- end
    --
    -- if #self.include == 0 and #self.exclude == 0 then
    --     error("key `include` and `exclude` cannot both be empty: " .. vim.inspect(args))
    -- end
    -- if self.include and self.exclude then
    --     for _, v in ipairs(self.include) do
    --         if vim.tbl_contains(self.exclude, v) then
    --             error(
    --                 "key `include` and `exclude` cannot contain the same value: "
    --                     .. vim.inspect(args)
    --             )
    --         end
    --     end
    -- end
end

---@alias VaultFilterOptions.constructor fun(...): VaultFilter.option
---@type VaultFilterOptions.constructor|VaultFilter.option
local VaultFilterOpts = FilterOptions

return VaultFilterOpts
