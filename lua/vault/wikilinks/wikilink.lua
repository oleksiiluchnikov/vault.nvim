local Object = require("vault.core.object")
local state = require("vault.core.state")
local function scanner()
    return require("vault.scanner")
end

--- @alias vault.Wikilink.Data.partial string A partial wikilink that might not contain full markdown syntax

--- @description Represents all possible components and metadata for a wikilink in a vault note
--- The raw link as it appears in the note. e.g. [[foo/bar/buzz|alias#heading]]
--- @alias vault.Wikilink.Data.raw string The complete wikilink text as it appears in the source

--- Whether the link is embedded file link. e.g. ![[foo/bar/buzz|alias#heading]]
--- @alias vault.Wikilink.Data.embedded boolean Indicates if this is an embedded file/image link

--- The slug of the link. e.g. [[foo/bar/buzz|alias#heading]] -> foo/bar/buzz
--- @alias vault.Wikilink.Data.slug string The unique identifier path for the linked note

--- The stem (tail) of the link. e.g. [[foo/bar/buzz|alias#heading]] -> buzz
--- @alias vault.Wikilink.Data.stem string The last path component extracted from the slug

--- The number of times the link appears in the note.
--- @alias vault.Wikilink.Data.count number Frequency count of this link's occurrence

--- The aliases of the link. e.g. [[foo/bar/buzz|alias#heading]] -> alias
--- @alias vault.Wikilink.Data.alias string Alternative display text for the link

--- All aliases used with that wikilink. e.g. [[foo/bar/buzz|alias#heading]] -> {["buzz"] = true, ["foo/bar/buzz"] = true, ["alias"] = true}
--- @alias vault.Wikilink.Data.aliases table<string, boolean> Collection of all valid display names for this link

--- @class vault.Wikilink.Data: vault.Object
--- @description Core data structure representing a wikilink in a vault note
--- @field raw string The content inside [[ ]] without the brackets
--- @field embedded boolean Indicates if this is an embedded media link
--- @field slug vault.slug Unique identifier path for the linked note (same as raw without # and |)
--- @field stem vault.stem Last path component of the slug (e.g. "buzz" for "foo/bar/buzz")
--- @field display string Display text: alias if present, otherwise stem
--- @field heading? string Heading/section reference after #
--- @field count number Number of occurrences in the note
--- @field alias vault.Wikilink.Data.alias Optional display text override
--- @field aliases vault.map Set of all valid display names
--- @field section? string Legacy alias for heading
--- @field sources vault.Sources.map References to source notes containing this link
--- @field target vault.Note The resolved target note object
--- @field variants vault.map Alternative forms of the link
--- ```lua
--- assert(wikilink.raw == "foo/bar/buzz|alias#heading") -- Content inside [[ ]]
--- assert(wikilink.slug == "foo/bar/buzz") -- Path part (no # or |)
--- assert(wikilink.stem == "buzz") -- Last component. Must be unique
--- assert(wikilink.display == "alias") -- Alias if present, else stem
--- assert(wikilink.heading == "heading") -- Heading after #
--- assert(wikilink.aliases == {["buzz"] = true, ["foo/bar/buzz"] = true, ["alias"] = true})
--- ```
local WikilinkData = Object("VaultWikilink")


--- Strip [[ ]] brackets from a wikilink string and return the inner content.
--- Also handles embedded links (![[...]]).
--- @param input string
--- @return string content The content inside brackets
--- @return boolean embedded Whether this is an embedded link
local function strip_brackets(input)
    local embedded = false
    local s = input

    -- Handle embedded prefix
    if s:find("^!") then
        s = s:sub(2)
        embedded = true
    end

    -- Strip [[ and ]]
    if s:sub(1, 2) == "[[" and s:sub(-2) == "]]" then
        s = s:sub(3, -3)
    elseif s:sub(1, 2) == "[[" then
        s = s:sub(3)
    elseif s:sub(-2) == "]]" then
        s = s:sub(1, -3)
    end

    return s, embedded
end


--- Validate that the content inside brackets is a valid wikilink.
--- @param content string The stripped content (no brackets)
--- @return boolean
--- Check whether a wikilink slug looks like a plausible Obsidian note name.
--- Real note names are alphanumeric with spaces, hyphens, underscores, dots,
--- slashes (for paths), and unicode. Code artifacts contain characters like
--- $, %, (, ), ", ', +, *, {, }, =, ;, >, <, .., etc.
--- @param slug string
--- @return boolean
local function is_valid_slug(slug)
    if not slug or slug == "" then
        return false
    end
    -- Reject strings with code/shell/regex artifacts
    -- These characters never appear in real Obsidian note filenames
    if slug:find("[%$%%%(%)%{%}%+%*=;<>\"'`\\]") then
        return false
    end
    -- Reject Lua string concatenation patterns: " .. " (space-dot-dot-space)
    -- But allow relative paths like "../foo" (dot-dot-slash)
    if slug:find(" %.%. ") or slug:find('" %.%. ') then
        return false
    end
    -- Reject strings that are only punctuation/digits/commas (e.g. "0, 0", "...", "%s")
    if slug:match("^[%d%p%s]+$") then
        return false
    end
    -- Reject pipe-only or hash-only (degenerate)
    if slug:match("^[#|]+$") then
        return false
    end
    -- Must have at least one letter (unicode or ASCII) — real note names always do
    if not slug:find("%a") and not slug:find("[\128-\255]") then
        return false
    end
    return true
end

local function is_valid_content(content)
    if not content or content == "" then
        return false
    end
    -- Pure | or # with nothing else
    if content:match("^[#|]+$") then
        return false
    end
    -- Reject bash-style [[ -flag ... ]] — they always have leading/trailing whitespace.
    -- Real Obsidian wikilinks never have leading or trailing whitespace inside brackets.
    if content:match("^%s") or content:match("%s$") then
        return false
    end
    -- Must have at least one non-whitespace character in the slug portion
    local slug = content:match("^([^#|]*)")
    if not slug or slug:match("^%s*$") then
        return false
    end
    -- Validate slug looks like a real note name
    if not is_valid_slug(slug) then
        return false
    end
    return true
end


--- @param this vault.Wikilink.Data|{raw: string}
function WikilinkData:init(this)
    if not this then
        error("Invalid wikilink format")
    elseif not this.raw then
        error("Invalid wikilink format")
    end

    local content, embedded = strip_brackets(this.raw)
    self.embedded = embedded or this.embedded or false

    -- Validate
    if not is_valid_content(content) then
        error("Invalid wikilink format")
    end

    -- Store raw content (inside brackets, without [[ ]])
    self.raw = content

    -- Parse components: slug#heading|alias
    self.slug = content:match("([^#|]+)")
    if not self.slug or self.slug == "" then
        error("Invalid wikilink format")
    end

    self.heading = content:match("#([^|]+)")
    self.section = self.heading -- backward compat
    self.alias = content:match("|(.+)$")

    self.sources = this.sources
    self.stem = self.slug:match("([^/]+)$") or self.slug
    self.display = self.alias or self.stem

    self.aliases = this.aliases or {}
    self.aliases[self.stem] = true
    if self.alias then
        self.aliases[self.alias] = true
    end

    self.count = this.count or 1
    self.suggestions = this.suggestions or {}

    self.variants = this.variants or {}
    self.variants[self.stem] = true
    if self.stem ~= self.slug then
        self.variants[self.slug] = true
    end

    -- Resolve target: match wikilink slug to an existing note.
    -- Obsidian resolution order:
    --   1. Exact slug match (e.g. [[Notes/foo]] → "Notes/foo")
    --   2. Basename match (e.g. [[foo]] → first slug ending with "/foo" or exactly "foo")
    if this.target then
        self.target = this.target
    else
        --- @type vault.Notes.data.slugs
        local slugs = state.get_global_key("cache.notes.slugs") or scanner().slugs()

        if slugs[self.slug] then
            -- Exact slug match
            self.target = self.slug
        else
            -- Basename resolution: build/use a cached basename → slug index
            local basename_index = state.get_global_key("cache.notes.basename_index")
            if not basename_index then
                basename_index = {}
                for slug, _ in pairs(slugs) do
                    local base = slug:match("([^/]+)$") or slug
                    if not basename_index[base] then
                        basename_index[base] = slug
                    end
                    -- Also index the lowercased version for case-insensitive fallback
                    local base_lower = base:lower()
                    if not basename_index[base_lower] then
                        basename_index[base_lower] = slug
                    end
                end
                state.set_global_key("cache.notes.basename_index", basename_index)
            end

            -- Try exact basename match, then case-insensitive
            local resolved = basename_index[self.slug] or basename_index[self.slug:lower()]
            if resolved then
                self.target = resolved
            end
        end
    end
end


--- @class vault.Wikilink: vault.Object
--- @field data vault.Wikilink.Data
local Wikilink = Object("VaultWikilink")


--- @param this vault.Wikilink.raw|vault.Wikilink.Data.partial|table
function Wikilink:init(this)
    if not this or (type(this) == "string" and this == "") then
        error("Invalid wikilink format")
    end

    if type(this) == "string" then
        -- Validate that the string looks like a wikilink or raw content
        local s = this
        if s:find("^!") then
            s = s:sub(2)
        end

        -- Must be [[...]] or raw content
        local has_open = s:sub(1, 2) == "[["
        local has_close = s:sub(-2) == "]]"

        if not has_open and not has_close then
            -- Bare string — could be single brackets or raw wikilink content
            if s:match("%[") or s:match("%]") then
                -- Contains mismatched brackets like "[single bracket]"
                error("Invalid wikilink format")
            end
            -- Treat as raw wikilink content (e.g. from parser extracting inner text)
            this = { raw = s }
        elseif has_open and not has_close then
            error("Invalid wikilink format")
        elseif not has_open and has_close then
            -- e.g. "extra]]brackets]]" — malformed
            error("Invalid wikilink format")
        else
            -- Normal [[...]] form
            -- Check for multiple closing brackets: "extra]]brackets]]"
            local inner = s:sub(3, -3)
            if inner:find("%]%]") then
                error("Invalid wikilink format")
            end
            this = { raw = s }
        end
    end

    self.data = WikilinkData(this)
end


--- Convert wikilink back to string representation.
--- @return string
function Wikilink:__tostring()
    local result = self.data.slug
    if self.data.heading then
        result = result .. "#" .. self.data.heading
    end
    if self.data.alias then
        result = result .. "|" .. self.data.alias
    end
    return "[[" .. result .. "]]"
end


--- Check if this wikilink resolves to an existing note in the vault.
--- @return boolean
function Wikilink:is_resolved()
    return self.data.target ~= nil
end


--- Get the parent path of the wikilink slug.
--- For "parent/child/note" returns "parent/child".
--- For "note" (no parent) returns nil.
--- @return string|nil
function Wikilink:get_parent_path()
    local parent = self.data.slug:match("(.+)/[^/]+$")
    return parent
end


--- Extract all valid wikilinks from a block of text.
--- @param text string The text to search for wikilinks
--- @return vault.Wikilink[] List of Wikilink objects
function Wikilink.extract_from_text(text)
    local results = {}
    for match in text:gmatch("%[%[(.-)%]%]") do
        if is_valid_content(match) then
            local ok, wl = pcall(Wikilink, "[[" .. match .. "]]")
            if ok then
                results[#results + 1] = wl
            end
        end
    end
    return results
end


--- Expose slug validation for use by other modules (e.g. scanner filtering).
--- @param slug string
--- @return boolean
Wikilink.is_valid_slug = is_valid_slug

--- @alias vault.Wikilink.constructor fun(raw_link: vault.Wikilink.Data.raw|vault.Wikilink.Data.partial)
--- @type vault.Wikilink|vault.Wikilink.constructor
local M = Wikilink

state.set_global_key("class.vault.Wikilink", M)
return M
