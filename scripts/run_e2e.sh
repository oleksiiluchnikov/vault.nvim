#!/usr/bin/env bash
set -euo pipefail

readonly ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

cd "$ROOT_DIR"

NVIM_LISTEN_ADDRESS= nvim --headless --noplugin -u tests/minimal_init.lua -c "lua require('plenary.test_harness').test_directory('tests/e2e', {minimal_init='tests/minimal_init.lua', sequential=true})" -c qa!
