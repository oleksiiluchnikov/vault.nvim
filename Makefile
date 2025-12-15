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

all: build

build:
	@echo "Building for $(UNAME_S) with flags: $(RUSTFLAGS)"
	RUSTFLAGS="$(RUSTFLAGS)" cargo build --release
	cp target/release/libvault_core.$(LIB_EXT) $(TARGET)

clean:
	cargo clean
	rm -f $(TARGET)



.PHONY: test

# Run all plenary tests using the minimal init file to avoid loading the user's
# real Neovim config (~/.config/nvim/init.lua). This ensures tests run in a
# hermetic environment with only the dependencies set up in tests/minimal_init.lua.
# Usage: make test

test:
	@echo "Running tests with tests/minimal_init.lua"
	@nvim --headless -u tests/minimal_init.lua -c "PlenaryBustedDirectory tests" -c qa
