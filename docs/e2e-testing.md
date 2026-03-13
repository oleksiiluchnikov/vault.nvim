## E2E Testing

### Goal

`vault.nvim` end-to-end tests run real Neovim command and UI journeys against disposable cloned vaults.

### Safety model

- E2E always launches a fresh Neovim instance.
- E2E never reuses the developer's current editor session.
- E2E never targets the live `~/knowledge` vault directly.
- The harness clones the source vault into a disposable temp directory and mutates only that clone.

### Local runner

Run the full E2E suite with:

```bash
bash ./scripts/run_e2e.sh
```

### Artifacts

Failure artifacts are written under:

```text
tests/.artifacts/e2e/
```

Typical files include:

- `messages.txt`
- `current-buffer.txt`
- `current-buffer-body.txt`
- `vault-diff.txt`
- `timeout.txt`

### Debugging workflow

1. Re-run `bash ./scripts/run_e2e.sh` or the specific E2E spec.
2. Inspect the latest directory under `tests/.artifacts/e2e/`.
3. Read `messages.txt` first.
4. Compare `current-buffer-body.txt` with `vault-diff.txt` to understand whether the failure was UI state, command dispatch, or filesystem mutation.

---

## Watcher and External Integration Test Strategy

### Problem

Watcher-based flows (file system events → cache invalidation → UI refresh) and external integrations (Obsidian open-app, dictation tools, glow preview) are currently only covered by manual smoke testing or unit tests. They need an explicit strategy so they don't regress silently.

### Test layers

| Layer | Scope | Where | Speed |
|---|---|---|---|
| **Unit** | Watcher link-rewrite logic, rename detection | `tests/vault/watcher_*.lua` | Fast (<1s) |
| **Integration** | Watcher + real filesystem events in isolated Neovim | `tests/e2e/` (new) | Medium (5-10s) |
| **Manual smoke** | External app interop, dictation, glow | Documented checklist | Human |

### Watcher testing strategy

**Already covered (unit):**
- `watcher_spec.lua` — core Watcher class instantiation
- `watcher_rename_spec.lua` — rename detection and link rewriting
- `watcher_link_spec.lua` — wikilink patch logic after renames

**Recommended integration tests (E2E):**

1. **File-create watcher event**: Write a new `.md` file to the cloned vault via `vim.fn.writefile`, wait, verify the scanner picks it up.
2. **File-delete watcher event**: Delete a note file via `os.remove`, wait, verify the scanner drops it.
3. **External rename**: Rename a file via `os.rename`, wait, verify wikilinks referencing the old slug are detected as broken.

**Implementation approach:**

Watcher integration tests should reuse the existing E2E driver harness but with the `watcher` feature explicitly enabled:

```lua
-- In the E2E session's vault setup:
require("vault").setup({
    root = fixture_root,
    features = { watcher = true },
})
```

Then use `driver.lua` to write/delete/rename files from outside Neovim (via `vim.system`) and poll for state changes using `driver.expr` or `driver.lua`.

**Scope boundary:** Watcher E2E should stay in a separate spec file (`tests/e2e/watcher_integration_spec.lua`) to avoid slowing the core E2E suite. The watcher relies on `libuv` polling intervals, so tests must use generous `wait_for` timeouts (5-10s).

### External integration testing strategy

**Obsidian open-app:**
- vault.nvim can launch `open obsidian://open?vault=...&file=...`
- **Not automatable** in E2E — the target app isn't installed in CI.
- **Strategy:** Manual checklist item. Document the command and expected behavior in a `docs/manual-smoke-tests.md` file.

**Dictation/glow-style tools:**
- These are editor-external tools that write to note files on disk.
- **Strategy:** Covered by the watcher integration tests above — an external write to a note file is the same event whether it comes from dictation or `echo >> file.md`.

**NAS/network-mounted vaults:**
- Error handling for disconnected NAS is tested by unit tests (`vault-core` has a separate `NAS disconnect error handling` task).
- **Strategy:** Unit test coverage is sufficient. E2E would require actual network mount simulation, which is out of scope.

### Recommended scope boundaries

| Flow | Test layer | Rationale |
|---|---|---|
| Watcher core logic | Unit | Fast, deterministic, already exists |
| Watcher + real fs events | E2E (separate spec) | Needs real Neovim + libuv loop |
| External app launch | Manual checklist | Needs target app installed |
| External file writes | Watcher E2E | Same as watcher fs events |
| Network/NAS errors | Unit | Simulated error paths |
| CI stability | E2E main suite only | Watcher E2E is opt-in via env var |

### CI integration

Watcher E2E tests should be gated behind an env var (`VAULT_TEST_WATCHER=1`) because:
1. They are inherently slower (libuv polling delays).
2. They may be flaky on CI runners with different filesystem event semantics.
3. The core E2E suite should remain fast and stable.

```yaml
# In .github/workflows/e2e.yml
- name: Run watcher integration tests
  if: env.VAULT_TEST_WATCHER == '1'
  run: VAULT_TEST_WATCHER=1 bash ./scripts/run_e2e.sh watcher
```
