local M = {}
-- "- [ ] test line"
-- "- [x] test line"
-- "- [i] test line"
-- "- [c] test line"

M.state = {}

function M.state.fetch(line)
  local state = line:match('%[([%w%s]+)%]')
  if state == nil then
    return nil
  end
  return state:sub(1, 1)
end

function M.state.set(line, state)
  local current_state = M.state.fetch(line)
  if current_state == nil then
    return line
  end
  return line:gsub(current_state, state)
end

function M.test(line)
  local state = M.state.fetch(line)
  if state == nil then
    return false
  end
  return true
end


return M
