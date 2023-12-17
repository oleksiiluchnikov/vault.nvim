-- "\[\[([^\]]*)\]\]" in PCRE (PHP >= 7.3) Flavor
-- test wikilink parser

local string_with_wikilink = [=[
This is a simple [[wikilink]] example.
Another example with a heading pointer: [[wikilink#Heading]].
Now, let's include a wikilink with a relative path: [[../folder/wikilink]].
Now, let's include a wikilink with a relative path: [[folder/wikilink]].
Here's a wikilink with an alias: [[wikilink|Alias]].
And now, a combination of all: [[complex/link#Section|Complex Link]] within a sentence.
Wikilink with Spaces: [[wiki link]].
Wikilink with Numbers: [[wiki123]].
Wikilink with Special Characters: [[wiki-123]].
External Link: [https://example.com External Link].
Mixed Inline Style: Some text with a [[wikilink]] and [https://example.com External Link].
Wikilink with Line Breaks:
[[wiki
link]].

[[wikilink]] with another [[wikilink]] on same line
]=]

local tbl_wikilink = {
  "wikilink",
  "wikilink#Heading",
  "../folder/wikilink",
  "folder/wikilink",
  "wikilink|Alias",
  "complex/link#Section",
  "wiki link",
  "wiki123",
  "wiki-123",
  "wikilink",
  "wikilink",
}

local function get_wikilinks(str)
  local wikilinks = {}
  for wikilink in string.gmatch(str, "%[%[([^]]*)%]%]") do
      table.insert(wikilinks, wikilink)
  end
  return wikilinks
end

  -- "wikilink#Heading", to get "wikilink" do:
-- print(string.match("wikilink#Heading", "(.-)#"))
-- print(string.match("wikilink|Alias", "(.-)|"))
-- print(string.match("complex/link#Section", "(.-)#"))
-- print(string.match("complex/link#Section|Complex Link", "(.-)#"))
-- print(string.match("complex/link#Section|Complex Link", "(.-)[|#]"))

-- P(get_wikilinks(string_with_wikilink))
