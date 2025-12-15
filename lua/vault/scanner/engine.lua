--- Engine module serves as a bridge to the core scanning functionality.
--- It is designed to avoid requiring any other `vault.*` modules for simplicity and modularity.
local config = require("vault.config")

local Engine = {}

--- Scans the specified root directory and returns the results.
--- The root directory is determined based on the `config.options.root` value.
---
--- @return table<string, any> The scan results from the core module.
function Engine.scan()
    local core = require("vault_core")
    local root = vim.fn.expand(config.options.root) -- Expands and normalizes the root path.
    return core.scan(root) -- Delegates the scanning operation to the core module.
end


return Engine
