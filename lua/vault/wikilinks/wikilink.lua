local Object = require("vault.core.object")
local state = require("vault.core.state")
local fetcher = require("vault.fetcher")

---@alias VaultWikilink.data.partial string

---@alias VaultWikilink.data.raw string
---@alias VaultWikilink.data.stem string
---@alias VaultWikilink.data.aliases table<string, boolean>

---@class VaultWikilink.data: VaultObject
---@field raw string - The raw link as it appears in the note. e.g. [[foo/bar/buzz|alias#heading]]
---@field embedded boolean - Whether the link is embedded file link. e.g. ![[foo/bar/buzz|alias#heading]]
---@field slug string - The slug of the link. e.g. [[foo/bar/buzz|alias#heading]] -> foo/bar/buzz
---@field stem VaultWikilink.data.stem - The title of the link. e.g. [[foo/bar/buzz|alias#heading]] -> buzz
---@field count number - The number of times the link appears in the note.
---@field alias string - The aliases of the link. e.g. [[foo/bar/buzz|alias#heading]] -> alias
---@field aliases VaultMap - All aliases used with that wikilink. e.g. [[foo/bar/buzz|alias#heading]] -> {["buzz"] = true, ["foo/bar/buzz"] = true, ["alias"] = true}
---@field section string? - The heading of the link. e.g. [[foo/bar/buzz|alias#heading]] -> heading
---@field sources VaultMap.sources - The notes slugs of notes with the tag.
---@field target VaultNote.data.slug - The target of the link if it exists. e.g. [[foo/bar/buzz|alias#heading]] -> foo/bar/buzz
---@field variants VaultMap - All variants of the link. e.g.
---```lua
---assert(wikilink.raw == "[[foo/bar/buzz|alias#heading]]") -- Raw link as it appears in the note
---assert(wikilink.content== "foo/bar/buzz") -- Content of the link as it appears in the note
---assert(wikilink.stem == "buzz") -- Tail of the link. Must be unique
---assert(wikilink.aliases == {["buzz"] = true, ["foo/bar/buzz"] = true, ["alias"] = true}) -- All aliases used with that wikilink
---assert(wikilink.heading == "heading") -- Heading of the link if it exists
---assert(wikilink.notes_relpaths == {"bar.md", "foo.md"}) -- All relative paths that has that wikilink
---assert(wikilink.target == "foo/bar/buzz.md") -- The target of the link if it exists
---```
local WikilinkData = Object("VaultWikilink")

--- Create a new Wikilink object.
---@param this VaultWikilink.data
function WikilinkData:init(this)
    if not this then
        error("Missing `this` argument: VaultWikilink.data")
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

    if this.target then
        self.target = this.target
    else
        ---@type VaultMap.slugs
        local slugs = state.get_global_key("slugs") or fetcher.slugs()
        if not slugs then
            error("Missing `slugs` global key")
        end

        if slugs[self.slug] then
            self.target = self.slug
        end
    end
end

---@class VaultWikilink: VaultObject
---@field data VaultWikilink.data
local Wikilink = Object("VaultWikilink")

--- Create a new Wikilink object.
---@param this VaultWikilink.data.partial|VaultWikilink.data.raw
function Wikilink:init(this)
    if not this then
        error("Missing `this` argument: VaultWikilink.data")
    end
    if type(this) == "string" then
        this = { raw = this }
    end
    self.data = WikilinkData(this)
end

function Wikilink:__tostring()
    return self.data.raw
end

---@alias VaultWikilink.constructor fun(raw_link: string): VaultWikilink
---@type VaultWikilink|VaultWikilink.constructor
local VaultWikilink = Wikilink

return VaultWikilink
