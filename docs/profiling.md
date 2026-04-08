# Profiling Guide

How to profile vault.nvim and vimtable.nvim workflows.

## Decision Tree: Which Tool Do I Use?

```
"Something is slow"
  │
  ├─ Which module/function is the bottleneck?
  │   └─ snacks.nvim profiler (instrumentation)
  │
  ├─ Which LINES in a known-slow function are hottest?
  │   └─ perfanno.nvim (LuaJIT sampling profiler)
  │
  ├─ Is startup regressing?
  │   └─ nvim --startuptime
  │
  └─ Are optimizations holding in CI?
      └─ make bench / just bench (automated regression)
```

## Tool 1: snacks.nvim Profiler

**Purpose**: Find which module/function is hot via Lua instrumentation.

**Best for**: "Where is time being spent?" — function-level attribution across the codebase.

### Setup

Add to your Neovim config (user-level, not shipped with the plugin):

```lua
-- lazy.nvim
{
  "folke/snacks.nvim",
  opts = {
    profiler = { enabled = true },
  },
  keys = {
    { "<leader>pp", function() Snacks.profiler.toggle() end, desc = "Toggle profiler" },
    { "<leader>ph", function() Snacks.profiler.highlight() end, desc = "Toggle highlights" },
    { "<leader>ps", function() Snacks.profiler.scratch() end, desc = "Profiler scratch" },
  },
}
```

### Profiling a Workflow

1. Press `<leader>pp` to start recording.
2. Perform the workflow (e.g., `:Vault process`, edit cells, `:w`).
3. Press `<leader>pp` again to stop.
4. Press `<leader>ps` to open the scratch buffer with results.
5. In the picker, group by `def_plugin` to see per-plugin totals, or filter by `modname` (e.g., `vimtable.views.grid.conceal`).

### Profiling Startup

```lua
-- In your init.lua, before any plugin loads:
if vim.env.PROF then
  require("snacks.profiler").startup({
    startup = {
      event = "VimEnter",  -- stop profiling after VimEnter
    },
  })
end
```

Then run:

```bash
PROF=1 nvim
```

### Interpreting Results

- **Self time**: time spent in the function body itself.
- **Total time**: self + time in functions it called.
- Look for functions with high self-time — those are the actual hotspots.
- Functions with high total-time but low self-time are dispatchers — the real cost is in their callees.

### Caveats

- Instrumentation adds overhead (~5-15% per function call). This distorts results for very fast functions called thousands of times (e.g., `cell.pad()`).
- For render loops and high-frequency handlers, prefer perfanno.nvim instead.

## Tool 2: perfanno.nvim (LuaJIT Sampling Profiler)

**Purpose**: Find which lines within a known function are hottest, using statistical sampling.

**Best for**: "I know `conceal.apply_all` is slow — which lines inside it?" — line-level profiling with minimal overhead.

### Setup

```lua
-- lazy.nvim
{
  "t-troebst/perfanno.nvim",
  config = function()
    require("perfanno").setup({
      line_highlights = require("perfanno.util").make_highlights(
        "#331111", "#773333"  -- gradient from cool to hot
      ),
    })
  end,
  cmd = {
    "PerfLuaProfileStart", "PerfLuaProfileStop",
    "PerfAnnotate", "PerfHottestLines", "PerfAnnotateFunction",
  },
}
```

### Profiling a TextChanged Handler

1. Open a process buffer: `:Vault process`
2. Start profiling: `:PerfLuaProfileStart`
3. Make several edits (type, delete, move lines) — the TextChanged handler fires each time.
4. Stop profiling: `:PerfLuaProfileStop`
5. Annotate: `:PerfAnnotate` — each line gets a heat indicator showing how much time was spent on it.
6. Or use `:PerfHottestLines` to see a sorted Telescope picker of the hottest lines across all files.

### Reading Annotations

- Lines are colored on a gradient from cool (little time) to hot (lots of time).
- A virtual text percentage shows relative time spent on each line.
- Focus on lines with >5% — those are your optimization targets.

### When to Use perfanno Over snacks

| Scenario | Tool |
|----------|------|
| "What's slow?" — broad survey | snacks.nvim |
| "Line 82 of conceal.lua does what?" — deep dive | perfanno.nvim |
| Render loops (TextChanged, CursorMoved) | perfanno.nvim |
| High-frequency callbacks (1000+ calls/sec) | perfanno.nvim |
| Startup profiling | snacks.nvim |
| Module load ordering | snacks.nvim |

## Tool 3: `nvim --startuptime`

**Purpose**: Track startup time regression.

```bash
nvim --startuptime /tmp/startup.log -c qa
sort -k2 -n /tmp/startup.log | tail -20
```

This shows time spent loading each script/module during startup. Look for:
- `vault/init.lua` — should be <1ms
- `vault/commands/init.lua` — currently ~1.3ms (eager telescope picker require)
- Any module >5ms is a candidate for lazy-loading.

## Tool 4: Automated Benchmarks (`just bench` / `just bench-check`)

**Purpose**: Detect performance regressions automatically.

```bash
# vault.nvim
just bench 500          # Run with 500-note fixture
just bench-check 500    # Compare latest run against baseline-500.json
just bench-all          # Run 100, 500, 1000

# vimtable.nvim
make bench BENCH_N=500  # Run with 500 records
```

Results are saved to `benchmarks/latest.json`. Reports now include `median`, `p95`, and `p99` so you can separate broad regressions from tail-latency spikes.

### Comparing Before/After

```bash
just bench 500
just bench-check 500
```

### CI Integration

CI uploads a fresh `benchmarks/latest.json` artifact for the 500-note fixture on pull requests. Local `just bench-check` remains the authoritative regression gate because absolute timings are machine-sensitive.
