-- local wikilink_pattern = [=[\[\[([^\[\]]+)\]\]]=]
local wikilink_pattern = "%[%[([^%[%]]-)%]%]"

local input_string = [=[
    # This is a test

    This is a test note. It has a [[link]] to another note.

    ## This is a heading

    This is a test note. It has a [[link]] to another note.

    ## This is another heading

    This is a test note. It has a [[link]] to another note.
    ]=]

local function parse_wikilinks(input_string)
    local links = {}
    for link in input_string:gmatch(wikilink_pattern) do
        table.insert(links, link)
    end
    return links
end

print(vim.inspect(parse_wikilinks(input_string)))
