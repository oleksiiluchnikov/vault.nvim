---@class Matcher
local Matcher = {}

---@enum MatchOpt
local MatchOpts = {
  exact = 1,
  contains = 2,
  startswith = 3,
  endswith = 4,
  regex = 5,
  fuzzy = 6,
}

local function invalid_match_error_msg(match_opt)
   return "Invalid match: " .. vim.inspect(match_opt) .. ". Valid matches are: " .. table.concat(MatchOpts, ", ")
end

---Create a new Matcher object.
---@param match_opt string - The match type to use.
---@return Matcher
function Matcher:new(match_opt)
  local matcher = {
    match_opt = match_opt,
  }
  setmetatable(matcher, self)
  self.__index = self
  -- self:validate(match_opt)
  return matcher
end

---Check if `MatchOpt` is valid.
---@param match_opt string - The match type to use.
function Matcher:validate(match_opt)
  if not MatchOpts[match_opt] then
    error(invalid_match_error_msg(match_opt))
  end
end

-- The perform_match function now takes an additional parameter, the match type
---@param a string - The value to filter notes.
---@param b string - The value to filter notes.
---@param match_opt string - The match type to use.
---|"'exact'" # Matches exact value. E.g., "foo" matches "foo" but not "foobar".
---|"'contains'" # Matches value if it contains the query. E.g., "foo" matches "foo" and "foobar".
---|"'startswith'" # Matches value if it starts with the query. E.g., "foo" matches "foo" and "foobar".
---|"'endswith'" # Matches value if it ends with the query. E.g., "foo" matches "foo" and "barfoo".
---|"'regex'" # Matches value if it matches the query as a regex. E.g., "foo" matches "foo" and "barfoo".
---@return boolean
function Matcher:match(a, b, match_opt)
  if type(a) ~= "string" or type(b) ~= "string" then
    error("Invalid match: " .. vim.inspect(a) .. ", " .. vim.inspect(b) .. ". Both values must be strings.")
    return false
  end

  ---@type number
  local v = MatchOpts[match_opt]

  if not v then
    error(invalid_match_error_msg(match_opt))
    return false
  end

  if v == 1 then -- exact
    if a == b then
      return true
    end
  elseif v == 2 then -- contains
    if string.find(a, b) then
      return true
    end
  elseif v == 3 then -- startswith
    if string.sub(a, 1, #b) == b then
      return true
    end
  elseif v == 4 then -- endswith
    if string.sub(a, -#b) == b then
      return true
    end
  elseif v == 5 then -- regex
    if string.match(a, b) then
      return true
    end
  elseif v == 6 then -- fuzzy
    for i = 1, #a do
      if string.sub(a, i, i) == string.sub(b, i, i) then
        return true
      end
    end
  end
  return false
end

function Matcher:__call(match_opt)
  return self:new(match_opt)
end

Matcher = setmetatable(Matcher, Matcher)

return Matcher
