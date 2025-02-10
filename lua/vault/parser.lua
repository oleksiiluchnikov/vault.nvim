local Parser = {}
function Parser.tags_from_line(line)
    local tags = {}
    local seen = {} -- Track seen tags to avoid duplicates

    -- Handle tags at start of line, after spaces, or after common delimiters
    local tag_patterns = {
        "[%s,;%.%s>]#([%w_][%w%-%_/]*)", -- Standard tag pattern
        "^#([%w_][%w%-%_/]*)", -- Tags at start of line
        "%[#([%w_][%w%-%_/]*)%]", -- Tags in brackets
    }

    for _, pattern in ipairs(tag_patterns) do
        for tag in line:gmatch(pattern) do
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
                table.insert(tags, tag:gsub("/$", ""))
            end
            ::continue::
        end
    end

    -- Sort tags first by nesting depth, then alphabetically within same depth
    table.sort(tags, function(a, b)
        local a_parts = vim.split(a:lower(), "/", { plain = true })
        local b_parts = vim.split(b:lower(), "/", { plain = true })

        -- If paths have different depths, sort by depth first
        if #a_parts ~= #b_parts then
            return #a_parts < #b_parts
        end

        -- If same depth, compare each part lexicographically
        for i = 1, #a_parts do
            if a_parts[i] ~= b_parts[i] then
                return a_parts[i] < b_parts[i]
            end
        end
        return false
    end)

    return tags
end

-- Test cases using plenary.test_harness
local busted = require("plenary.busted")

local function test_tags_from_line()
    -- Test basic tag extraction
    assert.are.same(
        { "world", "hello", "nested/hello", "nested/world" },
        Parser.tags_from_line(
            "[[hello]] #world #hello #World #nested/hello #nested/world without_space#world"
        )
    )

    -- Test tags at start of line
    assert.are.same(
        { "end", "middle", "StartTag" },
        Parser.tags_from_line("#StartTag #middle #end")
    )

    -- Test mixed bracket and normal tags
    assert.are.same(
        { "bracketTag", "normalTag" },
        Parser.tags_from_line("Mixed [#bracketTag] and #normalTag")
    )

    -- Test nested tags
    assert.are.same(
        { "simple", "nested/tag/1", "nested/tag/2" },
        Parser.tags_from_line("#nested/tag/1 #nested/tag/2 #simple")
    )

    -- Test case sensitivity handling
    assert.are.same(
        { "lowercase", "MixedCase", "UPPERCASE" },
        Parser.tags_from_line("#UPPERCASE #lowercase #MixedCase")
    )

    -- Test edge cases
    assert.are.same({}, Parser.tags_from_line(""))
    assert.are.same({}, Parser.tags_from_line("#"))
    assert.are.same({}, Parser.tags_from_line("#/"))
    assert.are.same({}, Parser.tags_from_line("#//"))
    assert.are.same({ "valid" }, Parser.tags_from_line("#valid/"))
end
test_tags_from_line()

return Parser
