---@class Wikilink
---@field raw string - The raw link as it appears in the note. e.g. [[foo|title]]
---@field link string - The link as it appears in the note. e.g. foo
---@field source string - The path to the note that contains the link. e.g. /home/user/notes/foo.md
---@field heading string? - The heading of the link. e.g. foo#heading
---@field custom_title string? - The custom title of the link. e.g. foo|title
local Wikilink = {}

---Create a new Wikilink object.
---@param link string - The raw link as it appears in the note. e.g. [[foo|title]]
---@return Wikilink
function Wikilink:new(link)
  local this = {}
  this.raw = link
  this.link = link
  this.title = ""
  this.heading = ""
  this.custom_title = ""
  setmetatable(this, self)
  self.__index = self
  return this
end

function Wikilink.parse(link)
  local link_pattern = "%[%[[^%]]+%]%]"
  local wikilink_map = link:match(link_pattern)
  if wikilink_map == nil then
    return {}
  end

  local link_title = wikilink_map:match("%[%[(.-)%]%]")
  if link_title == nil then
    return {}
  end

  local link_heading = wikilink_map:match("#(.+)")
  if link_heading == nil then
    link_heading = ""
  end

  local link_custom_title = wikilink_map:match("|(.+)")
  if link_custom_title == nil then
    link_custom_title = ""
  end

  return {
    link = link,
    title = link_title,
    heading = link_heading,
    custom_title = link_custom_title,
  }
end

return function(link)
  return Wikilink(link)
end
