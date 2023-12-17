local FilterOpts = require("vault.filter_opts")
local notes_enums = require("vault.notes.enums")

---@class VaultNotesPrefilterOpts: VaultFilter.option
---@field super VaultFilter.option
---@field by VaultNotesFilterKey|VaultNotesFilterKey[]
---@diagnostic disable-next-line: undefined-field
local NotesFilterOpts = FilterOpts:extend("VaultNotesFilterOpts")

--- Create a new NotesFilterOpts object.
---```lua
--- NotesFilterOpts("tags", { "foo", "bar" }, { "baz" }, "exact", "all")
---```
function NotesFilterOpts:init(...)
    local args = { ... }
    if #args == 1 and type(args[1]) == "table" then
        args = args[1]
    end

    if not args[1] then
        error(
            "invalid key `by`: is `nil`. Must be one or more of: "
                .. vim.inspect(notes_enums.filter_keys)
        )
    end

    if type(args[1]) == "string" then
        args[1] = { args[1] }
    end

    for _, v in ipairs(args[1]) do
        if not notes_enums.filter_keys[v] then
            error(
                "invalid key `by`: `"
                    .. vim.inspect(v)
                    .. "` not in: Opts "
                    .. vim.inspect(notes_enums.filter_keys)
            )
        end
    end

    ---@type VaultNotesFilterKey|VaultNotesFilterKey[]
    self.by = args[1]
    NotesFilterOpts.super.init(self, args[2], args[3], args[4], args[5])
end

---@alias VaultNotesFilterOpts.constructor fun(...): VaultNotesPrefilterOpts
---@type VaultNotesFilterOpts.constructor|VaultNotesPrefilterOpts
local VaultNotesFilterOpts = NotesFilterOpts

return VaultNotesFilterOpts
