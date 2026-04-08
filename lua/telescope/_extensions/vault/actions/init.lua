local common = require("telescope._extensions.vault.actions.common")
local property_module = require("telescope._extensions.vault.actions.property")

local vault_actions = {
    refresh = common.refresh,
    resort = common.resort,
    close = common.close,
    note = require("telescope._extensions.vault.actions.note"),
    tag = require("telescope._extensions.vault.actions.tag"),
    property = property_module.property,
    property_value = property_module.property_value,
    directory = require("telescope._extensions.vault.actions.directory"),
    base = require("telescope._extensions.vault.actions.base"),
    _rename_property_values = property_module._rename_property_values,
    _normalize_occurrences = property_module._normalize_occurrences,
    _find_property_value_occurrences = property_module._find_property_value_occurrences,
}

return vault_actions
