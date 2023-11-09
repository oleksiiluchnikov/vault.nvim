---Tags
---@class Tags - Retrieve tags from vault.
---@field map Tag[] - Array of Tag objects.
---@field fetch function - Fetch tags from vault.
---@field filter function - Filter tags from vault.
local Tags = {}

---Create a new Tags object.
---@param this? table - The table to create the Tags object from.
---@return Tags
function Tags:new(this)
  this = this or {}
  setmetatable(this, self)
  self.__index = self
  return this
end

-- ---Fetch tags from vault.
-- ---@param filter_opts TagsFilterOpts? - Filter options for tags.
-- ---@return Tag[] - Array of Tag objects.
-- function Tags:fetch(filter_opts)
--   return  TagsValues:new():fetch():to_tags(filter_opts)
-- end

return Tags
