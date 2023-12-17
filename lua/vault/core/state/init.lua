---@class VaultStateManager
local state = {}

---@class VaultGlobalState
---@field global table<string, any>
VaultGlobalState = VaultGlobalState or {}
VaultGlobalState.global = VaultGlobalState.global or {}

---@alias VaultStateKey string

--- Get a global state key.
---
---@param key VaultStateKey
---@return any
function state.get_global_key(key)
    return VaultGlobalState.global[key]
end

--- Set a global state key to a value.
---
---@param key VaultStateKey
---@param value any
---@return nil
function state.set_global_key(key, value)
    VaultGlobalState.global[key] = value
end

--- Clears all global state.
---
---@return nil
function state.clear_all()
    VaultGlobalState.global = {}
end

return state
