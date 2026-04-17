# Project Notes

- Benchmark and trace workflows are not pure Lua: they exercise scanner paths that `require("vault_core")`. Run `just build` before `just bench`, `just bench-metric`, `just bench-save`, `just bench-metric-save`, or `just trace-notes` if the Rust module is missing or stale.
