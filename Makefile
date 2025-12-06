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

