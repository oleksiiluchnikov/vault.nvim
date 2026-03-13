local pickers = require("telescope._extensions.vault.pickers")
local log = require("vault.log").scope("properties.actions")

local M = {}

local function safe_find(picker, empty_msg)
    if picker then
        picker:find()
    else
        log.info(empty_msg or "No results found")
    end
end

function M.open_picker_values(property_name)
    local properties = require("vault.properties")()
    local prop = properties.map and properties.map[property_name]
    if not prop or not prop.data or not prop.data.values then
        log.info("No values found for property: %s", property_name)
        return
    end
    safe_find(
        pickers.property_values({ property = property_name, values = prop.data.values }),
        "No values found for property: " .. property_name
    )
end

function M.open_picker_notes_with_value(property_name, value)
    safe_find(
        pickers.notes({
            notes = require("vault.notes")():filter(property_name, value, "contains", false),
        }),
        string.format("No notes found with property %s=%s", property_name, value)
    )
end

function M.open_picker_notes_with_empty_value(property_name, value)
    local notes = require("vault.notes")()
    if property_name and property_name ~= "" then
        notes = notes:filter(property_name, value or "", "exact", false)
    else
        notes = notes:without_property(value or "")
    end
    safe_find(pickers.notes({ notes = notes }), "No notes found with empty property value")
end

return M
