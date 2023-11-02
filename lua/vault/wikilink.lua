local M = {}
---@class Wikilink
---@param link string
---@return table
local wikilink = {}

function wikilink:new(link)
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
