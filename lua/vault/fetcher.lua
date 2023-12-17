---@type VaultConfig|VaultConfig.options
local config = require("vault.config")
local state = require("vault.core.state")
local utils = require("vault.utils")
local Job = require("plenary.job")

local root_dir = config.root
local ext = config.ext or ".md"
local filetype = ext:sub(2)

local cmd = config.search_tool or "rg" -- TODO: Make this configurable.

---@class VaultFetcher.ripgrep
---@field notes fun(): VaultMap.notes - Fetches all paths from the vault with ripgrep.
---@field wikilinks fun(): VaultMap.wikilinks - Fetches all wikilinks from the vault with ripgrep.
---@field tags fun(): VaultMap.tags - Fetches all tags from the vault with ripgrep.
---@field tasks fun(): VaultMap.todos - Fetches all todos from the vault with ripgrep.
---@field links fun(): VaultMap.links - Fetches all external links from the vault with ripgrep.
local Fetcher = {}

--- Executes the ripgrep command.
---
---@return string[]
local function execute(args)
    local stdout = {}

    Job:new({
        command = cmd,
        args = args,

        on_exit = function(j, _, _)
            stdout = j:result()
        end,
    }):sync()

    assert(stdout, "rg failed to run")

    return stdout
end

--- Fetches all paths from the vault with ripgrep.
---
--- TODO: Add support for ignore files. that is in the config.ignore option.
---@return VaultMap.notes
function Fetcher.paths()
    local args = {
        "-t" .. filetype,
        "--files",
        root_dir,
    }

    local stdout = execute(args)

    local paths = {}
    for _, path in ipairs(stdout) do
        local slug = utils.path_to_slug(path)

        if not paths[slug] then
            paths[slug] = {
                path = path,
                slug = slug,
                relpath = utils.path_to_relpath(path),
                basename = vim.fn.fnamemodify(path, ":t"),
            }
        end
    end
    return paths
end

function Fetcher.slugs()
    ---@type VaultMap.slugs
    local slugs = {}
    for slug, _ in pairs(Fetcher.paths()) do
        slugs[slug] = true
    end
    state.set_global_key("slugs", slugs)
    return slugs
end

--- FIXME: This is giving more results than the above function.
function Fetcher.paths_with_fd()
    local stdout = {}

    Job:new({
        command = "fd",
        args = args,
        cwd = root_dir,

        on_exit = function(j, _, _)
            stdout = j:result()
        end,
    }):sync()

    assert(stdout, "find failed to run")
    -- print(vim.inspect(stdout))

    local paths = {}
    for _, path in ipairs(stdout) do
        local slug = utils.path_to_slug(path)

        if not paths[slug] then
            paths[slug] = {
                path = path,
                slug = slug,
                relpath = utils.path_to_relpath(path),
                basename = vim.fn.fnamemodify(path, ":t"),
            }
        end
    end
    return paths
end

-- with macOS find command
--- Fetches all paths from the vault with find.
--- NOTE: This is only for macOS. And it is slower than everything else.
function Fetcher.paths_with_find()
    local args = {
        root_dir,
        "-type",
        "f",
        "-name",
        "*" .. ext,
    }

    local stdout = {}

    Job:new({
        command = "find",
        args = args,

        on_exit = function(j, _, _)
            stdout = j:result()
        end,
    }):sync()

    -- print(vim.inspect(stdout))

    local paths = {}
    for _, path in ipairs(stdout) do
        local slug = utils.path_to_slug(path)

        if not paths[slug] then
            paths[slug] = {
                path = path,
                slug = slug,
                relpath = utils.path_to_relpath(path),
                basename = vim.fn.fnamemodify(path, ":t"),
            }
        end
        ::continue::
    end
    return paths
end

-- Fetcher.paths()
-- Fetcher.paths_with_fd()
-- Compare the speed of both of these functions.
local function test()
    local t1 = vim.fn.reltime()
    Fetcher.paths()
    local t2 = vim.fn.reltime()
    print(vim.inspect(vim.fn.reltimestr(vim.fn.reltime(t1, t2))))
    local t3 = vim.fn.reltime()
    Fetcher.paths_with_fd()
    local t4 = vim.fn.reltime()
    print(vim.inspect(vim.fn.reltimestr(vim.fn.reltime(t3, t4))))
    local t5 = vim.fn.reltime()
    Fetcher.paths_with_find()
    local t6 = vim.fn.reltime()
    print(vim.inspect(vim.fn.reltimestr(vim.fn.reltime(t5, t6))))
end

-- Compare the count of items in the maps.
local function test2()
    local t1 = vim.fn.reltime()
    local paths = Fetcher.paths()
    local t2 = vim.fn.reltime()
    print(vim.inspect(vim.fn.reltimestr(vim.fn.reltime(t1, t2))))
    local t3 = vim.fn.reltime()
    local paths2 = Fetcher.paths_with_fd()
    local t4 = vim.fn.reltime()
    print(vim.inspect(vim.fn.reltimestr(vim.fn.reltime(t3, t4))))
    print(vim.inspect(vim.tbl_count(paths)))
    print(vim.inspect(vim.tbl_count(paths2)))
end

--- Fetches all wikilinks from the vault with ripgrep.
---
---@return VaultMap.wikilinks
function Fetcher.wikilinks()
    local wikilink_pattern = [=[(?:[!])?\[\[([^\[\]]+?)\]\]]=]
    local args = {
        "--json",
        "-t" .. filetype,
        "--no-heading",
        "--only-matching",
        wikilink_pattern,
        root_dir,
    }

    local stdout = execute(args)
    ---@type VaultWikilink.constructor|VaultWikilink
    local Wikilink = state.get_global_key("_class.VaultWikilink")
        or require("vault.wikilinks.wikilink")

    local wikilinks_map = {}
    for _, entry in ipairs(stdout) do
        ---@type VaultRipGrepMatch
        local match = vim.fn.json_decode(entry)
        if not match.type == "match" then
            goto continue
        elseif not match.data then
            goto continue
        elseif not match.data.submatches or next(match.data.submatches) == nil then
            goto continue
        end

        for _, submatch in ipairs(match.data.submatches) do
            ---@type VaultWikilink
            local wikilink = Wikilink(submatch.match.text)
            if not wikilinks_map[wikilink.data.stem] then
                wikilinks_map[wikilink.data.stem] = wikilink
            else
                wikilinks_map[wikilink.data.stem].data.count = wikilinks_map[wikilink.data.stem].data.count
                    + 1
            end

            local data = wikilinks_map[wikilink.data.stem].data
            local path = match.data.path.text
            local note_slug = utils.path_to_slug(path)
            local line_number = match.data.line_number

            if submatch.match.text:find("^!") then
                data.embedded = true
            end

            if not data.count then
                data.count = 1
            end

            if not data.sources then
                data.sources = {}
            end

            if not data.sources[note_slug] then
                data.sources[note_slug] = {}
            end

            data.sources[note_slug][line_number] = {}
            data.sources[note_slug][line_number].line = match.data.lines.text
            data.sources[note_slug][line_number].col = {}
            data.sources[note_slug][line_number].col.start = submatch.start
            data.sources[note_slug][line_number].col["end"] = submatch["end"]
        end

        ::continue::
    end
    return wikilinks_map
end

--- Fetches all tags from the vault with ripgrep.
---
---@return VaultMap.tags
function Fetcher.tags()
    local tag_pattern = [[(?:\s|^|[\.,; >])#([A-Za-z0-9_][A-Za-z0-9-_/]*)]] -- TODO: Make this configurable.
    -- How to exclude caste when [ some data #not-tag] is matched?
    local args = {
        "--json",
        "-t" .. filetype,
        "--no-heading",
        "--only-matching",
        -- TODO: Add support for ignore files. that is in the config.ignore option.
        -- "--ignore-file",

        tag_pattern,
        root_dir,
    }

    local stdout = execute(args)

    ---@type VaultTag.constructor|VaultTag
    local Tag = state.get_global_key("_class.VaultTag") or require("vault.tags.tag")

    local matches_map = {}
    ---@type VaultMap.tags
    local tags_map = {}
    for _, entry in ipairs(stdout) do
        ---@type VaultRipGrepMatch
        local match = vim.fn.json_decode(entry)

        if not match.type == "match" then
            goto continue
        elseif not match.data then
            goto continue
        elseif not match.data.submatches or next(match.data.submatches) == nil then
            goto continue
        end

        local line = match.data.lines.text

        -- Check if the tag is inside the link like [some data #not-tag](https://example.com)
        -- so it is not a tag.
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

        ---@type VaultNote.data.path
        local path = match.data.path.text
        ---@type VaultNote.data.slug
        local slug = utils.path_to_slug(path)

        for _, submatch in ipairs(match.data.submatches) do
            ---@type VaultTag.data.name
            local tag_name = submatch.match.text:sub(3)

            if not matches_map[tag_name] then
                matches_map[tag_name] = {}
            end

            ---@type VaultTag.data
            local tag_data = matches_map[tag_name]
            tag_data.name = tag_name
            if tag_data.name:find("/") then
                tag_data.is_nested = true
            end

            if tag_data.is_nested then
                tag_data.root = tag_data.name:match("^[^/]+")
            else
                tag_data.root = tag_data.name
            end

            if not tag_data.sources then
                tag_data.sources = {}
            end
            if not tag_data.sources[slug] then
                tag_data.sources[slug] = {}
                local line_number = match.data.line_number
                if not tag_data.sources[slug][line_number] then
                    tag_data.sources[slug][line_number] = {}
                end

                tag_data.sources[slug][line_number].line = line
                tag_data.sources[slug][line_number].start = submatch.start
                tag_data.sources[slug][line_number]["end"] = submatch["end"]
            end

            if not tag_data.count then
                tag_data.count = 1
            else
                tag_data.count = tag_data.count + 1
            end

            local tag = Tag(tag_data)
            tags_map[tag_name] = tag
        end
        ::continue::
    end
    return tags_map
end

---@class VaultTodo
---@field line string
---@field status string

---@class VaultMap.todos table<string, VaultMap.todos.lines>

--- Fetches all todos from the vault with ripgrep.
---
---@return VaultMap.todos
function Fetcher.tasks()
    local todo_pattern = [[^\s*-\s+\[(.)\]\s+]]
    local args = {
        "--json",
        "-t" .. filetype,
        "--no-heading",
        "--only-matching",
        todo_pattern,
        root_dir,
    }

    local stdout = execute(args)

    local tasks_map = {}
    for _, entry in ipairs(stdout) do
        ---@type VaultRipGrepMatch
        local match = vim.fn.json_decode(entry)
        if not match.type == "match" then
            goto continue
        elseif not match.data then
            goto continue
        elseif not match.data.submatches or next(match.data.submatches) == nil then
            goto continue
        end

        local line = match.data.lines.text

        for _, submatch in ipairs(match.data.submatches) do
            ---@type VaultTodo
            local todo = {
                line = line,
                status = submatch.match.text:match("%[.%]"),
                text = line:match("^%s*-%s+%[.%]%s+(.*)%s$"),
                wikilinks = {},
            }
            for wikilink in line:gmatch("%[%[.-]]") do
                todo.wikilinks[wikilink] = true
            end

            local path = match.data.path.text
            local slug = utils.path_to_slug(path)
            local line_number = match.data.line_number

            if not tasks_map[slug] then
                tasks_map[slug] = {}
            end

            if not tasks_map[slug][line_number] then
                tasks_map[slug][line_number] = todo
            end
        end
        ::continue::
    end
    return tasks_map
end

---@class VaultMap.links table<string, VaultMap.links.lines>

--- Fetches all external links from the vault with ripgrep.
---
---@return VaultMap.links
function Fetcher.links()
    local link_pattern = [[\[(.*?)\]\((.*?)\)]]
    local args = {
        "--json",
        "-t" .. filetype,
        "--no-heading",
        "--only-matching",
        link_pattern,
        root_dir,
    }

    local stdout = execute(args)

    local links_map = {}
    for _, entry in ipairs(stdout) do
        ---@type VaultRipGrepMatch
        local match = vim.fn.json_decode(entry)
        if not match.type == "match" then
            goto continue
        elseif not match.data then
            goto continue
        elseif not match.data.submatches or next(match.data.submatches) == nil then
            goto continue
        end

        local line = match.data.lines.text

        for _, submatch in ipairs(match.data.submatches) do
            ---@type VaultLink
            local link = {
                line = line,
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
--- @return VaultMap.fields
function Fetcher.inline_fields()
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
        root_dir,
    }

    local stdout = execute(args)

    local fields_map = {}
    for _, entry in ipairs(stdout) do
        ---@type VaultRipGrepMatch
        local match = vim.fn.json_decode(entry)
        if not match.type == "match" then
            goto continue
        elseif not match.data then
            goto continue
        elseif not match.data.submatches or next(match.data.submatches) == nil then
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

return Fetcher
