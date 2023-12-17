local Object = require("vault.core.object")
local error_formatter = require("vault.utils.error_formatter")

-- local config = require("vault.config")
local data = require("vault.tags.tag.data")

---@class VaultTag.data: VaultObject
local TagData = Object("VaultTagData")

---@alias VaultTagDataPartial table - The partial data of the tag.

---@param this VaultTag.data.name|VaultTagDataPartial
function TagData:init(this)
    if not this then
        error(error_formatter.missing_parameter("this"), 2)
    end
    -- -- Validate keys
    -- for k, _ in pairs(this) do
    --     if not data[k] then
    --         error(
    --             "Invalid key: "
    --                 .. vim.inspect(k)
    --                 .. ". Valid keys: "
    --                 .. vim.inspect(vim.tbl_keys(data))
    --         )
    --     end
    -- end

    self.name = this.name
    self.is_nested = this.is_nested or false
    self.root = this.root or this.name
    if self.name:find("/") then
        self.root = self.root:match("^[^/]+")
    end
    self.sources = this.sources or nil
    self.count = this.count or 1
end

--- Fetch the data if it is not already cached.
---
---@param key string -- `VaultTag.data` key
---@return any
function TagData:__index(key)
    ---@type fun(self: VaultTag.data): any
    local func = data[key]
    if func then
        local value = func(self)
        self[key] = value
    end
    if self[key] == nil then
        error(
            "Invalid key: "
                .. vim.inspect(key)
                .. ". Valid keys: "
                .. vim.inspect(vim.tbl_keys(data))
        )
    end
    return self[key]
end

---@class VaultTag: VaultObject
---@field data VaultTag.data - The data of the tag.
---@field init fun(self: VaultTag, this: VaultTag.data.name|VaultTagDataPartial): VaultTag
---@field add_slug fun(self: VaultTag, slug: string): VaultTag - Add a slug to the `self.data.sources` table.
local Tag = Object("VaultTag")

--- Create a new `VaultTag` instance.
---
---@param this VaultTag.data.name|VaultTagDataPartial
function Tag:init(this)
    if not this then
        error(error_formatter.missing_parameter("this"), 2)
    end
    if type(this) == "string" then
        this = { name = this }
    end

    if not this.name then
        error(error_formatter.missing_parameter("name"), 2)
    end

    self.data = TagData(this)
end

--- Add a slug to the `self.data.sources` `VaultMap`.
---
---@param slug string
---@return VaultTag
function Tag:add_slug(slug)
    if not self.data.sources[slug] then
        self.data.sources[slug] = true
    end
    return self
end

---@alias VaultTag.constructor fun(this: VaultTag|table|string): VaultTag
---@type VaultTag.constructor|VaultTag
local VaultTag = Tag

return VaultTag
