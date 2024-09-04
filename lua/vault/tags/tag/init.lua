local Object = require("vault.core.object")
local error_formatter = require("vault.utils.fmt.error")
local utils = require("vault.utils")
local state = require("vault.core.state")

-- local config = require("vault.config")
local data = require("vault.tags.tag.data")

--- @class vault.Tag.data: vault.Object
local TagData = Object("VaultTagData")

--- @alias vault.Tag.Data.partial table - The partial data of the tag.

--- @param this vault.Tag.data.name|vault.Tag.Data.partial
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
--- @param key string -- `VaultTag.data` key
--- @return any
function TagData:__index(key)
    --- @type fun(self: vault.Tag.data): any -- A function that fetches the data for the given key.
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

--- @class vault.Tag: vault.Object
--- @field data vault.Tag.data - The data of the tag.
--- @field init fun(self: vault.Tag, this: vault.Tag.data.name|vault.Tag.Data.partial): vault.Tag
--- @field add_slug fun(self: vault.Tag, slug: string): vault.Tag - Add a slug to the `self.data.sources` table.
local Tag = Object("VaultTag")

--- Create a new |vault.Tag| instance.
--- @param this vault.Tag.data.name|vault.Tag.Data.partial
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

--- Rename the tag. and update all occurences of the tag in the notes.
--- @param name vault.Tag.data.name
--- @param verbose? boolean
--- @return vault.Tag
function Tag:rename(name, verbose)
    if name == nil or name == "" then
        error("Invalid name: " .. vim.inspect(name))
    end
    if name == self.data.name then
        return self
    end
    verbose = verbose or true
    --- @type vault.Note.constructor
    local Note = state.get_global_key("class.vault.Note") or require("vault.notes.note")

    --- @type table<string, vault.Source> - A table of paths to update.
    local paths_to_update = {}
    for slug, source in pairs(self.data.sources) do
        local path = utils.slug_to_path(slug)
        paths_to_update[path] = source
    end

    local old_name = "#" .. self.data.name
    local new_name = "#" .. name

    local message = ""
    if verbose == true then
        message = self.data.name .. " -> " .. name
    end

    -- Update connected notes
    for path, _ in pairs(paths_to_update) do
        --- @type vault.Note
        local note = Note(path)
        note:update_content(old_name, new_name)

        if verbose == true then
            message = message
                .. "\n"
                .. self.data.name
                .. " -> "
                .. name
                .. " in "
                .. note.data.slug
        end
    end
    self.data.name = name
    if verbose == false then
        return self
    end

    vim.notify(message, vim.log.levels.INFO, {
        title = "Vault Rename",
        timeout = 200,
    })
    -- require("vault.tags").reset()
    return self
end

--- Add a slug to the |vault.Tag.Data.sources|
---
--- @param slug vault.slug
--- @return vault.Tag
function Tag:add_slug(slug)
    if not self.data.sources[slug] then
        -- FIXME: Should add the |vault.Source| to the |vault.Tag.data.sources| table, not the |boolean| value.
        self.data.sources[slug] = true
    end
    return self
end

--- @alias vault.Tag.constructor fun(this: vault.Tag|table|string): vault.Tag
--- @type vault.Tag.constructor|vault.Tag
local VaultTag = Tag

state.set_global_key("class.vault.Tag", VaultTag)
return VaultTag
