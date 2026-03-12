## PRD: End-to-End Testing for vault.nvim

*2026-03-12*

### Goal

Add a Neovim-native end-to-end testing system for `vault.nvim` that validates real user journeys through commands, pickers, views, and filesystem mutations.

The system should complement the existing Plenary unit/integration suite, not replace it.

---

### Problem

`vault.nvim` already has strong unit and integration coverage, but important failures still escape into manual smoke testing:

- command -> UI -> file mutation flows
- Telescope picker journeys
- resolve-picker create/rewrite paths
- duplicate review interaction
- taxonomy process/grid save loops
- tasks lifecycle flows
- kanban/calendar interaction

These bugs often live in runtime seams, not in isolated module logic.

---

### Product outcome

`vault.nvim` gets a dedicated `tests/e2e/` layer that:

- launches a fresh Neovim process per scenario
- launches that process in a separate Neovim instance/window from the developer's working editor
- runs against a temporary copy of a fixture vault
- drives real `:Vault ...` commands and real key input
- captures useful artifacts on failure
- covers a small set of high-value user journeys first

For personal-vault testing, the source vault may be a copy of the maintainer's real vault, but the test run must always operate on a disposable cloned copy, never the live vault itself.

---

### Non-goals

V1 does not include:

- external Obsidian app automation
- pixel-perfect visual regression
- full cross-platform matrix
- browser-first automation for editor UI
- replacing existing unit/integration tests

---

### Best-practice strategy (March 2026)

For `vault.nvim`, the correct E2E architecture is layered:

1. unit tests for pure logic
2. integration tests in headless Neovim for host-runtime behavior
3. a thin E2E layer for real interactive journeys

This project should stay Neovim-native for E2E. Browser-style E2E frameworks are the wrong center of gravity here.

---

### Existing foundations

Strong foundations already exist:

- `tests/minimal_init.lua` for isolated plugin boot
- `tests/vault/commands/init_spec.lua` for command-level coverage
- `tests/vault/bases/views/grid_spec.lua` for process/grid integration
- `tests/vault/taxonomy_spec.lua` for taxonomy flows
- `tests/vault/tasks/notes_spec.lua` for task-note flows

The E2E system should reuse these conventions:

- fixed fixture roots
- watcher disabled by default
- deterministic plugin setup
- explicit filesystem assertions

---

### V1 scope

#### 1. Grid / Process journeys

- `:Vault process`
- edit row values
- `:w`
- reload
- undo

#### 2. Taxonomy journeys

- `:Vault classify`
- edit taxonomy field
- save and verify file mutation
- `:Vault taxonomy preview`
- `:Vault taxonomy apply`
- `:Vault taxonomy undo-last`

#### 3. Tasks journeys

- `:Vault tasks promote`
- `:Vault tasks status`
- `:Vault tasks recur now`
- `:Vault tasks recur sweep`
- `:Vault tasks pick-next`
- `:Vault tasks doctor`

#### 4. Resolve-picker journeys

- note merge
- note retarget
- tag promote
- create vs rewrite paths

#### 5. Duplicate review journey

- open review
- preview keep A/B/recommended
- queue batch
- apply batch
- pause/resume

#### 6. View-surface journeys

- kanban open + create/move
- calendar open + create/move

#### 7. Picker health smoke

- `:Vault notes`
- `:Vault tags`
- `:Vault properties`
- `:Vault bases`
- gradients/highlight groups exist where expected

---

### User-facing definition of done

The E2E system is successful when:

- high-value user journeys fail in tests before they fail in manual use
- failures emit artifacts good enough to debug without rerunning blindly
- the suite is deterministic locally
- the suite is stable enough for CI

---

### Technical architecture

#### Test layers

- keep current unit/integration tests under `tests/vault/`
- add a new E2E layer under `tests/e2e/`

Suggested structure:

```text
tests/e2e/
  helpers/
    driver.lua
    fixture.lua
    artifacts.lua
    screen.lua
  commands/
    process_spec.lua
    taxonomy_spec.lua
    tasks_spec.lua
  pickers/
    resolve_picker_spec.lua
    health_spec.lua
  views/
    kanban_spec.lua
    calendar_spec.lua
  workflows/
    duplicates_spec.lua
```

#### Runtime model

Each scenario must:

- launch a fresh headless Neovim instance
- never reuse the developer's current interactive Neovim session
- use `tests/minimal_init.lua`
- use a temporary vault copy
- exit after one scenario

No shared process across E2E scenarios.

When running against a real vault dataset, the harness must first clone the source vault into a temporary directory and point `vault.nvim` at that clone. The source vault is strictly read-only from the harness point of view.

#### Driver model

The driver should use Neovim-native control:

- `vim.cmd("Vault ...")`
- key input / remote-send style interaction
- screen/buffer assertions
- filesystem assertions

No browser dependency.

#### Artifact model

On failure, store:

- command transcript
- notifications/messages
- visible screen snapshot
- relevant buffers
- vault diff/stat
- scenario metadata

---

### Determinism rules

Every E2E scenario must:

- fix `lines` / `columns`
- disable watcher unless explicitly testing watcher behavior
- use a temp vault copy
- use explicit wait predicates instead of sleeps where possible
- isolate state between scenarios
- avoid blocking `vim.fn.confirm()` and noisy notify flows

Additional hard safety rules:

- never run E2E against the live `~/knowledge` vault path
- always launch in a separate Neovim instance/window/process from the developer's normal editing session
- preserve the original vault copy as read-only input; mutate only the disposable clone

---

### Highest-value first scenarios

The first five scenarios should be:

1. `:Vault classify` -> edit -> save
2. `:Vault taxonomy preview/apply/undo-last`
3. `:Vault tasks promote` -> status -> pick-next
4. `:Vault note merge` / retarget resolve picker
5. `:Vault duplicates review tags test kind divergent`

These give the best confidence per unit of effort.

---

### Risks

#### 1. UI flakiness

- floating windows
- async redraw timing
- picker state transitions

Mitigation:

- predicate-based waits
- fresh process per scenario

#### 2. Prompt/RPC deadlocks

Mitigation:

- disable/block problematic notify paths in test harness
- explicitly avoid blocking prompts in E2E

#### 3. Fixture corruption

Mitigation:

- temp copy per scenario

#### 4. Maintenance cost

Mitigation:

- keep E2E suite intentionally small
- only cover high-value journeys

---

### Acceptance criteria

- `tests/e2e/` exists with reusable helpers
- each scenario runs in a fresh Neovim process
- each scenario uses a temporary vault copy
- failure artifacts are persisted
- V1 covers process, taxonomy, tasks, resolve-picker, and duplicate-review journeys
- CI can run the suite reliably

---

### Recommendation

Do not start by building a giant universal harness.

Start with a small, disciplined, Neovim-native E2E layer and five critical scenarios. Then expand only where real regressions justify it.
