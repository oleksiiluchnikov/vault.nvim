local state = require("vault.core.state")
--- @type vault.Config|vault.Config.options
local config = require("vault.config")
--- @type vault.Tag.constructor|vault.Tag
-- local Tag = state.get_global_key("class.vault.Tag") or require("vault.tags.tag")

local Wikilink = require("vault.wikilinks.wikilink")
local utils = require("vault.utils")
--- The line number in the note.
--- @alias vault.lnum integer

--- Path without root directory and extension
--- ```lua
--- "dir/subdir/stem"
--- ```
--- @alias vault.slug string

--- Absolute path to the note
--- ```lua
--- "/home/user/vault/dir/subdir/stem.md"
--- ```
--- @alias vault.path string

--- "stem" is the note filename without extension
--- ```lua
--- local utils = require("vault.utils")
--- local filename = "foo.md"
--- print(utils.filename_to_slug(filename)) -- foo
--- ```
--- @alias vault.stem string

--- |VaultProperty|
--- @alias vault.Note.data.properties vault.Property[]

--- Full text of the note
--- @alias vault.Note.data.content string

--- Text of the note excluding |vault.Note.data.frontmatter|.
--- @alias vault.Note.data.body string

--- Markdown heading of the |vault.Note|
--- @alias vault.Note.data.heading {level: integer, text: string}

--- List of |vault.Note.data.heading|
--- @alias vault.Note.data.headings table<vault.lnum, vault.Note.data.heading>

--- @alias vault.Note.data.list table

--- @alias vault.Note.data.field {line:{ row: vault.lnum, col: {start: integer, end: integer}, text: string}, data: table<string, any>} - A key in the note.

--- @alias VaultNoteDataString
--- | '"path"' - The absolute path to the note.
--- | '"relpath"' - The relative path to the root directory of the note.
--- | '"slug"' - The slug of the note. E.g. "Project/notename".
--- | '"basename"' - The basename of the note.
--- | '"stem"' - The stem(name without extension) of the note.
--- | '"content"' - The content of the note.
--- | '"body"' - The body of the note. (content without frontmatter)
--- | '"title"' - The title of the note. (e.g. "Note")

--- @class vault.Note.Data
--- @field ctime integer
--- @field mtime integer
--- @field path vault.path
--- @field relpath vault.relpath
--- @field slug vault.slug
--- @field stem vault.stem
--- @field content vault.Note.data.content
--- @field body vault.Note.data.body
--- @field title? vault.Note.Title
--- @field frontmatter? vault.Note.Frontmatter
--- @field headings? vault.Note.data.headings - List of headings in the note.
--- @field lists? vault.Note.data.list[] - The lists of the note`s list items.
--- @field tags? vault.Tags.map - The tags of the note.
--- @field properties? vault.Note.data.properties - The properties of the note.
--- @field inlinks? vault.Wikilinks.map - List of inlinks to the note.
--- @field outlinks? vault.Wikilinks.map - List of outlinks from the note.
--- @field dangling_links? vault.Wikilinks.map - List of dangling_links from the note.
--- @field keys? vault.Note.data.keys - The keys of the note.
--- @field type? vault.Note.data.type - The type of the note.
--- @field status? vault.Note.data.status - The status of the note.
--- @field stats table<string, any> - The stats of the note.

local Data = {}

--- @param note_data vault.Note.Data
--- @return vault.path
Data.path = function(note_data)
    local relpath = note_data.relpath
    local path = utils.relpath_to_path(path)
    return path
end

--- @param note_data vault.Note.Data
--- @return string
Data.relpath = function(note_data)
    local path = note_data.path
    local relpath = utils.path_to_relpath(path)
    return relpath
end

--- @param note_data vault.Note.Data
--- @return vault.slug
Data.slug = function(note_data)
    local path = note_data.path
    local slug = utils.path_to_slug(path)
    return slug
end

--- @param note_data vault.Note.Data
--- @return string
Data.basename = function(note_data)
    local path = note_data.path
    local basename = vim.fn.fnamemodify(path, ":t")
    if type(basename) ~= "string" then
        error("Invalid basename: " .. vim.inspect(basename))
    end
    return basename
end

--- @param note_data vault.Note.Data
--- @return string
Data.stem = function(note_data)
    local path = note_data.path
    local basename = note_data.slug
    local stem = vim.fn.fnamemodify(path, ":t:r") or basename:match("(.+)%..+")
    return stem
end

--- @param note_data vault.Note.Data
--- @return string
Data.content = function(note_data)
    local path = note_data.path
    local f, err = io.open(path, "r")

    local content
    if f ~= nil then
        content = f:read("*a")
        f:close()
    end
    return content or ""
end

--- @param note_data vault.Note.Data
--- @return vault.Note.Frontmatter|table
Data.frontmatter = function(note_data)
    local content = note_data.content
    local NoteFrontmatter = require("vault.notes.note.frontmatter")
    if not content:match("^%-%-%-") then
        return {}
    end
    return NoteFrontmatter(content)
end

--- @param note_data vault.Note.Data
--- @return string
Data.body = function(note_data)
    local content = note_data.content
    local frontmatter = note_data.frontmatter
    local body = content
    if frontmatter then
        body = content:sub(#frontmatter.raw + 1) -- TODO: check if it works
    end
    return body
end

--- @param note_data vault.Note.Data
--- @return vault.Note.data.headings
Data.headings = function(note_data)
    -- local body = note_data.body
    local body = [[
    # Heading 1

    Some text

    ## Heading 2

    Some text
    #not-a-heading

    ### Heading 3

    Some text
    ]]
    if not body then
        return {}
    end
    local lines = vim.split(body, "\n")
    local headings = {}
    for i, line in ipairs(lines) do
        local heading_pattern = "^#+%s+.*"
        local heading = {}
        local line_number = i
        if line:match(heading_pattern) then
            heading.line = line
            local hash_count = line:match("^#+"):len()
            heading.level = tonumber(hash_count)
            heading.text = line:match("^#+%s+(.*)")
            headings[line_number] = heading
        end
    end
    return headings
end

--- Return the title of the note.
--- Title is the first `VaultNote.data.headings` or the `VaultNote.data.stem`.
---
--- @param note_data vault.Note.Data
--- @return VaultNote.data.title
Data.title = function(note_data)
    local content = note_data.content
    local title = content:match("#%s*(.*)[\r\n$]") or note_data.stem
    return title
end

--- @param note_data vault.Note.Data
--- @return vault.Tags.map
Data.tags = function(note_data)
    local all_tags = state.get_global_key("tags") or require("vault.tags")()
    local sources = all_tags:sources()
    local note_tags = {}
    if sources[note_data.slug] then
        note_tags = sources[note_data.slug]
    end
    return note_tags
end

--- @alias vault.Note.data.list table<string, vault.lnum> - E.g. { ["- list"] = 1, ["- list"] = 2 }

--- @param note_data vault.Note.Data
--- @return vault.Note.data.list[] - List of "- list-like" lines.
Data.lists = function(note_data)
    --- @type string
    local body = note_data.body
    if not body then
        return {}
    end
    --- @type string
    local list_pattern = "\n-%s(.*)\n\n"
    --- @type vault.Note.data.list
    for list in body:gmatch(list_pattern) do
        if list ~= nil then
            -- TODO: implement
        end
    end

    return {}
end

--- @param note_data vault.Note.Data
--- @return vault.Wikilinks.map
Data.outlinks = function(note_data)
    local slug = note_data.slug
    local content = note_data.content
    if not content then
        return {}
    end
    local wikilink_pattern = "%[%[([^%[%]]-)%]%]"

    --- @type vault.Wikilinks.map
    local outlinks = {}
    for raw_link in content:gmatch(wikilink_pattern) do
        if raw_link == "" then
            goto continue
        end
        local wikilink = Wikilink(raw_link)
        local wikilink_data = wikilink.data

        if not outlinks[wikilink_data.stem] then
            outlinks[wikilink_data.stem] = wikilink
        end

        local data = outlinks[wikilink_data.stem].data

        if not data.sources then
            data.sources = {}
        end

        if not data.sources[slug] then
            data.sources[slug] = {}
        end

        if not data.variants then
            data.variants = {}
        end

        if not data.variants[wikilink_data.slug] then
            data.variants[wikilink_data.slug] = true
        end

        if not data.aliases then
            data.aliases = {}
        end

        if wikilink_data.alias then
            if not data.aliases[wikilink_data.alias] then
                data.aliases[wikilink_data.alias] = true
            end
        end
        ::continue::
    end

    return outlinks
end

--- @param note_data vault.Note.Data
--- @return vault.Wikilinks.map
Data.inlinks = function(note_data)
    local wikilinks = state.get_global_key("wikilinks") or require("vault.wikilinks")()
    --- @type vault.Wikilinks.map
    local wikilinks_resolved = wikilinks:resolved()
    local inlinks = {}
    for _, wikilink in pairs(wikilinks_resolved.map) do
        if wikilink.data.target == note_data.slug then
            for source, _ in pairs(wikilink.data.sources) do
                if not inlinks[source] then
                    inlinks[source] = {}
                end
                -- TODO: check what to put in value.maybe source note?
                table.insert(inlinks[source], wikilink)
            end
        end
    end
    return inlinks
end

Data.dangling_links = function(note_data)
    error("Not implemented: " .. vim.inspect(note_data))
end

--- @alias vault.Note.data.keys table<string, vault.lnum> - E.g. { ["title"] = 1, ["created"] = 2 }

--- @param note_data vault.Note.Data
--- @return vault.Note.data.keys
Data.keys = function(note_data)
    local keys = {}

    -- local frontmatter = note_data.frontmatter
    -- for k, v in pairs(frontmatter.data) do
    --     keys[k] = v
    -- end
    local body_example = [=[
    ---
    title: Note
    created: 2021-01-01
    modified: 2021-01-01
    class: note
    ---
    # Heading 1
    title:: Note
    created:: 2021-01-01

    another:: field, this is not a key. yet-another:: field
    ]=
    ]=]

    local result_examle = {
        [2] = {
            {
                start = 1,
                key = "title",
                value = "Note",
                ["end"] = 11,
            },
        },
        [3] = {
            {
                start = 1,
                key = "created",
                value = "2021-01-01",
                ["end"] = 11,
            },
        },
        [4] = {
            {
                start = 1,
                key = "modified",
                value = "2021-01-01",
                ["end"] = 11,
            },
        },
        [5] = {
            {
                start = 1,
                key = "class",
                value = "note",
                ["end"] = 11,
            },
        },
        [7] = {
            {
                start = 1,
                key = "title",
                value = "Note",
                ["end"] = 11,
            },
        },
        [8] = {
            {
                start = 1,
                key = "created",
                value = "2021-01-01",
                ["end"] = 11,
            },
        },
        [10] = {
            {
                start = 1,
                key = "another",
                value = "field, this is not a key. yet-another:: field",
                ["end"] = 11,
            },
            {
                start = 1,
                key = "yet-another",
                value = "field",
                ["end"] = 11,
            },
        },
    }

    local body = body_example

    local inline_field_pattern = "([A-Za-z%-%_]+)::%s*([^,%s%.]+)"
    local lines = vim.split(body, "\n")
    for line_number, line in ipairs(lines) do
        for key, value in line:gmatch(inline_field_pattern) do
            if key ~= nil then
                local start
                for i = 1, #line do
                    if line:sub(i, i) == key:sub(1, 1) then
                        start = i
                        break
                    end
                end
                local col_end
                for i = start, #line do
                    if line:sub(i, i) == value:sub(-1) then
                        col_end = i
                        break
                    end
                end

                local key = {
                    line = {
                        row = line_number,
                        col = { start, col_end },
                        text = line,
                    },
                    data = {
                        [key] = value,
                    },
                }
                table.insert(keys, key)
            end
        end
    end

    local frontmatter = note_data.frontmatter

    -- compare result with result_examle
    -- print(vim.inspect(keys))
end

--- @alias VaultNoteType table

--- @param note_data vault.Note.Data
--- @return VaultNoteType
Data.type = function(note_data)
    --- local keys = note_data.keys
    --- local type = keys.type
    -- local pattern = config.options.search_pattern.note.type or "%s#class/([A-Za-z0-9_-]+)"
    -- error("Not implemented: " .. vim.inspect(note_data))
end

-- --- Fetch status from the specified path.
-- ---
-- --- @parap path string - The path to the note to fetch status from.
-- --- @param content string - The content of the note.
-- --- @return string? - The status of the note.
-- local function fetch_status(path, content)
--   if not path then
--     return nil
--   end
--   content = content or fetch_content(path)
--   local status
--   local pattern = config.options.search_pattern.status or "%s#status/([A-Za-z0-9_-]+)"
--   local match = content:match(pattern)
--   if not match then
--     return nil
--   end
--   status = match
--   return status
-- end

--- @param note_data vault.Note.Data
--- @return string?
Data.status = function(note_data)
    -- local keys = note_data.keys
    error("Not implemented: " .. vim.inspect(note_data))
    -- return keys.status
end

Data.stats = function(note_data)
    error("Not implemented: " .. vim.inspect(note_data))
end

return Data
