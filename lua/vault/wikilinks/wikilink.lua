local Object = require("vault.core.object")
local state = require("vault.core.state")
local scanner = require("vault.scanner")

--- @alias vault.Wikilink.Data.partial string A partial wikilink that might not contain full markdown syntax

--- @description Represents all possible components and metadata for a wikilink in a vault note
--- The raw link as it appears in the note. e.g. [[foo/bar/buzz|alias#heading]]
--- @alias vault.Wikilink.Data.raw string The complete wikilink text as it appears in the source

--- Whether the link is embedded file link. e.g. ![[foo/bar/buzz|alias#heading]]
--- @alias vault.Wikilink.Data.embedded boolean Indicates if this is an embedded file/image link

--- The slug of the link. e.g. [[foo/bar/buzz|alias#heading]] -> foo/bar/buzz
--- @alias vault.Wikilink.Data.slug string The unique identifier path for the linked note

--- The title of the link. e.g. [[foo/bar/buzz|alias#heading]] -> buzz
--- @alias vault.Wikilink.Data.stem string The display name or title extracted from the slug

--- The number of times the link appears in the note.
--- @alias vault.Wikilink.Data.count number Frequency count of this link's occurrence

--- The aliases of the link. e.g. [[foo/bar/buzz|alias#heading]] -> alias
--- @alias vault.Wikilink.Data.alias string Alternative display text for the link

--- All aliases used with that wikilink. e.g. [[foo/bar/buzz|alias#heading]] -> {["buzz"] = true, ["foo/bar/buzz"] = true, ["alias"] = true}
--- @alias vault.Wikilink.Data.aliases table<string, boolean> Collection of all valid display names for this link

--- @class vault.Wikilink.Data: vault.Object
--- @description Core data structure representing a wikilink in a vault note
--- @field raw vault.Wikilink.Data.raw The complete original wikilink text
--- @field embedded boolean Indicates if this is an embedded media link
--- @field slug vault.slug Unique identifier path for the linked note
--- @field stem vault.stem Display name extracted from slug
--- @field count number Number of occurrences in the note
--- @field alias vault.Wikilink.Data.alias Optional display text override
--- @field aliases vault.map Set of all valid display names
--- @field section? vault.Note.Data.heading Optional heading/section reference
--- @field sources vault.Sources.map References to source notes containing this link
--- @field target vault.Note The resolved target note object
--- @field variants vault.map Alternative forms of the link
--- ```lua
--- assert(wikilink.raw == "[[foo/bar/buzz|alias#heading]]") -- Raw link as it appears in the note
--- assert(wikilink.content== "foo/bar/buzz") -- Content of the link as it appears in the note
--- assert(wikilink.stem == "buzz") -- Tail of the link. Must be unique
--- assert(wikilink.aliases == {["buzz"] = true, ["foo/bar/buzz"] = true, ["alias"] = true}) -- All aliases used with that wikilink
--- assert(wikilink.heading == "heading") -- Heading of the link if it exists
--- assert(wikilink.notes_relpaths == {"bar.md", "foo.md"}) -- All relative paths that has that wikilink
--- assert(wikilink.target == "foo/bar/buzz.md") -- The target of the link if it exists
--- ```
local WikilinkData = Object("VaultWikilink")

--- @param this vault.Wikilink.Data
function WikilinkData:init(this)
    if not this then
        error("Missing `this` argument: vault.Wikilink.data")
    elseif not this.raw then
        error("Missing `raw` argument: string")
    end

    if this.raw:find("^!") then
        this.raw = this.raw:sub(2)
        this.embedded = true
    end

    local content = this.raw
    if this.raw:sub(1, 2) == "[[" or this.raw:sub(-2) == "]]" then
        content = this.raw:sub(3, -3) -- Remove [[ and ]]
    end
    self.slug = content:match([[([^#|]+)]])
    if not self.slug or self.slug == "" then
        error("Invalid wikilink: " .. this.raw)
    end
    self.section = content:match([[#([^|]+)]])
    self.alias = content:match([[|(.+)$]])
    self.sources = this.sources
    self.stem = self.slug:match("([^/]+)$") or self.slug

    self.aliases = this.aliases or {}
    self.aliases[self.stem] = true
    if self.alias then
        self.aliases[self.alias] = true
    end

    self.count = 1

    self.variants = {}
    self.variants[self.stem] = true
    if self.stem ~= self.slug then
        self.variants[self.slug] = true
    end

    -- TODO: Let we put the target is the note itself, not the slug of the note
    if this.target then
        self.target = this.target
    else
        --- @type vault.Notes.data.slugs
        local slugs = state.get_global_key("cache.notes.slugs") or scanner.slugs()
        if slugs[self.slug] then
            self.target = self.slug
        end
    end
end

--- @class vault.Wikilink: vault.Object
--- @field Data vault.Wikilink.Data
local Wikilink = Object("VaultWikilink")

--- @param this vault.Wikilink.raw|vault.Wikilink.Data.partial
function Wikilink:init(this)
    if not this then
        error("Missing `this` argument: vault.Wikilink.data")
    end
    if type(this) == "string" then
        this = { raw = this }
    end
    self.data = WikilinkData(this)
end

--- @alias vault.Wikilink.constructor fun(raw_link: vault.Wikilink.Data.raw|vault.Wikilink.Data.partial)
--- @type vault.Wikilink|vault.Wikilink.constructor
local M = Wikilink

state.set_global_key("class.vault.Wikilink", M)
return M
