# vault.nvim justfile

# System detection
os := os()
lib_ext := if os == "macos" { "dylib" } else { "so" }
target := "lua/vault_core.so"
rustflags := if os == "macos" { "-C link-arg=-undefined -C link-arg=dynamic_lookup" } else { "" }
minimal_init := "tests/minimal_init.lua"

# Default: build + reload
default: build reload

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

# Format Lua files with StyLua
fmt:
    stylua lua/ tests/
