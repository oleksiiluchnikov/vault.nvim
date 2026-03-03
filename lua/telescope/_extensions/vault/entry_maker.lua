--- telescope._extensions.vault.entry_maker — Shared entry maker factories
---
--- Extracts the common "name + count" two-column displayer pattern used by
--- tags, properties, and dirs pickers into reusable factory functions.
---
--- Usage:
---   local em = require("telescope._extensions.vault.entry_maker")
---   local make_display, entry_maker = em.counted({
---     hl_name = "VaultTag",
---     colors = colors,
---     steps = steps,
---     get_name = function(item) return item.data.name end,
---     get_count = function(item) return item.data.count end,
---   })
---
--- @module "telescope._extensions.vault.entry_maker"

local entry_display = require("telescope.pickers.entry_display")

local M = {}

--- @class vault.EntryMakerCountedOpts
--- @field hl_name string            Gradient highlight base name (e.g. "VaultTag")
--- @field colors table|nil          Gradient color table from vault_hl.setup()
--- @field steps integer             Number of gradient steps
--- @field get_name fun(item: any): string   Extract display name from item
--- @field get_count fun(item: any): integer  Extract count from item
--- @field get_ordinal? fun(item: any): string  Custom ordinal (default: name .. " " .. count)
--- @field name_width? integer       Width of name column (default: 29)

--- Create a "name + count" two-column displayer and entry_maker.
---
--- Returns two functions: make_display(entry) and entry_maker(item).
--- The displayer shows the name with optional gradient highlight and the count.
---
--- @param opts vault.EntryMakerCountedOpts
--- @return fun(entry: table): table, table  make_display, entry_maker
function M.counted(opts)
    local hl_name = opts.hl_name
    local colors = opts.colors
    local steps = opts.steps
    local get_name = opts.get_name
    local get_count = opts.get_count
    local get_ordinal = opts.get_ordinal
    local name_width = opts.name_width or 29

    --- @param entry table
    --- @return table
    local function make_display(entry)
        local item = entry.value
        local count = get_count(item)
        local name = get_name(item)

        local name_hl = "TelescopeResultsNormal"
        if colors then
            local i = math.min(math.floor(count / 2), steps)
            if i == 0 then i = 1 end
            name_hl = hl_name .. tostring(i)
        end

        local displayer = entry_display.create({
            separator = " ",
            items = {
                { width = name_width },
                { remaining = true },
            },
        })

        return displayer({
            { name, name_hl },
            { tostring(count), "TelescopeResultsNumber" },
        })
    end

    --- @param item any
    --- @return table
    local function entry_maker(item)
        local ordinal
        if get_ordinal then
            ordinal = get_ordinal(item)
        else
            ordinal = get_name(item) .. " " .. tostring(get_count(item))
        end
        return {
            value = item,
            ordinal = ordinal,
            display = make_display,
        }
    end

    return make_display, entry_maker
end

return M
