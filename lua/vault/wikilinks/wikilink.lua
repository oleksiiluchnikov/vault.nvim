local Object = require("vault.core.object")
local state = require("vault.core.state")
local fetcher = require("vault.fetcher")

--- @alias vault.Wikilink.Data.partial string

--- The raw link as it appears in the note. e.g. [[foo/bar/buzz|alias#heading]]
--- @alias vault.Wikilink.Data.raw string
--- Whether the link is embedded file link. e.g. ![[foo/bar/buzz|alias#heading]]
--- @alias vault.Wikilink.Data.embedded boolean
--- The slug of the link. e.g. [[foo/bar/buzz|alias#heading]] -> foo/bar/buzz
--- @alias vault.Wikilink.Data.slug string
--- The title of the link. e.g. [[foo/bar/buzz|alias#heading]] -> buzz
--- @alias vault.Wikilink.Data.stem string
--- The number of times the link appears in the note.
--- @alias vault.Wikilink.Data.count number
--- The aliases of the link. e.g. [[foo/bar/buzz|alias#heading]] -> alias
--- @alias vault.Wikilink.Data.alias string
--- All aliases used with that wikilink. e.g. [[foo/bar/buzz|alias#heading]] -> {["buzz"] = true, ["foo/bar/buzz"] = true, ["alias"] = true}
--- @alias vault.Wikilink.Data.aliases table<string, boolean>

--- @class vault.Wikilink.Data: vault.Object
--- @field raw vault.Wikilink.Data.raw
--- @field embedded boolean
--- @field slug vault.slug
--- @field stem vault.stem
--- @field count number
--- @field alias vault.Wikilink.Data.alias
--- @field aliases vault.map
--- @field section? vault.Note.Data.heading
--- @field sources vault.Sources.map
--- @field target vault.Note
--- @field variants vault.map
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
        local slugs = state.get_global_key("cache.notes.slugs") or fetcher.slugs()
        if slugs[self.slug] then
            self.target = self.slug
        end
    end
end

--- @class vault.Wikilink: vault.Object
--- @field data vault.Wikilink.Data
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
