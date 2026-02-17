# System detection
UNAME_S := $(shell uname -s)

# Default flags
RUSTFLAGS :=

# macOS specific linker flags (The Fix)
ifeq ($(UNAME_S),Darwin)
	LIB_EXT := dylib
	TARGET := lua/vault_core.so
	# Force the linker to ignore missing Lua symbols
	RUSTFLAGS := -C link-arg=-undefined -C link-arg=dynamic_lookup
else
	LIB_EXT := so
	TARGET := lua/vault_core.so
endif

all: build reload

build:
	@echo "Building for $(UNAME_S) with flags: $(RUSTFLAGS)"
	RUSTFLAGS="$(RUSTFLAGS)" cargo build --release
	cp target/release/libvault_core.$(LIB_EXT) $(TARGET)

clean:
	cargo clean
	rm -f $(TARGET)

# send the 'Lazy reload vault.nvim' to the neovim instance
reload:
	@if command -v nvim-server >/dev/null 2>&1; then \
		open "nvim://cmd?run=Lazy%20reload%20vault.nvim"; \
	else \
		echo "nvr (neovim-remote) not found. Please install it or reload manually."; \
	fi

check:
	lua_cmd="vim.api.nvim_feedkeys(':lua P(require(\"vault.notes\")():get_random())', 'n', false)"; \
	encoded=$$(printf '%s' "$$lua_cmd" | jq -sRr @uri); \
	open "nvim://cmd?run=lua%20$$encoded"

# .PHONY: test

# Run all plenary tests using the minimal init file to avoid loading the user's
# real Neovim config (~/.config/nvim/init.lua). This ensures tests run in a
# hermetic environment with only the dependencies set up in tests/minimal_init.lua.
# Usage: make test

# Run plenary tests in a hermetic environment using minimal_init.lua
# This avoids loading the user's config and ensures reproducible test results

MINIMAL_INIT := tests/minimal_init.lua

test-all:
	@printf "Running all tests...\n"
	@lua_cmd='require("plenary.test_harness").test_directory("tests", {minimal_init = "$(MINIMAL_INIT)"})'; \
	encoded=$$(printf '%s' "$$lua_cmd" | jq -sRr @uri); \
	open "nvim://cmd?run=lua%20$$encoded"

test-note:
	@printf "Running tests/notes/...\n"
	@lua_cmd='require("plenary.test_harness").test_directory("tests/notes", {minimal_init = "$(MINIMAL_INIT)"})'; \
	encoded=$$(printf '%s' "$$lua_cmd" | jq -sRr @uri); \
	open "nvim://cmd?run=lua%20$$encoded"

# Run tests for the currently open buffer
test-current:
	@printf "Running tests for current buffer...\n"
	@lua_cmd='local path=vim.api.nvim_buf_get_name(0);require("plenary.test_harness").test_file(path, {minimal_init = "$(MINIMAL_INIT)"})'; \
	encoded=$$(printf '%s' "$$lua_cmd" | jq -sRr @uri); \
	open "nvim://cmd?run=lua%20$$encoded"

test: reload test-current


.PHONY: test test-note test-current
