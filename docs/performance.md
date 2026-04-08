# Performance Baselines

Captured 2026-04-08 on macOS arm64 (Apple Silicon).

- **Neovim**: v0.13.0-dev
- **LuaJIT**: 2.1.1774896198
- **OS**: macOS arm64

## vault.nvim — Startup & scan

All times in milliseconds (median of N runs).

| Metric | 100 notes | 500 notes | 1000 notes |
|--------|----------:|----------:|-----------:|
| `setup()` | 0.498 | 0.543 | 0.553 |
| `commands module load` | 1.199 | 1.314 | 1.284 |
| `Scanner.paths()` cold | 2.782 | 9.401 | 16.984 |
| `Scanner.slugs()` cold | 1.580 | 5.024 | 9.162 |
| `Scanner.tags()` | 2.140 | 7.660 | 14.447 |
| `Scanner.wikilinks()` | 2.334 | 8.381 | 16.171 |
| `Scanner.properties()` | 3.780 | 16.851 | 33.288 |
| `Scanner.lines()` Lua | 6.056 | 29.242 | 52.809 |
| `Scanner.paths_and_wikilinks_cached()` cold | 4.030 | 16.233 | 30.561 |
| `Scanner.paths_and_wikilinks_cached()` warm | 1.702 | 10.146 | 20.804 |
| `Scanner.paths_and_wikilinks_cached()` 1 file changed | 2.222 | 10.540 | 20.794 |

## vault.nvim — Workflow

All times in milliseconds (median of N runs).

| Metric | 100 notes | 500 notes | 1000 notes |
|--------|----------:|----------:|-----------:|
| `Notes.from_paths()` | 0.139 | 0.578 | 1.169 |
| `grid build_records()` | 1.682 | 11.804 | 22.397 |
| `grid open() [preloaded]` | 5.923 | 20.899 | 37.359 |
| `grid save no-op (:w)` | 0.044 | 0.055 | 0.069 |
| `grid on_save update` | 5.213 | 5.116 | 5.161 |
| `grid on_save rename` | 16.418 | 39.439 | 69.194 |
| `Watcher.handle_rename()` | 14.059 | 28.010 | 43.873 |

### Observations

- `Scanner.lines()` remains the slowest pure-scan path because it is still pure Lua file I/O.
- `Scanner.paths_and_wikilinks_cached()` now has explicit cold, warm, and 1-file-changed measurements. Warm and single-file-changed runs are much cheaper than a cold scan, but they still scale with vault size because every file's metadata must be checked.
- `grid build_records()` and `grid open()` scale roughly linearly with note count and now replace the old synthetic `grid data prep` placeholder.
- `grid on_save update` stays nearly flat across fixture sizes because it mutates one note.
- `grid on_save rename` and `Watcher.handle_rename()` scale with vault size because they scan the vault and patch inbound links.

## vimtable.nvim — Grid Rendering & Handlers

All times in milliseconds (median of N runs).

| Metric                         | 50 records | 200 records | 500 records | 1000 records |
|--------------------------------|-----------:|------------:|------------:|-------------:|
| `render.data_lines`            |      0.117 |       0.502 |       1.420 |        2.944 |
| `render.build_lines`           |      0.110 |       0.497 |       1.421 |        2.824 |
| `conceal.apply_all`            |      0.188 |       0.814 |       2.007 |        4.176 |
| `conceal.apply_line`           |      0.006 |       0.006 |       0.005 |        0.005 |
| `highlights.apply`             |      0.066 |       0.308 |       0.650 |        1.367 |
| `validation.update`            |      0.176 |       0.777 |       2.114 |        4.331 |
| `row_identity.rebind_by_order` |      0.000 |       0.000 |       0.000 |        0.000 |
| `signs.update`                 |      0.183 |       0.771 |       2.022 |        4.229 |
| `snapshot.diff` (no changes)   |      0.194 |       0.822 |       2.149 |        4.628 |
| **TextChanged handler**        |  **0.559** |   **2.571** |   **6.299** |   **13.108** |
| `Grid.new` (construction)      |      1.675 |       2.978 |       5.373 |        8.406 |
| `Calendar.new` (+rebuild)      |      1.909 |       2.250 |       2.233 |        2.489 |

### Observations

- **TextChanged handler is the critical hotspot**: 13ms at 1000 records. This fires on every normal-mode edit. It runs `conceal.apply_all` + `signs.update` + `validation.update` sequentially — all three walk the entire buffer.
- `conceal.apply_all` at 4.2ms (1000 rows) clears ALL extmarks then re-applies on EVERY line. For a 50-line viewport, this is ~20x more work than needed.
- `validation.update` (4.3ms) and `signs.update` (4.2ms) have the same full-buffer-walk problem.
- `conceal.apply_line` is 0.005ms — 800x faster than `apply_all`. This confirms viewport-scoping would be a massive win.
- `row_identity.rebind_by_order` is essentially free (extmark-based, no buffer reads).
- `Calendar.new` is roughly constant across record counts — the calendar grid is fixed-size (month grid), only card placement scales.

## Top 5 Critical Hotspots

1. **`grid on_save rename`** — 69.2ms at 1000 notes
2. **`Scanner.lines()`** — 52.8ms at 1000 notes
3. **`Watcher.handle_rename()`** — 43.9ms at 1000 notes
4. **`Scanner.properties()`** — 33.3ms at 1000 notes
5. **TextChanged handler** — 13.1ms at 1000 rows (vimtable full-buffer decoration path)

## Running Benchmarks

```bash
# vault.nvim
just bench 500        # Single size
just bench-check 500  # Compare latest run to stored baseline
just bench-all        # All sizes (100, 500, 1000)

# vimtable.nvim
make bench BENCH_N=500    # Single size
```

Results are saved to `benchmarks/latest.json` and `benchmarks/baseline-*.json`.
