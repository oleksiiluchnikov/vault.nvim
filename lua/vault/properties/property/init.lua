local Object = require("vault.core.object")
local Error = require("vault.utils.error")

local state = require("vault.core.state")
local data = require("vault.properties.property.data")
local utils = require("vault.utils")
local log = require("vault.log").scope("property")

--- Partial constructor input accepted by `PropertyData:init`.
--- @alias VaultPropertyDataPartial { name?: string, values?: table<string, vault.Property.Value>, sources?: vault.Sources.map }

--- @class vault.Property.Data: vault.Object
--- @field name    vault.Property.Data.name                - The property key name, e.g. `"foo-bar"`.
--- @field values  table<string, vault.Property.Value>     - Map of value-name → PropertyValue.
--- @field sources vault.Sources.map                       - Map of note slugs that carry this property.
--- @field count   number                                  - Number of notes carrying this property.
local PropertyData = Object("VaultPropertyData")

--- Initialise a `VaultPropertyData` instance.
--- @param this vault.Property.Data.name|VaultPropertyDataPartial
function PropertyData:init(this)
    if not this then
        error(Error.MISSING_PARAMETER("this"), 2)
    end
    self.name = this.name
    self.values = this.values or {}
    self.sources = this.sources or {}
    self.count = 0
    for _, _ in pairs(self.sources) do
        self.count = self.count + 1
    end
end

--- Lazy-load a computed field from the `data` parser table.
--- If the key exists in `data`, the resolver is called and the result is cached.
--- @param key string Field name to resolve via `vault.Property.Data.parser`
--- @return any
function PropertyData:__index(key)
    --- @type fun(self: vault.Property.Data): any
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

--- A frontmatter / inline property observed in one or more vault notes.
---
--- Properties are used to store structured metadata such as tags, dates, and links.
--- They usually appear in a note's YAML frontmatter but can also be inline properties.
---
--- @class vault.Property: vault.Object
--- @field data   vault.Property.Data   - Resolved data bag for this property instance.
--- @field init   fun(self: vault.Property, this: vault.Property.Data.name|VaultPropertyDataPartial): vault.Property
--- @field add_slug  fun(self: vault.Property, slug: vault.slug): vault.Property      - Register a note slug as a source.
--- @field add_value fun(self: vault.Property, value: vault.Property.Value): vault.Property
--- @field rename    fun(self: vault.Property, name: vault.Property.Data.name, verbose?: boolean): vault.Property
local Property = Object("VaultProperty")

--- Create a new `VaultProperty` instance.
---
--- @param this vault.Property.Data.name|VaultPropertyDataPartial
function Property:init(this)
    if not this then
        error(Error.MISSING_PARAMETER("this"), 2)
    end
    if type(this) == "string" then
        this = { name = this }
    end

    if not this.name then
        error(Error.MISSING_PARAMETER("name"), 2)
    end

    self.data = PropertyData(this)
end

--- Rename the property and update every occurrence in the connected notes.
--- @param name vault.Property.Data.name  New property name
--- @param verbose? boolean               When `true` (default) log a summary message
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

    --- @type table<vault.path, vault.source.lnums> - Map of file paths to update.
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

    log.info(message)
    -- require("vault.tags").reset()
    return self
end

--- Register a note slug as a source for this property in `self.data.sources`.
---
--- @param slug vault.slug
--- @return vault.Property
function Property:add_slug(slug)
    if not self.data.sources[slug] then
        self.data.sources[slug] = true
    end
    return self
end

--- Attach a `vault.Property.Value` to this property.
--- If the value already exists, merge its source slugs into `self.data.sources`.
--- @param value vault.Property.Value
--- @return vault.Property
function Property:add_value(value)
    if not self.data.values[value.data.name] then
        self.data.values[value.data.name] = value
        return self
    end

    for slug, _ in pairs(value.data.sources) do
        if not self.data.sources[slug] then
            self.data.sources[slug] = true
        end
    end

    return self
end

--- @alias vault.Property.constructor fun(this: vault.Property|VaultPropertyDataPartial|string): vault.Property
--- @type vault.Property.constructor|vault.Property
local VaultProperty = Property
state.set_global_key("class.vault.Property", VaultProperty)

return VaultProperty
