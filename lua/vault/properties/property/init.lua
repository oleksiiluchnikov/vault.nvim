local Object = require("vault.core.object")
local error_formatter = require("vault.utils.fmt.error")

local state = require("vault.core.state")
local data = require("vault.properties.property.data")
local utils = require("vault.utils")

--- @class vault.Property.data: vault.Object
local PropertyData = Object("VaultPropertyData")

--- Partial data of the property. Used to create a new `VaultProperty` instance.
--- @alias VaultPropertyDataPartial table - The partial data of the property.

--- @param this vault.Property.Data.name|VaultPropertyDataPartial
function PropertyData:init(this)
    if not this then
        error(error_formatter.missing_parameter("this"), 2)
    end
    self.name = this.name
    self.values = this.values or {}
    self.sources = this.sources or nil
    self.count = this.count or #self.sources or 1
end

--- Fetch the data if it is not already cached.
--- @param key string -- `VaultProperty.data` key
--- @return any
function PropertyData:__index(key)
    --- @type fun(self: vault.Property.data): any
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

--- Properties are used to store metadata about notes.
--- They are used to store information such as the note's name, tags, and sources.
--- Usually, properties are exists in a |vault.Note.data.frontmatter| table.
--- but they can be also stored as inline properties in a note.
--- @class vault.Property: vault.Object
--- @field data vault.Property.data
--- @field init fun(self: vault.Property, this: vault.Property.Data.name|VaultPropertyDataPartial): vault.Property
--- @field add_slug fun(self: vault.Property, slug: string): vault.Property - Add a slug to the `self.data.sources` table.
local Property = Object("VaultProperty")

--- Create a new `VaultProperty` instance.
---
--- @param this vault.Property.Data.name|VaultPropertyDataPartial
function Property:init(this)
    if not this then
        error(error_formatter.missing_parameter("this"), 2)
    end
    if type(this) == "string" then
        this = { name = this }
    end

    if not this.name then
        error(error_formatter.missing_parameter("name"), 2)
    end

    self.data = PropertyData(this)
end

--- Rename the |'vault.Property'|. and update all occurences of the |'vault.Property'| in the notes.
--- @param name vault.Property.Data.name
--- @param verbose? boolean
--- @return vault.Property
function Property:rename(name, verbose)
    if name == nil or name == "" then
        error("Invalid name: " .. vim.inspect(name))
    end
    if name == self.data.name then
        return self
    end
    verbose = verbose or true
    --- @type vault.Note.constructor
    local Note = state.get_global_key("class.vault.Note") or require("vault.notes.note")

    --- @type table<string, vault.source.lnums> - A table of paths to update.
    local paths_to_update = {}
    for slug, lnums in pairs(self.data.sources) do
        local path = utils.slug_to_path(slug)
        paths_to_update[path] = lnums
    end

    local old_name = self.data.name
    local new_name = name

    local message = ""
    if verbose == true then
        message = self.data.name .. " -> " .. name
    end

    -- Update connected notes
    for path, lnums in pairs(paths_to_update) do
        --- @type vault.Note
        local note = Note(path)
        note:update_content(old_name, new_name, lnums)

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

--- Add a slug to the `self.data.sources` `VaultMap`.
---
--- @param slug string
--- @return vault.Property
function Property:add_slug(slug)
    if not self.data.sources[slug] then
        self.data.sources[slug] = true
    end
    return self
end

--- Add a value to the `self.data.values` `VaultMap`.
--- If the value already exists, it will add the slug to the `self.data.sources` `VaultMap`.
--- @param value vault.Property.Value
--- @return vault.Property
function Property:add_value(value)
    if not self.data.values[value.data.name] then
        self.data.values[value.data.name] = value
        return self
    end

    local value_sources = self.data.values[value.data.name].data.sources
    for slug, _ in pairs(value.data.sources) do
        if not self.data.sources[slug] then
            self.data.sources[slug] = true
        end
    end

    return self
end

--- @alias VaultProperty.constructor fun(this: vault.Property|table|string): vault.Property
--- @type VaultProperty.constructor|vault.Property
local VaultProperty = Property
state.set_global_key("class.vault.Property", VaultProperty)

return VaultProperty
