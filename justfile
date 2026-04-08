# vault.nvim — Obsidian vault integration for Neovim
# https://github.com/oleksiiluchnikov/vault.nvim

# Default: list available recipes
default:
    @just --list

# System detection
os := os()
lib_ext := if os == "macos" { "dylib" } else { "so" }
target := "lua/vault_core.so"
rustflags := if os == "macos" { "-C link-arg=-undefined -C link-arg=dynamic_lookup" } else { "" }
minimal_init := "tests/minimal_init.lua"

# Build + reload (alias)
br: build reload

# Compile Rust module, copy to lua/, re-sign on macOS
build:
    @echo "Building for {{ os }} with flags: {{ rustflags }}"
    RUSTFLAGS="{{ rustflags }}" cargo build --release
    cp target/release/libvault_core.{{ lib_ext }} {{ target }}
    {{ if os == "macos" { "codesign --force --sign - " + target } else { "true" } }}

# cargo clean + remove built .so
clean:
    cargo clean
    rm -f {{ target }}

# Hot-reload plugin in running Neovim via nvim:// URL scheme
reload:
    @if command -v nvim-server >/dev/null 2>&1; then \
        open "nvim://cmd?run=Lazy%20reload%20vault.nvim"; \
    else \
        echo "nvim-server not found. Please install it or reload manually."; \
    fi

# Quick check: eval a random note in running Neovim
check:
    #!/usr/bin/env bash
    lua_cmd='vim.api.nvim_feedkeys(":lua P(require(\"vault.notes\")():get_random())", "n", false)'
    encoded=$(printf '%s' "$lua_cmd" | jq -sRr @uri)
    open "nvim://cmd?run=lua%20$encoded"

# Run all plenary tests
test-all:
    @printf "Running all tests...\n"
    #!/usr/bin/env bash
    lua_cmd='require("plenary.test_harness").test_directory("tests", {minimal_init = "{{ minimal_init }}"})'
    encoded=$(printf '%s' "$lua_cmd" | jq -sRr @uri)
    open "nvim://cmd?run=lua%20$encoded"

# Run tests in tests/notes/ only
test-note:
    @printf "Running tests/notes/...\n"
    #!/usr/bin/env bash
    lua_cmd='require("plenary.test_harness").test_directory("tests/notes", {minimal_init = "{{ minimal_init }}"})'
    encoded=$(printf '%s' "$lua_cmd" | jq -sRr @uri)
    open "nvim://cmd?run=lua%20$encoded"

# Run test for the currently open buffer
test-current:
    @printf "Running tests for current buffer...\n"
    #!/usr/bin/env bash
    lua_cmd='local path=vim.api.nvim_buf_get_name(0);require("plenary.test_harness").test_file(path, {minimal_init = "{{ minimal_init }}"})'
    encoded=$(printf '%s' "$lua_cmd" | jq -sRr @uri)
    open "nvim://cmd?run=lua%20$encoded"

# Reload then run test for current buffer
test: reload test-current

# Run a specific test file headlessly
test-file file:
    nvim --headless -u {{ minimal_init }} \
        -c "PlenaryBustedFile {{ file }}"

# Run a test directory headlessly
test-dir dir:
    nvim --headless -u {{ minimal_init }} \
        -c 'PlenaryBustedDirectory {{ dir }} {minimal_init = "{{ minimal_init }}"}'

# Run performance benchmarks (default: 500 notes)
bench vault_size="500":
    NVIM_LISTEN_ADDRESS= nvim --headless -u {{ minimal_init }} -l scripts/benchmark.lua -- --vault-size {{ vault_size }}

# Compare latest benchmark against the stored baseline for this size
bench-check vault_size="500" threshold="20":
    NVIM_LISTEN_ADDRESS= nvim --headless -u {{ minimal_init }} -l scripts/check_bench.lua -- --baseline benchmarks/baseline-{{ vault_size }}.json --latest benchmarks/latest.json --threshold {{ threshold }}

# Refresh the stored baseline for this size from a fresh run
bench-baseline vault_size="500":
    just bench {{ vault_size }}
    cp benchmarks/latest.json benchmarks/baseline-{{ vault_size }}.json

# Trace :Vault notes performance step-by-step (default: real knowledge vault)
trace-notes vault_root="":
    NVIM_LISTEN_ADDRESS= nvim --headless -u {{ minimal_init }} -l scripts/trace_vault_notes.lua {{ if vault_root != "" { "-- --vault-root " + vault_root } else { "" } }}

# Run benchmarks for all sizes (100, 500, 1000)
bench-all:
    just bench 100
    just bench 500
    just bench 1000

# Format Lua files with StyLua
fmt:
    stylua lua/ tests/
