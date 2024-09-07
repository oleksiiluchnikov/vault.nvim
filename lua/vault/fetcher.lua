--- @type vault.Config|vault.Config.options
local config = require("vault.config")
--- @type vault.StateManager
local state = require("vault.core.state")
local utils = require("vault.utils")
--- @type Job
local Job = require("plenary.job")

--- @type string
local filetype = config.options.ext:sub(2)

--- @type string
local COMMAND = config.options.search_tool or "rg" -- TODO: Make this configurable.

--- @alias vault.fetcher.ripgrep.entry {type: string, data: vault.fetcher.ripgrep.entry.Data}
--- @alias vault.fetcher.ripgrep.entry.Data {absolute_offset: number, line_number: number, lines: {text: string}, path: {text: string}, submatches: vault.fetcher.ripgrep.entry.Data.submatch[]}
--- @alias vault.fetcher.ripgrep.entry.Data.submatch {match: {text: string}, start: number, end: number}

--- @class vault.fetcher
--- @field notes fun(): vault.Notes.map - Fetches all paths from the vault with ripgrep.
--- @field wikilinks fun(): vault.Wikilinks.map - Fetches all wikilinks from the vault with ripgrep.
--- @field tags fun(): vault.Tags.map - Fetches all tags from the vault with ripgrep.
--- @field tasks fun(): vault.Tasks.map - Fetches all todos from the vault with ripgrep.
--- @field links fun(): vault.Links.map - Fetches all external links from the vault with ripgrep.
--- @field fields fun(): vault.Fields.map - Fetch all the key value pairs from the frontmatter and inline Dataview
--- @field dirs fun(): vault.Dirs.map - Fetch all dirs from the vault with rg.
--- @field slugs fun(): vault.Notes.Data.slugs
--- @field paths fun(): vault.Notes.map - Fetches all paths from the vault with ripgrep.
local Fetcher = {}

--- Executes the ripgrep command.
---
--- @return string[]
local function rg(args)
    local stdout = {}

    Job:new({
        command = COMMAND,
        args = args,

        on_exit = function(j, _, _)
            stdout = j:result()
        end,
    }):sync()

    if not stdout then
        error("Failed to fetch data from the vault.")
    end

    return stdout
end

--- @alias vault.fetcher.ripgrep.line string

--- Converts a JSON line to a match entry.
---
--- This function decodes the JSON line and verifies if it is a match entry.
--- It returns the entry if it is a match and contains submatches, otherwise nil.
---
--- Example:
--- ```lua
--- local line = '{"type":"match","data":{"path":{"text":"path/to/file.md"},"lines":{"text":"line content"},"submatches":[{"match":{"text":"match content"},"start":0,"end":0}]}}'
--- assert(line_to_match_entry(line) ~= nil)
--- ```
--- @param line string: A JSON-encoded string representing a ripgrep line.
--- @return vault.fetcher.ripgrep.entry|nil: The match entry if the line is a match and contains submatches, otherwise nil.
local function line_to_match_entry(line)
    --- @type vault.fetcher.ripgrep.entry
    local entry = vim.fn.json_decode(line)
    if not entry.type == "match" then
        return nil
    elseif not entry.data then
        return nil
    elseif not entry.data.submatches or next(entry.data.submatches) == nil then
        return nil
    end
    return entry
end

--- Fetches all paths from the vault with ripgrep.
--- TODO: Add support for ignore files. that is in the config.options.ignore option.
--- @return table<vault.slug, {path: vault.path, slug: vault.slug, relpath: string, basename: string}>
function Fetcher.paths()
    local args = {
        "-t" .. filetype,
        "--files",
        config.options.root,
    }

    --- @type string[]
    local paths = rg(args)

    --- @type table<vault.slug, {path: vault.path, slug: vault.slug, relpath: string, basename: string}>
    local map = {}
    for _, path in ipairs(paths) do
        local slug = utils.path_to_slug(path)
        if map[slug] then
            goto continue
        end
        map[slug] = {
            path = path,
            slug = slug,
            relpath = utils.path_to_relpath(path),
            basename = utils.path_to_basename(path),
        }
        ::continue::
    end

    state.set_global_key("cache.notes.paths", map)
    return map
end

--- Fetches all slugs from the vault with ripgrep.
--- @return vault.Notes.Data.slugs
function Fetcher.slugs()
    local paths = Fetcher.paths()
    --- @type vault.Notes.data.slugs
    local slugs = {}
    for slug, _ in pairs(paths) do
        slugs[slug] = true
    end

    state.set_global_key("cache.notes.slugs", slugs)
    return slugs
end

--- Fetches all wikilinks from the vault with ripgrep.
---
--- @return vault.Wikilinks.map
function Fetcher.wikilinks()
    --- https://regex101.com/r/T1me3d/2 - Wikilink regex pattern
    local wikilink_pattern =
    [=[^\[\[(?<link>[^\]\|]+)?(\#(?<anchor>[^\]\|]+))?(\|(?<title>[^\]\|]+))?(\|(?<tooltip>[^\]\|]+))?\]\]]=]

    local args = {
        "--json",
        "-t" .. filetype,
        "--no-heading",
        "--only-matching",
        "--pcre2",
        wikilink_pattern,
        config.options.root,
    }
    local stdout = rg(args)

    --- @type vault.Wikilink.constructor|vault.Wikilink
    local Wikilink = state.get_global_key("class.vault.Wikilink")
        or require("vault.wikilinks.wikilink")

    --- @type vault.Wikilinks.map
    local wikilinks_map = {}
    for _, entry in ipairs(stdout) do
        local match = line_to_match_entry(entry)
        if not match then
            goto continue
        end
        for _, submatch in ipairs(match.data.submatches) do
            --- @type vault.Wikilink
            local wikilink = Wikilink(submatch.match.text)

            if not wikilinks_map[wikilink.data.stem] then
                wikilinks_map[wikilink.data.stem] = wikilink
            else
                wikilinks_map[wikilink.data.stem].data.count = wikilinks_map[wikilink.data.stem].data.count
                    + 1
            end

            --- @type vault.Wikilink.Data
            local data = wikilinks_map[wikilink.data.stem].data
            --- @type vault.path
            local path = match.data.path.text
            --- @type vault.slug
            local slug = utils.path_to_slug(path)
            --- @type integer
            local lnum = match.data.line_number

            if submatch.match.text:find("^!") then
                data.embedded = true
            end

            if not data.count then
                data.count = 1
            end

            if not data.sources then
                data.sources = {}
            end

            if not data.sources[slug] then
                data.sources[slug] = {}
            end

            data.sources[slug][lnum] = {
                lnum = lnum,
                line = match.data.lines.text,
                end_lnum = lnum,
                col = submatch.start,
                end_col = submatch["end"],
            }
        end
        ::continue::
    end
    return wikilinks_map
end

--- @class vault.Task
--- @field line string
--- @field status string

--- @class vault.Tasks.map table<string, VaultMap.todos.lines>

--- Fetches all todos from the vault with ripgrep.
---
--- ```lua
--- [path/to/file]
---   [27] = {
---     line = "- [ ] Fix issue with `:VaultMove` it doesn't move buffer to new location with lsp\n",
---     status = "[ ]",
---     text = "Fix issue with `:VaultMove` it doesn't move buffer to new location with lsp",
---     wikilinks = {}
---   },
---   [28] = {
---     line = "- [ ] make a little promotion video for vault.nvim\n",
---     status = "[ ]",
---     text = "make a little promotion video for vault.nvim",
---     wikilinks = {}
---   },
---   [29] = {
---     line = "- [ ] make a twitter account for vault.nvim\n",
---     status = "[ ]",
---     text = "make a twitter account for vault.nvim",
---     wikilinks = {}
---   },
---   [30] = {
---     line = "- [ ] add ability to load [[20231026075435 Explore Telescope Plugin for Neovim]] with notes with X connections",
---     status = "[ ]",
---     wikilinks = {
---       ["[[20231026075435 Explore Telescope Plugin for Neovim]]"] = true
---     }
---   }
--- },
--- ```
--- @return vault.Tasks.map
function Fetcher.tasks()
    local todo_pattern = config.options.search_pattern.task.pcre2
    local args = {
        "--json",
        "-t" .. filetype,
        "--no-heading",
        "--only-matching",
        todo_pattern,
        config.options.root,
    }

    local stdout = rg(args)

    local tasks_map = {}
    for _, entry in ipairs(stdout) do
        local match = line_to_match_entry(entry)
        if not match then
            goto continue
        end

        local line = match.data.lines.text

        for _, submatch in ipairs(match.data.submatches) do
            --- @type vault.Task
            local task = {
                line = line,
                status = submatch.match.text:match("%[.%]"),
                text = line:match("^%s*-%s+%[.%]%s+(.*)%s$"),
                wikilinks = {},
            }
            for wikilink in line:gmatch("%[%[.-]]") do
                task.wikilinks[wikilink] = true
            end

            local path = match.data.path.text
            local slug = utils.path_to_slug(path)
            local line_number = match.data.line_number

            if not tasks_map[slug] then
                tasks_map[slug] = {}
            end

            if not tasks_map[slug][line_number] then
                tasks_map[slug][line_number] = task
            end
        end
        ::continue::
    end
    return tasks_map
end

--- @class vault.Links
--- @field map table<string, VaultMap.links.lines>

--- Fetches all external links from the vault with ripgrep.
---
--- @return vault.Links.map
function Fetcher.links()
    local link_pattern = [[\[(.*?)\]\((.*?)\)]]
    local args = {
        "--json",
        "-t" .. filetype,
        "--no-heading",
        "--only-matching",
        link_pattern,
        config.options.root,
    }

    local stdout = rg(args)

    local links_map = {}
    for _, entry in ipairs(stdout) do
        local match = line_to_match_entry(entry)
        if not match then
            goto continue
        end

        for _, submatch in ipairs(match.data.submatches) do
            local link = {
                line = match.data.lines.text,
                text = submatch.match.text:match("%[(.*)%]%(.*%)"),
                url = submatch.match.text:match("%((.*)%)"),
            }

            local path = match.data.path.text
            local slug = utils.path_to_slug(path)
            local line_number = match.data.line_number

            if not links_map[slug] then
                links_map[slug] = {}
            end

            if not links_map[slug][line_number] then
                links_map[slug][line_number] = link
            end
        end
        ::continue::
    end
    return links_map
end

--- Fetch all the key value pairs from the frontmatter and inline dataview
---
--- @return vault.Fields.map
function Fetcher.fields()
    -- Rust engine regex pattern
    local inline_pattern = [[(\w+::\s*[^,\n\r]+)]]
    local inline_in_brackets_pattern = [=[(\[\w+::\s*[^,\n\r]+\])]=]
    inline_pattern = "(?:" .. inline_pattern .. "|" .. inline_in_brackets_pattern .. ")"

    local args = {
        "--json",
        "-t" .. filetype,
        "--no-heading",
        "--only-matching",
        inline_pattern,
        config.options.root,
    }

    local stdout = rg(args)

    local fields_map = {}
    for _, entry in ipairs(stdout) do
        local match = line_to_match_entry(entry)
        if not match then
            goto continue
        end

        local line = match.data.lines.text

        local path = match.data.path.text
        local slug = utils.path_to_slug(path)
        local line_number = match.data.line_number

        for _, submatch in ipairs(match.data.submatches) do
            local inline_fields = {}
            for inline_field in submatch.match.text:gmatch("%[.-::%s*[^,\n\r]-%]") do
                inline_field = inline_field:sub(2, -2)
                table.insert(inline_fields, inline_field)
            end

            if #inline_fields == 0 then
                table.insert(inline_fields, submatch.match.text)
            end

            local prev_finish = 0
            for i, inline_field in ipairs(inline_fields) do
                local key = inline_field:match("^(.-)::.*$")
                local value = inline_field:match("::%s*(.-)$")

                local data = {
                    key = key,
                    value = value,
                    count = 1,
                }

                local start = submatch.start
                local finish = submatch["end"]
                if i == 1 then
                    prev_finish = tonumber(start) + 3 + #inline_field
                end
                if i > 1 then
                    -- remove first part of the line until the previous finish
                    local trimmed_line = line
                    -- for _ = 1, prev_finish do
                    --     -- print("line", trimmed_line)
                    --     trimmed_line = trimmed_line:gsub("^.", "")
                    -- end
                    trimmed_line = trimmed_line:sub(prev_finish + 1)
                    start = prev_finish + 2
                    finish = start + #inline_field
                    prev_finish = prev_finish + 3 + #inline_field
                end

                local pos = {
                    start,
                    finish,
                }

                local source = {
                    key = key,
                    value = value,
                    pos = pos,
                    line = line,
                    path = path,
                    raw = submatch.match.text,
                }

                if not key or not value then
                    goto continue
                end

                if not fields_map[key] then
                    fields_map[key] = {}
                end
                if not fields_map[key][value] then
                    fields_map[key][value] = data
                else
                    fields_map[key][value].count = fields_map[key][value].count + 1
                end
                if not fields_map[key][value].sources then
                    fields_map[key][value].sources = {}
                end
                if not fields_map[key][value].sources[slug] then
                    fields_map[key][value].sources[slug] = {}
                end
                if not fields_map[key][value].sources[slug][line_number] then
                    fields_map[key][value].sources[slug][line_number] = {}
                end
                -- if on the same line there are multiple inline fields with the same key and value
                -- then we need to add the li
                if not fields_map[key][value].sources[slug][line_number][submatch.start] then
                    fields_map[key][value].sources[slug][line_number][submatch.start] = {}
                end
                fields_map[key][value].sources[slug][line_number][submatch.start] = source
            end
        end
        ::continue::
    end
    return fields_map
end

--- @alias vault.Dirs.map table<string, boolean>

--- Fetch all directories from the vault using ripgrep (rg).
--- @return vault.Dirs.map
function Fetcher.dirs()
    local args = {
        "--hidden", -- Include hidden files and directories
        "--files",  -- Only print file paths
        "--glob",   -- Use glob pattern matching
        "![.]*",    -- Exclude all files and directories starting with a dot
        config.options.root,   -- Root directory to search
    }

    local stdout = rg(args) -- Execute ripgrep with the provided arguments

    --- @type vault.Dirs.map
    local dirs_map = {}

    for _, entry in ipairs(stdout) do
        if not entry:find("/") then -- Skip if the entry doesn't contain a directory separator
            goto continue
        end

        -- Extract the directory path relative to the root directory
        entry = vim.fn.fnamemodify(entry, ":p:h"):sub(#config.options.root + 2)

        if dirs_map[entry] or entry == "" then -- Skip if the directory is already in the map or if it's an empty string
            goto continue
        end

        dirs_map[entry] = true -- Add the directory to the map
        ::continue::
    end

    return dirs_map
end

--- Examples:
--- ```lua
--- assert(is_valid_key("foo_bar-123") == true)
--- assert(is_valid_key("invalid!key") == false)
--- assert(is_valid_key("123") == true)
--- ```
--- @param key string The key to validate
--- @return boolean is_valid True if the key is valid, false otherwise
local function is_valid_key(key)
    local is_quoted = key:match("^\".*\"$")
    if not is_quoted then
        -- Any character except: -
        return key:match("^[%w_%-]+$") ~= nil
    end
    return false
end

--- @alias FrontmatterLine string - A line from the frontmatter.

--- @param line FrontmatterLine
--- ```lua
-- local key, value = parse_frontmatter_line("title: My Title")
-- assert(key == "title" and value == "My Title")
--
-- key, value = parse_frontmatter_line("invalid line")
-- assert(key == nil and value == nil)
--- ```
--- @return string? key
--- @return string? value
local function parse_frontmatter_line(line)
    --- @type string?, string?
    local key, value = line:match("^(%S+):%s*(.*)$")
    if not key then
        return nil
    end
    if not is_valid_key(key) then
        return nil
    end
    return key, value
end

--- @param key string
--- @return boolean
local function is_valid_key(key)
    return key:match("^[%w_%-]+$") ~= nil
end

--- Fetch all obsidian properties from the vault.
---
--- TODO: Since we look for the properties in the frontmatter, we should workaround to look at the fronmatter of the note only.
--- @return vault.Properties.map
function Fetcher.properties()
    local frontmatter_pattern = [[(?s)^---\n(.*?)\n---]]
    local args = {
        "--json",
        "-t" .. filetype,
        "--no-heading",
        "--only-matching",
        "-U",
        "--pcre2",
        frontmatter_pattern,
        config.options.root,
    }
    local stdout = rg(args)

    local properties_map = {}
    --- @type vault.Tag.constructor|vault.Tag
    local Property = state.get_global_key("class.vault.Property") or require("vault.properties.property")
    local PropertyValue = state.get_global_key("class.vault.Property.Value") or
        require("vault.properties.property.value")


    -- Try use yq instead of rg
    for _, entry in ipairs(stdout) do
        local match = line_to_match_entry(entry)
        if not match then
            goto continue
        end

        local text = match.data.lines.text
        local path = match.data.path.text

        --- @type table<string, string>
        local frontmatter = {}
        local lines = vim.fn.split(text, "\n")
        table.remove(lines, 1) -- Remove the first line containing "--- "

        local frontmatter_lines = {}
        for i, line in ipairs(lines) do
            if line:match("^%-%-%-") then
                break
            end
            frontmatter_lines[i] = line
        end

        local current_key = ""
        local occurences = {}
        for i, line in ipairs(frontmatter_lines) do
            if line:match("^%s+") then
                if current_key ~= "" then
                    frontmatter[current_key] = (frontmatter[current_key] or "") .. "\n" .. line:gsub("^%s+%-%s*", "")
                end
            else
                local key, value = parse_frontmatter_line(line)
                if key and value then
                    frontmatter[key] = value
                    current_key = key
                    --- @type vault.source.occurence
                    occurences[key] = {
                        lnum = i,
                        end_lnum = i,
                        line = line,
                        col = 1,
                        end_col = key:len(),
                    }
                end
            end
        end

        for k, v in pairs(frontmatter) do
            --- @type vault.Property.Data.name
            local property_name = k

            local slug = utils.path_to_slug(path)
            --- @type vault.source.occurence
            local occurence = occurences[k]
            if not properties_map[property_name] then
                -- Create the property
                --- @type vault.Property.data
                local property_data = {}
                property_data.name = property_name
                property_data.sources = {}
                property_data.sources[slug] = {}
                property_data.count = 1

                table.insert(property_data.sources[slug], occurence.lnum, occurence)
                -- property_data.sources[path][
                --- @type vault.Property.Data.values
                property_data.values = {}

                local property = Property(property_data)
                properties_map[property_name] = property
            else
                properties_map[property_name].data.sources[slug] = {}
                table.insert(properties_map[property_name].data.sources[slug], occurence.lnum, occurence)
                properties_map[property_name].data.count = properties_map[property_name].data.count + 1
            end

            -- local indent = submatch.match.text:match("^%s+")
            local indent = 0

            local values_raw = vim.split(v, "\n")
            local values = {}
            if #values_raw > 1 then
                if values_raw[1] == "" then
                    table.remove(values_raw, 1)
                end
                -- delete the "- " from the beginning
                values = vim.tbl_map(function(value)
                    if value:match("^%s+") then
                        indent = indent + value:match("^%s+"):len()
                    end
                    value = value:gsub("^%s*-%s+", "")
                    if k == "tags" then
                        return value:gsub("^%s*[\"'](.-)[\"']%s*$", "%1")
                    end
                    return value

                end, values_raw)
            else
                values = vim.tbl_map(function(value)
                    return value
                end, values_raw)
            end

            for i, value_name in ipairs(values) do
                local value_occurence = {
                    lnum = occurence.lnum + i, -- If value is a list, then it is next
                    end_lnum = occurence.end_lnum + i,
                    line = values_raw[i],
                    col = occurence.col + indent,
                    end_col = occurence.end_col,
                }
                --- @type vault.Property.Value|nil
                local value = properties_map[property_name].data.values[value_name]
                if not value then
                    local value_type = "text"
                    if vim.tbl_count(values_raw) > 1 then
                        value_type = "list"
                    end
                    --- @type vault.Property.Value.data
                    --- @diagnostic disable-next-line: missing-fields
                    local value_data = {
                        name = value_name,
                        sources = {
                            [slug] = {
                                [value_occurence.lnum] = value_occurence,
                            },
                        },
                        properties = {
                            [property_name] = properties_map[property_name],
                        },
                        count = 1,
                        type = value_type,
                    }

                    value = PropertyValue(value_data)
                    -- properties_map[property_name]:add_value(value)
                    properties_map[property_name].data.values[value_data.name] = value
                else
                    -- properties_map[property_name]:add_value(value)
                    if not value.data.sources[slug] then
                        value.data.sources[slug] = {}
                    end
                    if not value.data.sources[slug][value_occurence.lnum] then
                        value.data.sources[slug][value_occurence.lnum] = value_occurence
                    end
                    value.data.count = value.data.count + 1
                    -- if not value.data.properties[property_name] then
                    --     value.data.properties[property_name] =
                    --         properties_map[property_name]
                    -- end
                    -- TODO: Add the occurence
                end
            end
        end
        ::continue::
    end

    return properties_map
end

local function fetch_tags_from_frontmatter()
    local tags_from_frontmatter_map = {}
    local tags_from_properties = Fetcher.properties()[config.options.frontmatter.keys.tags].data.values
    for _, tag_from_frontmatter in pairs(tags_from_properties) do
        if tag_from_frontmatter.data.name == "" then
            goto continue
        end
        -- unqoute the name if it is quoted
        tag_from_frontmatter.data.name = tag_from_frontmatter.data.name:gsub("^['\"](.-)['\"]$", "%1")
        local tag_data = {
            name = tag_from_frontmatter.data.name,
            sources = tag_from_frontmatter.data.sources,
            -- where = tag.data.where, -- "frontmatter" | "body"
        }
        tags_from_frontmatter_map[tag_from_frontmatter.data.name] = tag_data
        ::continue::
    end
    return tags_from_frontmatter_map
end

--- Fetches all tags from the vault with ripgrep.
---
--- @return vault.Tags.map
function Fetcher.tags()
    local tag_pattern = [=[(?:\s|^|[\.,; >])#([A-Za-z0-9_][A-Za-z0-9-_/]*)]=]
    local args = {
        "--json",
        "-t" .. filetype,
        "--no-heading",
        "--only-matching",
        -- TODO: Add support for ignore files. that is in the config.options.ignore option.
        -- "--ignore-file",

        tag_pattern,
        config.options.root,
    }

    local stdout = rg(args)


    --- @type vault.Tags.map
    local tags_map = {}
    local tags_from_frontmatter_map = fetch_tags_from_frontmatter()
    --- @type vault.Tag.constructor|vault.Tag
    local Tag = state.get_global_key("class.vault.Tag") or require("vault.tags.tag")

    local matches_map = {}
    for _, entry in ipairs(stdout) do
        local match = line_to_match_entry(entry)
        if not match then
            goto continue
        end

        local line = match.data.lines.text

        -- Check if the tag is inside the link like [some data #not-tag](https://example.com)
        -- so it is not a tag.
        -- TODO: Make it more accurate. Now it could be a tag inside a brackets, and it will be skipped.
        if line:find("%[.-#.-%]") then
            local is_tag = false
            local inside_brackets = false
            for char in line:gmatch(".") do
                if char == "[" then
                    inside_brackets = true
                elseif char == "]" then
                    inside_brackets = false
                elseif char == "#" and inside_brackets == false then
                    is_tag = true
                    break
                end
            end

            if is_tag == false then
                goto continue
            end
        end

        --- @type vault.path
        local path = match.data.path.text
        --- @type vault.slug
        local slug = utils.path_to_slug(path)

        for _, submatch in ipairs(match.data.submatches) do
            --- @type vault.Tag.data.name
            -- Remove the # from the beginning
            local tag_name = submatch.match.text:match("#(%S+)%s*$")

            if not matches_map[tag_name] then
                matches_map[tag_name] = {}
            end

            --- @type vault.Tag.data
            local tag_data = matches_map[tag_name]
            tag_data.name = tag_name

            -- nested
            if tag_data.name:find("/") then
                tag_data.is_nested = true
            end

            if tag_data.is_nested then
                tag_data.root = tag_data.name:match("^[^/]+")
            else
                tag_data.root = tag_data.name
            end

            -- sources
            if not tag_data.sources then
                tag_data.sources = {}
            end
            if not tag_data.sources[slug] then
                tag_data.sources[slug] = {}
            end
            local lnum = match.data.line_number
            if not tag_data.sources[slug][lnum] then
                tag_data.sources[slug][lnum] = {
                    lnum = lnum,
                    line = line,
                    col = submatch.start,
                    end_lnum = lnum,
                    end_col = submatch["end"],
                }
            end
            --
            -- if not tag_data.count then
            --     tag_data.count = 1
            -- else
            --     tag_data.count = tag_data.count + 1
            -- end

            if tags_from_frontmatter_map[tag_name] then
                -- tag_data.count = tag_data.count + tags_from_frontmatter_map[tag_name].count
                tag_data.sources = vim.tbl_deep_extend("force", tag_data.sources, tags_from_frontmatter_map[tag_name].sources)
            end

            tags_map[tag_name] = Tag(tag_data)
        end
        ::continue::
    end
    return tags_map
end

return Fetcher
