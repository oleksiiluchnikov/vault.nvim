local Parser = {}
-- function Parser.tags_from_line(line)
--     local tags = {}
--     local seen = {} -- Track seen tags to avoid duplicates
--
--     -- Handle tags at start of line, after spaces, or after common delimiters
--     local tag_patterns = {
--         "[%s,;%.%s>]#([%w_][%w%-%_/]*)", -- Standard tag pattern
--         "^#([%w_][%w%-%_/]*)", -- Tags at start of line
--         "%[#([%w_][%w%-%_/]*)%]", -- Tags in brackets
--     }
--
--     for _, pattern in ipairs(tag_patterns) do
--         for tag in line:gmatch(pattern) do
--             -- Convert to lowercase for case-insensitive comparison
--             local normalized_tag = tag:lower()
--             -- Remove any trailing slashes
--             normalized_tag = normalized_tag:gsub("/$", "")
--
--             -- Skip empty tags or invalid formats
--             if #normalized_tag == 0 or normalized_tag:match("^/") or normalized_tag:match("//") then
--                 goto continue
--             end
--
--             -- Only add if we haven't seen this tag before
--             if not seen[normalized_tag] then
--                 seen[normalized_tag] = true
--                 -- Store original case in tags array
--                 table.insert(tags, tostring(tag:gsub("/$", "")))
--             end
--             ::continue::
--         end
--     end
--
--     -- Sort tags first by nesting depth, then alphabetically within same depth
--     table.sort(tags, function(a, b)
--         local a_parts = vim.split(a:lower(), "/", { plain = true })
--         local b_parts = vim.split(b:lower(), "/", { plain = true })
--
--         -- If paths have different depths, sort by depth first
--         if #a_parts ~= #b_parts then
--             return #a_parts < #b_parts
--         end
--
--         -- If same depth, compare each part lexicographically
--         for i = 1, #a_parts do
--             if a_parts[i] ~= b_parts[i] then
--                 return a_parts[i] < b_parts[i]
--             end
--         end
--         return false
--     end)
--
--     if next(tags) then
--         return tags
--     else
--         return nil
--     end
-- end

function Parser.metadata_from_line(line)
    local metadata = {}
    local metadata_pattern = "%[?([^%[%]]+)::([^%[%]]+)%]?"
    for field, value in line:gmatch(metadata_pattern) do
        -- Trim whitespace and normalize fields
        field = field:match("^%s*(.-)%s*$"):lower()
        value = value:match("^%s*(.-)%s*$")

        -- Handle special field types
        if
            field:match("date$")
            or field:match("^due")
            or field:match("^created")
            or field:match("^completed")
        then
            -- Try to parse as date
            local date = value:match("(%d%d%d%d%-%d%d%-%d%d)")
            if date then
                value = date
            end
        elseif field == "priority" then
            -- Convert priority to number if possible
            local num = tonumber(value)
            if num then
                value = num
            end
        elseif value:match("^%d+$") then
            -- Convert pure numbers
            value = tonumber(value)
        end

        -- Store normalized values
        if field and value then
            metadata[field] = value
        end
    end
    return metadata
end

function Parser.tags_from_line(line)
    local tags = {}
    local seen = {} -- Track seen tags to avoid duplicates
    local tag_pattern = "[%s,;%.%s>]#([%w_][%w%-%_/]*)"
    for tag in line:gmatch(tag_pattern) do
        -- Convert to lowercase for case-insensitive comparison
        local normalized_tag = tag:lower()
        -- Remove any trailing slashes
        normalized_tag = normalized_tag:gsub("/$", "")
        -- Skip empty tags or invalid formats
        if #normalized_tag == 0 or normalized_tag:match("^/") or normalized_tag:match("//") then
            goto continue
        end
        -- Only add if we haven't seen this tag before
        if not seen[normalized_tag] then
            seen[normalized_tag] = true
            -- Store original case in tags array
            table.insert(tags, tostring(tag:gsub("/$", "")))
        end
        ::continue::
    end
    return tags
end

function Parser.wikilinks_from_line(line)
    local wikilinks = {}
    local seen = {} -- Track seen wikilinks to avoid duplicates
    local wikilink_pattern = "%[%[([^%[%]]+)%]%]"
    for wikilink in line:gmatch(wikilink_pattern) do
        table.insert(wikilinks, wikilink)
    end
    return wikilinks
end

return Parser
