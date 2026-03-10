local Object = require("vault.core.object")
local error_formatter = require("vault.utils.error")
local utils = require("vault.utils")
local state = require("vault.core.state")
local Parser = require("vault.parser")
local log = require("vault.log").scope("line")

-- local config = require("vault.config")
-- local data = require("vault.lines.line.data")

---@alias vault.Line.Data.name vault.Line.content
---@alias vault.Line.Data.metadata table<string, string>
---@alias vault.Line.Data.tags vault.Tags.map
---@alias vault.Line.sources vault.Sources.map

---@class vault.Line.Data.partial
---@field content vault.Line.content
---@field sources? vault.Line.sources
---@field is_nested? boolean
---@field wikilinks? vault.Wikilinks.map
---@field metadata? vault.Line.Data.metadata
---@field tags? vault.Line.Data.tags

--- @class vault.Line.Data: vault.Object
--- @field content vault.Line.content
--- @field sources vault.Line.sources
--- @field is_nested boolean
--- @field wikilinks vault.Wikilinks.map
--- @field link string?
--- @field metadata vault.Line.Data.metadata
--- @field tags vault.Line.Data.tags
--- @field count integer
--- @field occurences integer
local LineData = Object("VaultLineData")

--- @param this vault.Line.Data.partial
---@return nil
function LineData:init(this)
    self.content = this.content

    self.sources = this.sources or {}
    self.is_nested = this.is_nested or false
    self.wikilinks = this.wikilinks or Parser.wikilinks_from_line(this.content)
    --- TODO: Implement sublines

    -- Extract status and content
    self.link = this.content:match("%[%[(.-)%]%]")

    -- Parse wikilinks

    -- Parse metadata fields
    -- local metadata_fields = {
    --     "id",
    --     "created",
    --     "due",
    --     "start",
    --     "schedule",
    --     "completed",
    --     "priority",
    --     "repeat",
    -- }

    self.metadata = this.metadata or Parser.metadata_from_line(this.content)
    self.tags = this.tags or Parser.tags_from_line(this.content)

    -- self.content = this.line:gsub("^%s*-%s*%[.%]%s*", ""):match("^(.-)%s*%[%a+::") or this.line
    -- content is the line without the status, tags, and metadata
    -- self.content = this.line:gsub("^%s*-%s*%[.%]%s*", ""):match("^(.-)%s*%[%a+::") or this.line
    -- self.content = this.line:gsub("- %[.-%]", ""):match("^(.-)%[%a+::"):gsub("\n", "")
    --     or this.line

    -- Calculate source statistics
    self.count = 0
    self.occurences = 0
    for _, occurences in pairs(self.sources) do
        self.count = self.count + 1
        if type(occurences) == "table" then
            for _ in pairs(occurences) do
                self.occurences = self.occurences + 1
            end
        end
    end
end

--- @class vault.Line: vault.Object
--- @field data vault.Line.Data - The Data of the line.
--- @field init fun(self: vault.Line, this: vault.Line.Data.name|vault.Line.Data.partial): vault.Line
--- @field add_slug fun(self: vault.Line, slug: vault.slug): vault.Line - Add a slug to the `self.Data.sources` table.
local Line = Object("VaultLine")

--- Create a new |vault.Line| instance.
--- @param this vault.Line.Data.name|vault.Line.Data.partial
---@return nil
function Line:init(this)
    if not this then
        error(error_formatter.MISSING_PARAMETER("this"), 2)
    end
    if type(this) == "string" then
        this = { content = this }
    end

    if not this.content then
        error(error_formatter.MISSING_PARAMETER("name"), 2)
    end

    self.data = LineData(this)
end

--- Rename the line. and update all occurences of the line in the notes.
--- @param name vault.Line.Data.name
--- @param verbose? boolean
--- @return vault.Line
function Line:rename(name, verbose)
    if name == nil or name == "" then
        error("Invalid name: " .. vim.inspect(name))
    end
    if name == self.data.content then
        return self
    end
    verbose = verbose or true
    --- @type vault.Note.constructor
    local Note = state.get_global_key("class.vault.Note") or require("vault.notes.note")

    --- @type table<vault.path, vault.source.lnums|boolean> - A table of paths to update.
    local paths_to_update = {}
    for slug, lnums in pairs(self.data.sources) do
        local path = utils.slug_to_path(slug)
        paths_to_update[path] = lnums
    end

    local old_name = "#" .. self.data.content
    local new_name = "#" .. name

    local message = ""
    if verbose == true then
        message = self.data.content .. " -> " .. name
    end

    -- Update connected notes
    for path, lnums in pairs(paths_to_update) do
        --- @type vault.Note
        local note = Note(path)
        note:update_content(old_name, new_name, lnums)

        if verbose == true then
            message = message
                .. "\n"
                .. self.data.content
                .. " -> "
                .. name
                .. " in "
                .. note.data.slug
        end
    end
    self.data.content = name
    if verbose == false then
        return self
    end

    log.info(message)
    -- require("vault.lines").reset()
    return self
end

--- Add a slug to the |vault.Line.Data.sources|
---
--- @param slug vault.slug
--- @return vault.Line
function Line:add_slug(slug)
    if not self.data.sources[slug] then
        -- FIXME: Should add the |vault.Source| to the |vault.Line.data.sources| table, not the |boolean| value.
        self.data.sources[slug] = true
    end
    return self
end

--- @alias vault.Line.constructor fun(this: vault.Line|table|string): vault.Line
--- @type vault.Line.constructor|vault.Line
local VaultLine = Line

state.set_global_key("class.vault.Line", VaultLine)
return VaultLine
