local Object = require("vault.core.object")
local state = require("vault.core.state")
local function scanner()
    return require("vault.scanner")
end

--- A partial wikilink that might not contain full markdown syntax.
--- @alias vault.Wikilink.Data.partial string

--- The raw link as it appears in the note. e.g. [[foo/bar/buzz|alias#heading]]
--- @alias vault.Wikilink.Data.raw string

--- Whether the link is an embedded file link. e.g. ![[foo/bar/buzz|alias#heading]]
--- @alias vault.Wikilink.Data.embedded boolean

--- The slug of the link. e.g. [[foo/bar/buzz|alias#heading]] -> foo/bar/buzz
--- @alias vault.Wikilink.Data.slug vault.slug

--- The stem (tail) of the link. e.g. [[foo/bar/buzz|alias#heading]] -> buzz
--- @alias vault.Wikilink.Data.stem vault.stem

--- The number of times the link appears in the note.
--- @alias vault.Wikilink.Data.count integer

--- The alias of the link. e.g. [[foo/bar/buzz|alias#heading]] -> alias
--- @alias vault.Wikilink.Data.alias string

--- All aliases used with that wikilink.
--- e.g. [[foo/bar/buzz|alias#heading]] -> {["buzz"] = true, ["foo/bar/buzz"] = true, ["alias"] = true}
--- @alias vault.Wikilink.Data.aliases table<string, true>

--- Map from source note slug to an empty table (presence sentinel).
--- @alias vault.Sources.map table<vault.slug, table>

--- Input table accepted by WikilinkData:init.
--- @class vault.Wikilink.Data.InitArgs
--- @field raw string The wikilink text (may include [[ ]] or just inner content).
--- @field embedded? boolean Override for embedded detection.
--- @field sources? vault.Sources.map Pre-populated sources map.
--- @field aliases? table<string, true> Pre-populated aliases.
--- @field count? integer Pre-populated occurrence count.
--- @field suggestions? table Pre-populated suggestions.
--- @field variants? table<string, true> Pre-populated variants.
--- @field target? vault.slug Resolved target slug (skips auto-resolution when provided).

--- @class vault.Wikilink.Data: vault.Object
--- @description Core data structure representing a wikilink in a vault note.
--- @field raw string The content inside [[ ]] without the brackets.
--- @field embedded boolean Indicates if this is an embedded media link.
--- @field slug vault.slug Unique identifier path for the linked note (no # or |).
--- @field stem vault.stem Last path component of the slug (e.g. "buzz" for "foo/bar/buzz").
--- @field display string Display text: alias if present, otherwise stem.
--- @field heading? string Heading/section reference after #.
--- @field section? string Legacy alias for heading (backward compat).
--- @field count integer Number of occurrences of this link in its note.
--- @field alias? vault.Wikilink.Data.alias Optional display text override.
--- @field aliases table<string, true> Set of all valid display names.
--- @field sources vault.Sources.map References to source notes containing this link.
--- @field target? vault.slug The resolved target note slug (nil if unresolved).
--- @field variants table<string, true> Alternative slug/stem forms of the link.
--- @field suggestions table Candidate target suggestions for unresolved links.
--- ```lua
--- assert(wikilink_data.raw == "foo/bar/buzz|alias#heading") -- Content inside [[ ]]
--- assert(wikilink_data.slug == "foo/bar/buzz") -- Path part (no # or |)
--- assert(wikilink_data.stem == "buzz") -- Last component.
--- assert(wikilink_data.display == "alias") -- Alias if present, else stem.
--- assert(wikilink_data.heading == "heading") -- Heading after #.
--- assert(wikilink_data.aliases == {["buzz"] = true, ["foo/bar/buzz"] = true, ["alias"] = true})
--- ```
local WikilinkData = Object("VaultWikilinkData")

--- Strip [[ ]] brackets from a wikilink string and return the inner content.
--- Also handles embedded links (![[...]]).
--- @private
--- @param input string Raw wikilink string (may include ![[...]] or [[...]])
--- @return string content The content inside brackets (without [[ ]] or ![[ ]])
--- @return boolean embedded Whether this is an embedded link
local function strip_brackets(input)
    ---@type boolean
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

--- Check whether a wikilink slug looks like a plausible Obsidian note name.
--- Real note names are alphanumeric with spaces, hyphens, underscores, dots,
--- slashes (for paths), and unicode. Code artifacts contain characters like
--- $, %, (, ), ", ', +, *, {, }, =, ;, >, <, .., etc.
--- @private
--- @param slug string The candidate slug to validate.
--- @return boolean valid `true` when slug is a plausible Obsidian note name.
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

--- Validate that the inner bracket content is a plausible wikilink.
--- @private
--- @param content string The stripped content (no [[ ]] brackets).
--- @return boolean valid `true` when content passes all validation rules.
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
    ---@type string|nil
    local slug_part = content:match("^([^#|]*)")
    if not slug_part or slug_part:match("^%s*$") then
        return false
    end
    -- Validate slug looks like a real note name
    if not is_valid_slug(slug_part) then
        return false
    end
    return true
end

--- Initialise a WikilinkData instance from a raw or partially-parsed table.
--- @param this vault.Wikilink.Data.InitArgs
--- @return nil
function WikilinkData:init(this)
    if not this then
        error("Invalid wikilink: missing input")
    elseif not this.raw then
        error("Invalid wikilink: missing 'raw' field")
    end

    local content, embedded = strip_brackets(this.raw)
    self.embedded = embedded or this.embedded or false

    -- Validate
    if not is_valid_content(content) then
        error("Invalid wikilink content: " .. tostring(this.raw):sub(1, 80))
    end

    -- Store raw content (inside brackets, without [[ ]])
    self.raw = content

    -- Parse components: slug#heading|alias
    self.slug = content:match("([^#|]+)")
    if not self.slug or self.slug == "" then
        error("Invalid wikilink: could not extract slug from: " .. tostring(content):sub(1, 80))
    end

    self.heading = content:match("#([^|]+)")
    self.section = self.heading -- backward compat
    self.alias = content:match("|(.+)$")

    ---@type vault.Sources.map
    self.sources = this.sources or {}
    self.stem = self.slug:match("([^/]+)$") or self.slug
    self.display = self.alias or self.stem

    ---@type table<string, true>
    self.aliases = this.aliases or {}
    self.aliases[self.stem] = true
    if self.alias then
        self.aliases[self.alias] = true
    end

    self.count = this.count or 1
    self.suggestions = this.suggestions or {}

    ---@type table<string, true>
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
        --- @type vault.Notes.Data.slugs
        local slugs = state.get_global_key("cache.notes.slugs") or scanner().slugs()

        if slugs[self.slug] then
            -- Exact slug match
            self.target = self.slug
        else
            -- Basename resolution: build/use a cached basename → slug index
            --- @type table<string, vault.slug>|nil
            local basename_index = state.get_global_key("cache.notes.basename_index")
            if not basename_index then
                ---@type table<string, vault.slug>
                basename_index = {}
                for note_slug, _ in pairs(slugs) do
                    local base = note_slug:match("([^/]+)$") or note_slug
                    if not basename_index[base] then
                        basename_index[base] = note_slug
                    end
                    -- Also index the lowercased version for case-insensitive fallback
                    local base_lower = base:lower()
                    if not basename_index[base_lower] then
                        basename_index[base_lower] = note_slug
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

--- Initialise a Wikilink from a raw link string or a partial data table.
---
--- Accepted forms:
--- - `"[[foo/bar]]"` — standard wikilink with brackets
--- - `"![[foo/bar]]"` — embedded wikilink
--- - `"foo/bar"` — raw inner content (used by parser extracting inner text)
--- - `{ raw = "[[foo/bar]]", sources = {...}, ... }` — pre-parsed data table
---
--- @param this vault.Wikilink.Data.raw | vault.Wikilink.Data.partial | vault.Wikilink.Data.InitArgs
--- @return nil
function Wikilink:init(this)
    local input_repr = type(this) == "string" and this:sub(1, 80) or type(this)
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
            error("Invalid wikilink format")
        else
            -- Normal [[...]] form
            -- Check for multiple closing brackets: "extra]]brackets]]"
            local inner = s:sub(3, -3)
            if inner == "" or inner == "|" or inner == "#" then
                error("Invalid wikilink format")
            end
            if inner:find("%]%]") then
                error("Invalid wikilink format")
            end
            this = { raw = s }
        end
    end

    self.data = WikilinkData(this)
end

--- Convert wikilink back to its canonical string representation.
--- @return string wikilink_string e.g. `"[[foo/bar#heading|alias]]"`
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

--- Return whether this wikilink resolves to an existing note in the vault.
--- Resolution is based on the scanner cache; for disk-level certainty use
--- `Wikilink:is_resolved_on_disk()`.
--- @nodiscard
--- @return boolean resolved `true` when `data.target` is non-nil.
function Wikilink:is_resolved()
    return self.data.target ~= nil
end

--- Return the parent directory path of the wikilink slug.
--- For `"parent/child/note"` returns `"parent/child"`.
--- For a top-level slug like `"note"` (no parent) returns `nil`.
--- @nodiscard
--- @return string|nil parent_path The parent path, or nil if no parent exists.
function Wikilink:get_parent_path()
    local parent = self.data.slug:match("(.+)/[^/]+$")
    return parent
end

--- Extract all valid wikilinks from a block of text.
--- @param text string The text to search for wikilinks.
--- @return vault.Wikilink[] wikilinks List of successfully-parsed Wikilink objects.
function Wikilink.extract_from_text(text)
    ---@type vault.Wikilink[]
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

--- Return whether this wikilink resolves to a readable file on disk.
--- More reliable than `Wikilink:is_resolved()`, which only checks the scanner cache.
--- @nodiscard
--- @return boolean readable `true` when the target slug maps to a readable file.
function Wikilink:is_resolved_on_disk()
    local target_slug = self.data.target
    if not target_slug or target_slug == "" then
        return false
    end
    local utils = require("vault.utils")
    local abs_path = utils.slug_to_path(target_slug)
    return vim.fn.filereadable(abs_path) == 1
end

--- Result shape returned by `Wikilink:rewrite_preview`.
--- @class vault.Wikilink.RewritePreview
--- @field count integer Number of source files that contain the old slug.
--- @field affected string[] Slugs of source notes that would be modified.

--- Compute which source files would be affected by a slug rewrite (dry run).
--- Does NOT modify any files.
--- @nodiscard
--- @param new_slug string The new slug to check against.
--- @return integer count Number of source files that contain the old slug.
--- @return string[] affected List of source slugs that would be modified.
function Wikilink:rewrite_preview(new_slug)
    local old_slug = self.data.slug or ""
    if old_slug == "" or old_slug == new_slug then
        return 0, {}
    end

    local utils = require("vault.utils")
    ---@type vault.Sources.map
    local sources = self.data.sources or {}

    local old_stem = self.data.stem or old_slug:match("([^/]+)$") or old_slug
    ---@type table<string, true>
    local old_patterns = {}
    for _, pat in ipairs({ old_slug, old_stem }) do
        old_patterns[pat] = true
    end

    local count = 0
    ---@type string[]
    local affected = {}
    for source_slug, _ in pairs(sources) do
        local source_path = utils.slug_to_path(source_slug)
        if vim.fn.filereadable(source_path) == 1 then
            local lines = vim.fn.readfile(source_path)
            for _, line in ipairs(lines) do
                local found = false
                for old_pat, _ in pairs(old_patterns) do
                    local escaped = old_pat:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
                    if line:find("%[%[" .. escaped) then
                        found = true
                        break
                    end
                end
                if found then
                    count = count + 1
                    affected[#affected + 1] = source_slug
                    break
                end
            end
        end
    end

    return count, affected
end

--- Rewrite all occurrences of this wikilink's slug to `new_slug` across source files.
--- Replaces both the full-slug form (`[[slug]]`) and the stem-only form (`[[stem]]`).
--- @param new_slug string The new slug to replace the old one with.
--- @return integer patched Number of source files that were modified.
function Wikilink:rewrite(new_slug)
    local old_slug = self.data.slug or ""
    if old_slug == "" or old_slug == new_slug then
        return 0
    end

    local utils = require("vault.utils")
    ---@type vault.Sources.map
    local sources = self.data.sources or {}
    local patched = 0

    -- Build all pattern variants to replace (stem and full slug)
    local old_stem = self.data.stem or old_slug:match("([^/]+)$") or old_slug
    ---@type table<string, true>
    local old_patterns = {}
    for _, pat in ipairs({ old_slug, old_stem }) do
        old_patterns[pat] = true
    end

    for source_slug, _ in pairs(sources) do
        local source_path = utils.slug_to_path(source_slug)
        if vim.fn.filereadable(source_path) == 1 then
            local lines = vim.fn.readfile(source_path)
            local changed = false
            for i, line in ipairs(lines) do
                local new_line = line
                for old_pat, _ in pairs(old_patterns) do
                    local escaped = old_pat:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
                    new_line =
                        new_line:gsub("%[%[" .. escaped .. "(%]%])", "[[" .. new_slug .. "%1")
                    new_line =
                        new_line:gsub("%[%[" .. escaped .. "([#|])", "[[" .. new_slug .. "%1")
                end
                if new_line ~= line then
                    lines[i] = new_line
                    changed = true
                end
            end
            if changed then
                vim.fn.writefile(lines, source_path)
                patched = patched + 1
            end
        end
    end

    return patched
end

--- Create a target note for an unresolved wikilink.
--- The note is written to the path derived from `self.data.slug`.
--- @return vault.Note note The newly created note object.
function Wikilink:create_target()
    local Note = require("vault.notes.note")
    local path = require("vault.notes.paths").for_slug(self.data.slug)
    local note = Note(path)
    note:write(path)
    return note
end

--- Expose slug validation for use by other modules (e.g. scanner filtering).
--- @param slug string Candidate slug string.
--- @return boolean valid `true` when the slug is a plausible Obsidian note name.
Wikilink.is_valid_slug = is_valid_slug

--- Constructor type alias for Wikilink.
--- @alias vault.Wikilink.constructor fun(raw_link: vault.Wikilink.Data.raw|vault.Wikilink.Data.partial|vault.Wikilink.Data.InitArgs): vault.Wikilink

--- @type vault.Wikilink|vault.Wikilink.constructor
local M = Wikilink

state.set_global_key("class.vault.Wikilink", M)
return M
