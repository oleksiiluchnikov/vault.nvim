-- tests/vault/bases/views/kanban_spec.lua
-- Unit tests for the kanban board vault adapter.
--
-- Run with: PlenaryBustedFile tests/vault/bases/views/kanban_spec.lua {minimal_init='tests/minimal_init.lua'}

local fixture_root = vim.fn.getcwd() .. "/tests/fixtures/demo-vault"

--- Helper: check if vault config is available.
local function has_vault_config()
  local ok, config = pcall(require, "vault.config")
  return ok and config.options and config.options.root and config.options.root ~= ""
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- 1. Pure-function unit tests
-- ═══════════════════════════════════════════════════════════════════════════════

describe("kanban (unit)", function()
  local gk

  before_each(function()
    package.loaded["vault.views.kanban"] = nil
    package.loaded["vault.views.shared"] = nil
    gk = require("vault.views.kanban")
  end)

  -- ── get_value_hl ──────────────────────────────────────────────────────────

  describe("get_value_hl", function()
    it("returns String for done/completed", function()
      assert.are.equal("String", gk._get_value_hl("done"))
      assert.are.equal("String", gk._get_value_hl("completed"))
      assert.are.equal("String", gk._get_value_hl("Done"))
    end)

    it("returns Function for active/in-progress", function()
      assert.are.equal("Function", gk._get_value_hl("active"))
      assert.are.equal("Function", gk._get_value_hl("in-progress"))
    end)

    it("returns Keyword for planned/todo", function()
      assert.are.equal("Keyword", gk._get_value_hl("planned"))
      assert.are.equal("Keyword", gk._get_value_hl("todo"))
    end)

    it("returns WarningMsg for on-hold", function()
      assert.are.equal("WarningMsg", gk._get_value_hl("on-hold"))
    end)

    it("returns ErrorMsg for blocked", function()
      assert.are.equal("ErrorMsg", gk._get_value_hl("blocked"))
    end)

    it("returns Comment for archived/cancelled", function()
      assert.are.equal("Comment", gk._get_value_hl("archived"))
      assert.are.equal("Comment", gk._get_value_hl("cancelled"))
    end)

    it("returns nil for unknown values", function()
      assert.is_nil(gk._get_value_hl("random"))
      assert.is_nil(gk._get_value_hl(""))
    end)
  end)

  -- ── resolve_group_field ───────────────────────────────────────────────────

  describe("resolve_group_field", function()
    local mock_notes

    before_each(function()
      mock_notes = {
        ["note-a"] = {
          data = {
            frontmatter = { status = "active" },
            tags = { "project", "status/active" },
            relpath = "Project/note-a.md",
          },
        },
        ["note-b"] = {
          data = {
            frontmatter = { status = "done" },
            tags = { "project", "status/done" },
            relpath = "Inbox/note-b.md",
          },
        },
        ["note-c"] = {
          data = {
            frontmatter = { status = "active" },
            tags = { "misc" },
            relpath = "Project/note-c.md",
          },
        },
      }
    end)

    it("resolves frontmatter mode with auto-derived values", function()
      local info = gk._resolve_group_field(mock_notes, "status", nil)
      assert.are.equal("frontmatter", info.mode)
      assert.are.equal("status", info.field_key)
      assert.is_nil(info.resolver)
      -- Should have "active" and "done" (sorted)
      assert.is_true(vim.tbl_contains(info.values, "active"))
      assert.is_true(vim.tbl_contains(info.values, "done"))
    end)

    it("respects explicit group_values ordering", function()
      local info = gk._resolve_group_field(mock_notes, "status", { "done", "active", "planned" })
      assert.are.equal("done", info.values[1])
      assert.are.equal("active", info.values[2])
      assert.are.equal("planned", info.values[3])
    end)

    it("appends unseen values from data when explicit values given", function()
      -- "active" and "done" exist in data; "planned" does not
      local info = gk._resolve_group_field(mock_notes, "status", { "planned" })
      assert.are.equal("planned", info.values[1])
      -- "active" and "done" should be appended
      local all_vals = table.concat(info.values, ",")
      assert.is_truthy(all_vals:find("active"))
      assert.is_truthy(all_vals:find("done"))
    end)

    it("resolves tag_prefix mode", function()
      local info = gk._resolve_group_field(mock_notes, "tags/status", nil)
      assert.are.equal("tag_prefix", info.mode)
      assert.are.equal("_tag_group", info.field_key)
      assert.are.equal("status", info.tag_prefix)
      assert.is_not_nil(info.resolver)
      -- Should find "active", "done", and "" (for note-c which has no status/ tag)
      assert.is_true(vim.tbl_contains(info.values, "active"))
      assert.is_true(vim.tbl_contains(info.values, "done"))
      assert.is_true(vim.tbl_contains(info.values, ""))
    end)

    it("tag_prefix resolver extracts suffix from record", function()
      local info = gk._resolve_group_field(mock_notes, "tags/status", nil)
      assert.is_not_nil(info.resolver)
      local result = info.resolver({ _raw_tags = { "project", "status/active" } }, "_tag_group")
      assert.are.equal("active", result)
    end)

    it("tag_prefix resolver returns empty for no matching tag", function()
      local info = gk._resolve_group_field(mock_notes, "tags/status", nil)
      local result = info.resolver({ _raw_tags = { "misc" } }, "_tag_group")
      assert.are.equal("", result)
    end)

    it("resolves directory mode", function()
      local info = gk._resolve_group_field(mock_notes, "directory", nil)
      assert.are.equal("directory", info.mode)
      assert.are.equal("_directory", info.field_key)
      assert.is_not_nil(info.resolver)
      assert.is_true(vim.tbl_contains(info.values, "Project/"))
      assert.is_true(vim.tbl_contains(info.values, "Inbox/"))
    end)

    it("directory resolver returns folder from record", function()
      local info = gk._resolve_group_field(mock_notes, "directory", nil)
      local result = info.resolver({ _directory = "Project/" }, "_directory")
      assert.are.equal("Project/", result)
    end)
  end)

  -- ── build_kanban_fields ───────────────────────────────────────────────────

  describe("build_kanban_fields", function()
    it("builds field list with format/parse closures", function()
      local fields = gk._build_kanban_fields({ "title", "tags" })
      assert.are.equal(2, #fields)
      assert.are.equal("title", fields[1].name)
      assert.are.equal("tags", fields[2].name)
      assert.is_function(fields[1].format)
      assert.is_function(fields[1].parse)
    end)

    it("marks readonly file columns", function()
      local fields = gk._build_kanban_fields({ "title", "file.ctime" })
      assert.is_falsy(fields[1].readonly)
      assert.is_true(fields[2].readonly)
      assert.are.equal("Comment", fields[2].hl_group)
    end)

    it("marks formula columns as readonly", function()
      local fields = gk._build_kanban_fields({ "formula.greeting" })
      assert.is_true(fields[1].readonly)
    end)

    it("normalizes column names", function()
      local fields = gk._build_kanban_fields({ "dir" })
      assert.are.equal("file.folder", fields[1].name)
    end)
  end)

  -- ── find_kanban_view ──────────────────────────────────────────────────────

  describe("find_kanban_view", function()
    it("returns nil when no views", function()
      local base = { data = {} }
      assert.is_nil(gk._find_kanban_view(base))
    end)

    it("returns nil when no kanban view exists", function()
      local base = { data = { views = {
        { type = "table", name = "Table" },
      } } }
      assert.is_nil(gk._find_kanban_view(base))
    end)

    it("finds the first kanban view", function()
      local base = { data = { views = {
        { type = "table", name = "Table" },
        { type = "kanban", name = "Board", group_by = "status",
          group_values = { "a", "b" }, display_fields = { "title" } },
      } } }
      local view = gk._find_kanban_view(base)
      assert.is_not_nil(view)
      assert.are.equal("kanban", view.type)
      assert.are.equal("Board", view.name)
      assert.are.equal("status", view.group_by)
    end)
  end)
end)

-- ═══════════════════════════════════════════════════════════════════════════════
-- 2. Integration tests (with demo vault notes)
-- ═══════════════════════════════════════════════════════════════════════════════

describe("kanban (integration)", function()
  if not has_vault_config() then
    pending("vault config not available")
    return
  end

  local gk

  before_each(function()
    package.loaded["vault.views.kanban"] = nil
    package.loaded["vault.views.shared"] = nil
    gk = require("vault.views.kanban")
  end)

  after_each(function()
    gk.close_all()
  end)

  -- ── flatten_notes ─────────────────────────────────────────────────────────

  describe("flatten_notes", function()
    it("flattens demo vault notes for frontmatter mode", function()
      local Notes = require("vault.notes")
      local notes = Notes()
      local notes_map = notes.map or {}
      assert.is_true(next(notes_map) ~= nil, "Expected at least one note")

      local group_info = gk._resolve_group_field(notes_map, "status", nil)
      local records, paths, mtimes = gk._flatten_notes(
        notes_map, { "title", "tags" }, group_info, nil)

      assert.is_true(#records > 0, "Expected at least one record")
      -- Each record should have an id and title
      for _, rec in ipairs(records) do
        assert.is_string(rec.id)
        assert.is_not_nil(rec.title)
      end
      -- paths should have entries
      assert.is_true(next(paths) ~= nil)
    end)

    it("flattens demo vault notes for directory mode", function()
      local Notes = require("vault.notes")
      local notes = Notes()
      local notes_map = notes.map or {}

      local group_info = gk._resolve_group_field(notes_map, "directory", nil)
      local records = gk._flatten_notes(
        notes_map, { "title" }, group_info, nil)

      assert.is_true(#records > 0)
      -- Each record should have _directory
      for _, rec in ipairs(records) do
        assert.is_string(rec._directory)
      end
    end)
  end)

  -- ── resolve_group_field with real notes ───────────────────────────────────

  describe("resolve_group_field with real notes", function()
    it("finds expected status values from demo vault", function()
      local Notes = require("vault.notes")
      local notes = Notes()
      local notes_map = notes.map or {}

      local info = gk._resolve_group_field(notes_map, "status", nil)
      assert.are.equal("frontmatter", info.mode)
      -- Demo vault has: active, done, draft, planning, archived, evergreen
      assert.is_true(vim.tbl_contains(info.values, "active"))
      assert.is_true(vim.tbl_contains(info.values, "done"))
      assert.is_true(vim.tbl_contains(info.values, "draft"))
    end)

    it("finds directory groups from demo vault", function()
      local Notes = require("vault.notes")
      local notes = Notes()
      local notes_map = notes.map or {}

      local info = gk._resolve_group_field(notes_map, "directory", nil)
      assert.are.equal("directory", info.mode)
      assert.is_true(vim.tbl_contains(info.values, "Project/"))
      assert.is_true(vim.tbl_contains(info.values, "Inbox/"))
      assert.is_true(vim.tbl_contains(info.values, "Journal/"))
    end)
  end)

  -- ── Base kanban view from fixture ─────────────────────────────────────────

  describe("base kanban view", function()
    it("finds kanban view in projects.base fixture", function()
      local Bases = require("vault.bases")
      local bases = Bases()
      local base = bases:get("projects")
      assert.is_not_nil(base, "projects base should exist")

      local view = gk._find_kanban_view(base)
      assert.is_not_nil(view, "projects.base should have a kanban view")
      assert.are.equal("kanban", view.type)
      assert.are.equal("Project Board", view.name)
      assert.are.equal("status", view.group_by)
      assert.is_table(view.group_values)
      assert.are.equal(4, #view.group_values)
      assert.are.equal("active", view.group_values[1])
      assert.is_table(view.display_fields)
      assert.are.equal("file.name", view.display_fields[1])
      assert.are.equal("tags", view.display_fields[2])
    end)

    it("returns nil for all-notes.base (no kanban view)", function()
      local Bases = require("vault.bases")
      local bases = Bases()
      local base = bases:get("all-notes")
      assert.is_not_nil(base)
      assert.is_nil(gk._find_kanban_view(base))
    end)
  end)
end)
