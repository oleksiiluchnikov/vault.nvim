local FilterOpts = require("vault.filter_opts")

---@class VaultNotesFilterOpts: VaultFilterOpts
---@field super VaultFilterOpts
---@field by table - Target to filter.
---| '"tags"' # Filter tags.
---| '"notes"' # Filter notes.
---@diagnostic disable-next-line: undefined-field
local NotesFilterOpts = FilterOpts:extend("VaultNotesFilterOpts")

---@enum NotesFilterOptBy
local NotesFilterOptBy = {
  "tags",
  "notes",
  "basename",
}

---Create a new NotesFilterOpts object.
---```lua
---NotesFilterOpts("tags", { "foo", "bar" }, { "baz" }, "exact", "all")
---```
---@param ... any
function NotesFilterOpts:init(...)
  local args = { ... }
  if #args == 1 and type(args[1]) == "table" then
    args = args[1]
  end

  if not args[1] then
    error("invalid key `by`: must be a string or table")
  end

  if type(args[1]) == "string" then
    args[1] = { args[1] }
  end

  if type(args[1]) == "table" then
    for _, v in ipairs(args[1]) do
      if not vim.tbl_contains(NotesFilterOptBy, v) then
        error("invalid key `by`: `" .. vim.inspect(v) .. "` not in: Opts " .. vim.inspect(NotesFilterOptBy))
      end
    end
  end
  ---
  ---@type NotesFilterOptBy|NotesFilterOptBy[]
  self.by = args[1]
  NotesFilterOpts.super.init(self, args[2], args[3], args[4], args[5])
end

---@alias VaultNotesFilterOpts.constructor fun(...): VaultNotesFilterOpts
---@type VaultNotesFilterOpts.constructor|VaultNotesFilterOpts
local VaultNotesFilterOpts = NotesFilterOpts

return VaultNotesFilterOpts
