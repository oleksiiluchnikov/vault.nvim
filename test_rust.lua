-- test_rust.lua
vim.opt.runtimepath:append(".")

-- Force reload the module if it was cached
package.loaded["vault_core"] = nil
local core = require("vault_core")

-- IMPORTANT: Expand the path before sending to Rust
local path = vim.fn.expand("~/backups/knowledge") -- Update this to your actual vault path

print("Scanning: " .. path)

local start = vim.loop.hrtime()
-- This should now be nearly instant for < 1000 notes
local notes = core.scan(path)
local end_time = vim.loop.hrtime()

print(string.format("✅ Scanned %d notes in %.2fms", #notes, (end_time - start) / 1e6))

if #notes > 0 then
    print("Sample Note:", vim.inspect(notes[1]))
else
    print("⚠️ No notes found. Check directory permissions or path.")
end
