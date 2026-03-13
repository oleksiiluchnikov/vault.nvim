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
