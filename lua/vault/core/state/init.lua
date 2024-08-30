--- @class vault.StateManager
--- The state manager is responsible for managing the state of the plugin.
local state = { global = {} }

--- @class vault.GlobalState
--- @field global table<string, any>
VaultState = VaultState or { global = {} }
VaultState.global = VaultState.global or {}

--- @alias vault.StateManager.key string

--- Get a global state key.
---
--- ```lua
--- local state = require("vault.core.state")
---
--- state.get_global_key("foo")
--- ```
--- @param key vault.StateManager.key
--- @return any
function state.get_global_key(key)
    return VaultState.global[key]
end

--- Set a global state key to a value.
---
--- ```lua
--- local state = require("vault.core.state")
---
--- state.set_global_key("foo", "bar")
--- ```
--- @param key vault.StateManager.key
--- @param value any
--- @return nil
function state.set_global_key(key, value)
    VaultState.global[key] = value
end

--- Clears all global state.
---
--- ```lua
--- local state = require("vault.core.state")
---
--- state.clear_all()
--- ```
--- @return nil
function state.clear_all()
    VaultState.global = {}
end

return state
