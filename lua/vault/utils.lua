-- Lightweight delegate so require("vault.utils") resolves to the real implementation
-- in `lua/vault/utils/init.lua`. This avoids duplicating code and ensures a single
-- canonical implementation.

return require("vault.utils.init")
