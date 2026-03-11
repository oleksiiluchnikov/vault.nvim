## vault.nvim Architecture Refactor Blueprint

*2026-03-11*

This document describes the target architecture for refactoring `vault.nvim` into a noun-owned, CLI-friendly, LLM-friendly system without introducing mirrored folder trees or a stale central API facade.

---

### Goal

Make `vault.nvim` easy to navigate by domain noun, easy to operate by command grammar, and hard to let rot over time.

The refactor should preserve the original domain-first mental model while separating shared views, command registration, and user-configurable policy.

---

### Core decisions

- Keep the codebase organized around owning nouns: `notes`, `tags`, `taxonomy`, `tasks`, `bases`.
- Keep `grid` as the shared editing/view primitive. `grid` is a good name and should stay.
- Do not introduce a literal `domain/` folder.
- Do not make `vault.api` the architecture. A hand-maintained central facade will go stale.
- Let each owning package expose its own Lua facade and its own command spec.
- Move generic views out of `bases/views/*` into `views/*`.
- Move user-facing policy and preferred defaults out of hardcoded locals and into config.

---

### Important invariant

`notes.data` was intentional and should remain intentional.

The refactor should not flatten `note.data.*` into random top-level note fields just to make the file tree look cleaner. The `note` / `note.data` split is a useful boundary between object behavior and loaded note data, and it already appears throughout the codebase in a consistent way.

So the refactor should preserve:

- `note.data.path`
- `note.data.slug`
- `note.data.relpath`
- `note.data.frontmatter`
- `note.data.content`
- `note.data.inlinks`
- `note.data.outlinks`

This is an architectural seam, not accidental nesting.

#### `note.data` contract

The semantic split should be:

- `note` - behavior and operations
- `note.data` - structured, file-backed payload of one note
- `notes` - collection, query, and batch operations over many notes

`note.data` is the right home for:

- file identity like `path`, `relpath`, `slug`, `stem`
- parsed content like `content`, `body`, `frontmatter`, `headings`
- indexed graph data like `inlinks`, `outlinks`, `dangling_links`, `tags`
- stable derived note facts like title, type, status, stats

`note.data` is not the right home for:

- UI state
- buffer state
- command/session state
- temporary workflow decisions
- view-specific flattened row records
- unrelated cross-note aggregate state

Operationally, `note.data` should remain a live mutable record for note-owned facts like rename/move updates. It should not become a junk drawer for transient runtime state.

---

### North star

Every important concept should answer exactly one of these questions:

- What is it?
- How is it shown?
- What can I do with it?

The mapping is:

- nouns own meaning
- views own presentation
- commands own grammar
- config owns policy
- factories own creation defaults
- aliases own backward compatibility

---

### Target package map

```text
lua/vault/
  init.lua
  config.lua

  commands/
    init.lua
    registry.lua
    aliases.lua
    help.lua

  views/
    grid.lua
    list.lua
    kanban.lua
    calendar.lua
    picker.lua
    shared.lua

  notes/
    init.lua
    commands.lua
    paths.lua
    create.lua
    merge.lua
    move.lua
    retarget.lua
    find.lua
    note/
      init.lua
      data.lua

  tags/
    init.lua
    commands.lua
    promote.lua
    rename.lua
    documentation.lua

  taxonomy/
    init.lua
    commands.lua
    classify.lua
    audit.lua
    rename.lua
    plan.lua

  tasks/
    init.lua
    commands.lua
    paths.lua
    create.lua
    recur.lua
    doctor.lua
    policy.lua
    query.lua

  bases/
    init.lua
    commands.lua
    query.lua
    open.lua
```

Notes:

- no `domain/`
- no mirrored `workflows/` tree
- no mirrored `capabilities/` tree
- one owning package per noun
- one shared `views/` package

---

### Public Lua API

The public Lua API should come from noun packages, not from a central stale facade.

Stable entrypoints:

- `require("vault.notes")`
- `require("vault.tags")`
- `require("vault.taxonomy")`
- `require("vault.tasks")`
- `require("vault.bases")`
- `require("vault.views.grid")`

Each noun package should have exactly one small facade in its `init.lua`.

Example shape:

```lua
local M = {}

M.merge = require("vault.notes.merge").run
M.move = require("vault.notes.move").run
M.retarget = require("vault.notes.retarget").run
M.create = require("vault.notes.create").create
M.paths = require("vault.notes.paths")

return M
```

`vault.api` now remains only as a lightweight orchestration facade. Core ownership has moved into noun-owned modules.

---

### Command grammar

The CLI must be regular enough that humans and LLMs can infer the next command.

Canonical forms:

- `:Vault <noun> <verb> [args]`
- `:Vault <noun> view <view> [args]`
- `:Vault <noun> <dangerous-verb> preview|apply|undo`

Examples:

- `:Vault note merge`
- `:Vault note move`
- `:Vault tag promote`
- `:Vault taxonomy classify`
- `:Vault taxonomy audit`
- `:Vault taxonomy rename preview`
- `:Vault taxonomy rename apply`
- `:Vault taxonomy rename undo`
- `:Vault task recur sweep`
- `:Vault base view grid`
- `:Vault task view kanban`

Rules:

- nouns first
- verbs second
- views always behind `view`
- destructive operations expose `preview` before `apply`
- old command names survive only as aliases

---

### Command registry architecture

The central dispatcher should stop owning feature logic.

Each noun package exports a `commands.lua` spec file.

Example shape:

```lua
local taxonomy = require("vault.taxonomy")

return {
  { path = { "taxonomy", "classify" }, run = taxonomy.classify },
  { path = { "taxonomy", "audit" }, run = taxonomy.audit },
  { path = { "taxonomy", "rename", "preview" }, run = taxonomy.rename.preview },
  { path = { "taxonomy", "rename", "apply" }, run = taxonomy.rename.apply },
  { path = { "taxonomy", "rename", "undo" }, run = taxonomy.rename.undo },
}
```

`lua/vault/commands/registry.lua` should aggregate all command specs.

`lua/vault/commands/init.lua` should only:

- register `:Vault`
- dispatch into the registry
- provide completion/help via registry metadata

It should not contain business logic for tasks, taxonomy, note operations, or view behavior.

---

### Config architecture

`lua/vault/config.lua` should remain the single normalization and validation layer, but it should stop being the place where every domain's defaults are invented ad hoc.

Config ownership model:

- `config.lua` merges and validates
- noun packages define their own defaults and readers
- views define their own defaults and readers
- callers depend on package readers, not raw `config.options` whenever possible

Target setup shape:

```lua
require("vault").setup({
  root = "~/knowledge",
  dirs = { ... },

  notes = {
    ext = ".md",
    create = {
      slug_template = "note-%Y%m%d%H%M%S",
    },
    journal = {
      filename_format = "%Y-%m-%d %A",
    },
  },

  tags = {
    docs_dir = "Categories",
  },

  taxonomy = {
    field = "categories",
    reference_prefix = "category - ",
    classify = {
      columns = { "slug", "title", "categories", "file.mtime" },
      readonly_columns = { "slug", "title", "file.mtime" },
      dirs = nil,
    },
    rename = {
      require_preview = true,
      update_links = true,
      chunk_size = 25,
      skip_collisions = true,
    },
    mapping = { ... },
  },

  tasks = {
    dir = "Tasks",
    fields = {
      status = "status",
      priority = "priority",
      blocked_by = "blocked_by",
    },
    defaults = {
      status = "[[Status - Backlog]]",
      executor = "[[Executor - Human]]",
      category = "[[Category - Green Task]]",
      priority = "[[Priority - Medium]]",
    },
    status_order = { ... },
    priority_order = { ... },
    completed_statuses = { ... },
    aliases = { ... },
    transitions = { ... },
    recurrence = {
      rules = "builtin",
    },
  },

  views = {
    grid = {
      default_columns = { "slug", "title", "status", "tags" },
      identity_mode = "conceal",
      delete_hard_cap = 100,
      create_hard_cap = 100,
      row_hl = { ... },
    },
    kanban = { ... },
    calendar = { ... },
    list = { ... },
    picker = { ... },
  },
})
```

---

### Config extraction plan

The refactor must export hardcoded and preferred options into config along the way.

#### Notes

Move into `notes.*` config:

- note extension currently in `config.options.ext`
- journal filename format currently hardcoded in commands
- generated note slug templates currently duplicated in multiple places
- note path policies currently rebuilt with raw string concatenation

Add helpers:

- `vault.notes.paths.for_slug(slug)`
- `vault.notes.paths.for_relpath(relpath)`
- `vault.notes.paths.daily(date)`
- `vault.notes.create(spec)`

#### Tasks

Move into `tasks.*` config:

- `dir`
- field names for status, priority, blocked_by
- default status/executor/category/priority
- status order
- priority order
- completed statuses
- alias map for status normalization
- transition graph
- recurrence policy and accepted rule set

Add helpers:

- `vault.tasks.paths.dir_abs()`
- `vault.tasks.create(spec)`
- `vault.tasks.policy.statuses()`
- `vault.tasks.policy.normalize_status(value)`
- `vault.tasks.policy.can_transition(from, to)`
- `vault.tasks.policy.next_due(values, completed_iso)`

#### Taxonomy

Move into `taxonomy.*` config:

- taxonomy field
- reference prefix
- mapping
- classify columns and readonly columns
- classify dirs
- rename preview requirement
- rename chunk size
- rename collision policy
- link update policy

Add helpers:

- `vault.taxonomy.config.get()`
- `vault.taxonomy.plan.build(...)`

#### Views

Move into `views.*` config:

- grid default columns
- grid identity mode
- grid delete/create hard caps
- grid row highlights
- kanban grouping defaults and layout
- calendar date field / link date fields / first day / limits
- list defaults
- picker affordances like `show_actions`

#### Global but still valid

Keep globally shared policy where it truly crosses domains:

- `wikilinks.*`
- `watcher.*`
- `merge.*`
- `duplicates.*`
- `log.*`
- `notify.*`
- `typecheck.*`

---

### Shared views strategy

The current `bases/views/*` area mixes a real shared view layer with base-specific ownership.

Target rule:

- generic view code lives in `views/*`
- noun packages adapt data into those views
- base-specific rules stay in `bases/*`

This especially applies to:

- `grid`
- `list`
- `kanban`
- `calendar`

`grid` should remain generic and reusable. Taxonomy, tasks, and bases should each pass adapters or options into it instead of forking new view logic.

---

### Factories and paths

To kill duplication, creation and path logic must stop living inside commands and views.

Add owner-level factories:

- `vault.notes.create(spec)`
- `vault.tasks.create(spec)`

Add owner-level path helpers:

- `vault.notes.paths.*`
- `vault.tasks.paths.*`
- `vault.tags.documentation_path(...)`

Commands and views should request creation or paths from these helpers instead of assembling strings like `root .. "/" .. slug .. ext` themselves.

---

### Package-specific refactor targets

#### Notes

Keep `note.data` and `notes.note.data` intact.

Extract:

- path helpers
- creation helpers
- merge/move/retarget entrypoints

Do not collapse `note` behavior and `note.data` into one flat blob.

#### Tags

Keep tag operations under `tags/*`.

Extract docs path policy into config instead of recomputing docs directories in several files.

#### Taxonomy

Split by responsibility without losing the noun:

- `taxonomy/init.lua` - public facade
- `taxonomy/classify.lua` - classify workflow
- `taxonomy/audit.lua` - audit workflow
- `taxonomy/plan.lua` - rename planning primitives
- `taxonomy/rename.lua` - preview/apply/undo

Taxonomy remains a noun package. The split is by verb file, not by mirrored folder tree.

#### Tasks

Split current `tasks/notes.lua` into:

- `tasks/policy.lua` - statuses, aliases, transitions, recurrence
- `tasks/create.lua` - task-note creation defaults
- `tasks/query.lua` - task-note loading/scanning/filtering
- `tasks/recur.lua` - recurrence workflows
- `tasks/doctor.lua` - validation/repair workflows

This is the highest-leverage cleanup because `tasks/notes.lua` currently mixes data access, policy, parsing, creation, and workflows.

#### Bases

Keep bases as a noun package, but stop using `bases/views/*` as the hiding place for generic UI primitives.

---

### Migration order

This should be staged, not a big-bang rewrite.

#### Phase 1 - Freeze command grammar

- define canonical noun-first commands
- introduce command registry and aliases
- keep old commands working through compatibility aliases

#### Phase 1.5 - Lock core note contract

- document the `note` / `note.data` / `notes` boundary in code comments and architecture docs
- preserve `notes.note.data` as the owning payload model
- do not flatten `note.data.*` into top-level note fields during any file moves
- reject refactor steps that smuggle UI or session state into `note.data`

#### Phase 2 - Extract shared views

- move generic grid/list/kanban/calendar/shared code into `views/*`
- leave compatibility require shims where needed

#### Phase 3 - Extract config-owned policy

- export hardcoded defaults into `notes.*`, `tasks.*`, `taxonomy.*`, `views.*`
- add package readers/helpers

#### Phase 4 - Refactor taxonomy

- split classify/audit/plan/rename
- move taxonomy command specs beside taxonomy facade

#### Phase 5 - Refactor tasks

- split policy/create/query/recur/doctor
- remove duplicated status and recurrence rules from scattered locations

#### Phase 6 - Refactor notes and tags

- centralize path and creation helpers
- move command specs beside owners

#### Phase 7 - Shrink central command dispatcher

- move all business logic out of `commands/init.lua`
- registry-driven completion/help only

#### Phase 8 - Deprecate `vault.api`

- keep only thin compatibility aliases
- stop adding new functionality there

---

### Execution status

Completed in code:

- command registry scaffolding
- taxonomy pilot command specs
- package-owned config readers for taxonomy, tasks, and grid views
- shared `vault.views.*` namespace
- task policy / create / paths extraction
- taxonomy split into classify / audit / plan / rename modules
- note create / paths helpers
- compat command extraction and `vault.api` de-emphasis

Key commits:

- `aff7668` - chunks 0-2
- `90c4e2f` - chunk 3
- `869c75c` - chunk 4
- `c8e5c7d` - chunk 5
- `21afdba` - chunk 6
- `4b4970b` - chunk 7

The foundational architecture refactor is complete.

Recent cleanup after the main migration:

- removed the temporary `commands/compat.lua` compatibility layer
- collapsed command-layer API access to a direct workflow helper
- removed the stale `vault.api.refresh_buffers` dependency from note writes
- added package-local command specs for `notes`, `tags`, `properties`, and `bases`
- made `vault.views.shared` the canonical shared view implementation
- moved merge/promote/retarget workflow bodies into noun-owned workflow modules
- removed the old `bases/views/*` shim namespace so `vault.views.*` is canonical

### Final status

- noun-owned modules are now the canonical owners
- `vault.views.*` is the only view namespace
- package-local command specs are established across the refactored areas
- the original migration plan has been executed end to end

---

### Anti-rot guardrails

- no new public feature ships without an owning noun package
- no new command ships without a package-local `commands.lua` spec
- no new creation logic lives directly in a view or command callback
- no new user-facing policy ships as a local hardcoded constant if it should reasonably be configurable
- no new feature gets added to `vault.api`
- generic UI primitives do not go back under `bases/views/*`

---

### Acceptance criteria

- a contributor can find the owner of a feature in under 30 seconds
- `:Vault` command completion is driven from the command registry, not a giant hand-maintained tree
- generic views live in `views/*`, not under `bases/views/*`
- note and task path generation are centralized in owner helpers
- task policy is no longer duplicated between config and implementation locals
- taxonomy logic is split by verb file while preserving taxonomy as the owning noun
- `note.data` remains a first-class boundary and is not flattened away
- `note.data` contains note payload, not UI/session/workflow-local state
- `vault.api` is no longer the architectural center of the plugin
- preferred defaults and hardcoded policy values are exported into config where appropriate

---

### Out of scope

- a literal `domain/` directory
- a mirrored `workflows/` or `capabilities/` tree
- a big-bang rewrite that breaks all commands at once
- removing `note.data`
- renaming `grid`

---

### Short diagnosis

The codebase should be organized by owning nouns, rendered through shared views, operated through a regular command grammar, and configured through explicit policy. The refactor succeeds when the structure matches that sentence and no second source of truth grows back.

---

### Refactor kickoff slice

Start with the smallest high-leverage slice that improves structure without forcing a big-bang rewrite.

1. Introduce `commands/registry.lua` and move one noun's command definitions beside its owner while keeping aliases in place.
2. Add package-owned config readers for `taxonomy`, `tasks`, and `views.grid` without changing behavior.
3. Extract shared `grid` infrastructure out of `bases/views/grid.lua` only where it is genuinely generic.
4. Split `tasks/notes.lua` by policy first, because it currently mixes config, parsing, state rules, creation defaults, and workflows.
5. Split `taxonomy.lua` into classify/audit/plan/rename once command and config seams exist.

This order creates better seams before moving lots of code.
