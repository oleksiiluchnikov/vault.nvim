local M = {}
---@class Wikilink
---@field raw string - The raw link as it appears in the note. e.g. [[link|title]]
---@field link string - The link as it appears in the note. e.g. link
---@field source string - The path to the note that contains the link. e.g. /home/user/notes/link.md
---@field heading string? - The heading of the link. e.g. link#heading
---@field custom_title string? - The custom title of the link. e.g. link|title
local Wikilink = {}

function Wikilink:new(link)
  local o = {}
  setmetatable(o, self)
  self.__index = self
  self.link = link
  self.title = ""
  self.heading = ""
  self.custom_title = ""
  return o
end
  

function M.parse(link)
  local link_pattern = "%[%[[^%]]+%]%]"
  local wikilink_data = link:match(link_pattern)
  if wikilink_data == nil then
    return {}
  end

  local link_title = wikilink_data:match("%[%[(.-)%]%]")
  if link_title == nil then
    return {}
  end

  local link_heading = wikilink_data:match("#(.+)")
  if link_heading == nil then
    link_heading = ""
  end

  local link_custom_title = wikilink_data:match("|(.+)")
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

return M
