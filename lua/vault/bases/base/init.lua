local Object = require("vault.core.object")
local state = require("vault.core.state")

---@alias vault.Base.FilterTree table<string, unknown>
---@alias vault.Base.Formulas table<string, string>

---@class vault.Base.PropertyConfig
---@field displayName? string

---@class vault.Base.ViewConfig
---@field type string
---@field name? string
---@field order? integer
---@field group_by? string
---@field group_values? string[]
---@field display_fields? string[]
---@field render_mode? string
---@field date_field? string
---@field end_date_field? string
---@field primary_field? string

--- @class vault.Base.Data
--- @field path vault.path Absolute path to the .base file
--- @field relpath vault.relpath Relative path from vault root
--- @field name string Base name (file stem without extension)
--- @field slug string Unique identifier (same as name for bases)
--- @field filters? vault.Base.FilterTree The parsed filter tree (and:/or:/not: structure)
--- @field formulas? vault.Base.Formulas Named formula expressions
--- @field properties? table<string, vault.Base.PropertyConfig> Property display configuration
--- @field views? vault.Base.ViewConfig[] Array of view definitions

--- @class vault.Base: vault.Object
--- @field data vault.Base.Data
local Base = Object("VaultBase")


--- Initialize a Base object from raw scanner data.
---
--- @param this vault.Base.Data|table<string, unknown> Raw data from the Rust scanner or manual construction
function Base:init(this)
    if type(this) ~= "table" then
        error("Base:init() expects a table, got " .. type(this))
    end

    if not this.path and not this.name then
        error("Base:init() requires at least `path` or `name`")
    end

    self.data = {
        path = this.path or "",
        relpath = this.relpath or "",
        name = this.name or "",
        slug = this.name or this.slug or "",
        filters = this.filters,
        formulas = this.formulas,
        properties = this.properties,
        views = this.views,
    }
end


--- String representation for the Base object.
--- @return string
function Base:__tostring()
    return string.format("VaultBase(%s)", self.data.name)
end


--- Check if this base has any filters defined.
--- @return boolean
function Base:has_filters()
    return type(self.data.filters) == "table" and next(self.data.filters) ~= nil
end


--- Check if this base has any formulas defined.
--- @return boolean
function Base:has_formulas()
    return type(self.data.formulas) == "table" and next(self.data.formulas) ~= nil
end


--- Get the list of formula names defined in this base.
--- @return string[]
function Base:formula_names()
    if type(self.data.formulas) ~= "table" then
        return {}
    end
    return vim.tbl_keys(self.data.formulas)
end


--- Get the number of views defined in this base.
--- @return integer
function Base:view_count()
    if type(self.data.views) ~= "table" then
        return 0
    end
    return #self.data.views
end


--- Get property display names map.
--- Returns a table mapping property keys to their display names.
--- @return table<string, string>
function Base:display_names()
    local result = {}
    if type(self.data.properties) ~= "table" then
        return result
    end
    for key, prop in pairs(self.data.properties) do
        if type(prop) == "table" and prop.displayName then
            result[key] = prop.displayName
        else
            result[key] = key
        end
    end
    return result
end


--- Evaluate this base's filters against a set of notes.
--- Returns the notes that match the filter tree.
---
--- @param notes table<string, vault.Note> Map of slug -> Note
--- @return table<string, vault.Note> matched notes
function Base:match_notes(notes)
    if not self:has_filters() then
        -- No filters means all notes match
        return notes
    end

    local evaluator = require("vault.bases.evaluator")
    local matched = {}

    for slug, note in pairs(notes) do
        if evaluator.evaluate_filter(self.data.filters, note) then
            matched[slug] = note
        end
    end

    return matched
end


--- Evaluate formulas for a single note, returning computed values.
---
--- @param note vault.Note The note to evaluate formulas against
--- @return table<string, unknown> formula_name -> computed_value
function Base:evaluate_formulas(note)
    if not self:has_formulas() then
        return {}
    end

    local evaluator = require("vault.bases.evaluator")
    local results = {}

    for name, expr in pairs(self.data.formulas) do
        local ok, value = pcall(evaluator.evaluate_expression, expr, note)
        if ok then
            results[name] = value
        else
            results[name] = nil
        end
    end

    return results
end


--- @type vault.Base
local VaultBase = Base

state.set_global_key("class.vault.Base", VaultBase)
return VaultBase
