local todo = {}
local utils = require("vault.utils")
local config = require("vault.config")

---Create a new todo if it does not exist.
---@param title string
function todo.add(title)
  local Vault = require("vault")
  local Note = require("vault.notes.note")
  local note = Vault.find(title)

	if note ~= nil then
		note:edit()
    return
  end

  local inbox_dir = config.dirs.inbox

  local path = inbox_dir .. "/" .. title .. ".md"

  local content = [[
  ---
  uuid:: ]] .. utils.generate_uuid() .. [[
  ---
# ]] .. title .. [[


status:: #status/TODO
  ]]

  note = Note:new(path)

  note:write(path, content)
end

return todo
