---@class NoteCheckbox
---@field state NoteCheckboxState
local Checkbox = {}
-- "- [ ] test line"
-- "- [x] test line"
-- "- [i] test line"
-- "- [c] test line"

local default_states = {
  unchecked = " ",
  checked = "x",
  intermediate = "i",
  cancelled = "c",
}


---@class NoteCheckboxState
---@field __index string
local CheckboxState = {}

---@return NoteCheckboxState
function CheckboxState:new(state)
  local this = {}
  setmetatable(this, self)
  this.__index = state
  return this
end

---@return string
function CheckboxState:__tostring()
  return self.__index
end


function CheckboxState:from_string(line)
  local state = line:match("%[([%w%s]+)%]")
  if state == nil then
    return nil
  end
  state = state:sub(1, 1)
  return self:new(state)
end

function Checkbox:new(state)
  local this = {}
  setmetatable(this, self)
  self.__index = self
  this.state = state
  return this
end

function Checkbox:from_string(line)
  local state = CheckboxState:from_string(line)
  if state == nil then
    return nil
  end
  return self:new(state)
end

---@type NoteCheckboxState
Checkbox.state = CheckboxState

function Checkbox:set(line, state)
  local current_state = CheckboxState:from_string(line)
  if current_state == nil then
    return line
  end
  local checkbox, line_content= line:match("^(.-%])%s*(.*)$")
  checkbox = checkbox:gsub("%[" .. tostring(current_state) .. "%]", "[" .. tostring(state) .. "]")
  return checkbox .. " " .. line_content
end

-- test
local checkbox = Checkbox:from_string("- [ ] test line"):set("- [ ] test line", "x")


return Checkbox
