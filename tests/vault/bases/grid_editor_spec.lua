-- tests/vault/bases/grid_editor_spec.lua
-- Unit and integration tests for the grid-backed vault process buffer.
--
-- Run with: PlenaryBustedFile tests/vault/bases/grid_editor_spec.lua {minimal_init='tests/minimal_init.lua'}
--
-- Tests are grouped into:
-- 1. Pure-function unit tests (no buffer creation needed)
-- 2. Integration tests (open buffer, edit, save, undo)

local fixture_root = vim.fn.getcwd() .. "/tests/fixtures/demo-vault"

--- Helper: check if vault config is available. Returns true if config.options.root is set.
local function has_vault_config()
  local ok, config = pcall(require, "vault.config")
  return ok and config.options and config.options.root and config.options.root ~= ""
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- 1. Pure-function unit tests
-- ═══════════════════════════════════════════════════════════════════════════════

describe("grid_editor (unit)", function()
  local ge

  before_each(function()
    package.loaded["vault.bases.grid_editor"] = nil
    ge = require("vault.bases.grid_editor")
  end)

  -- ── normalize_col ────────────────────────────────────────────────────────

  describe("normalize_col", function()
    it("maps note.* to file.*", function()
      assert.are.equal("file.name", ge._normalize_col("note.name"))
      assert.are.equal("file.path", ge._normalize_col("note.path"))
    end)

    it("maps legacy aliases", function()
      assert.are.equal("file.folder", ge._normalize_col("dir"))
      assert.are.equal("file.body", ge._normalize_col("body"))
      assert.are.equal("file.name", ge._normalize_col("name"))
    end)

    it("passes through standard columns unchanged", function()
      assert.are.equal("slug", ge._normalize_col("slug"))
      assert.are.equal("title", ge._normalize_col("title"))
      assert.are.equal("tags", ge._normalize_col("tags"))
      assert.are.equal("status", ge._normalize_col("status"))
    end)
  end)

  -- ── base_key_to_col ──────────────────────────────────────────────────────

  describe("base_key_to_col", function()
    it("marks formula columns as readonly", function()
      local col, is_formula = ge._base_key_to_col("formula.greeting")
      assert.are.equal("formula.greeting", col)
      assert.is_true(is_formula)
    end)

    it("marks readonly file columns", function()
      local col, is_ro = ge._base_key_to_col("file.path")
      assert.are.equal("file.path", col)
      assert.is_true(is_ro)
    end)

    it("marks editable columns as not readonly", function()
      local col, is_ro = ge._base_key_to_col("status")
      assert.are.equal("status", col)
      assert.is_false(is_ro)
    end)

    it("normalizes note.* to file.*", function()
      local col, _ = ge._base_key_to_col("note.name")
      assert.are.equal("file.name", col)
    end)
  end)

  -- ── yaml_quote ───────────────────────────────────────────────────────────

  describe("yaml_quote", function()
    it("quotes boolean-like values", function()
      assert.are.equal('"true"', ge._yaml_quote("true"))
      assert.are.equal('"false"', ge._yaml_quote("false"))
      assert.are.equal('"yes"', ge._yaml_quote("yes"))
      assert.are.equal('"no"', ge._yaml_quote("no"))
      assert.are.equal('"null"', ge._yaml_quote("null"))
    end)

    it("quotes numeric-looking values", function()
      assert.are.equal('"123"', ge._yaml_quote("123"))
      assert.are.equal('"3.14"', ge._yaml_quote("3.14"))
      assert.are.equal('"2024-01-01"', ge._yaml_quote("2024-01-01"))
    end)

    it("quotes values with YAML special chars", function()
      assert.are.equal('"key: value"', ge._yaml_quote("key: value"))
      assert.are.equal('"has #tag"', ge._yaml_quote("has #tag"))
    end)

    it("passes through safe strings unquoted", function()
      assert.are.equal("hello", ge._yaml_quote("hello"))
      assert.are.equal("simple-text", ge._yaml_quote("simple-text"))
    end)

    it("escapes strings with YAML indicators", function()
      -- Strings starting with ? & * ! are YAML indicators and must be quoted
      local q1 = ge._yaml_quote("?question")
      assert.truthy(q1:match('^"'), "should quote YAML indicator ?")

      local q2 = ge._yaml_quote("*anchor")
      assert.truthy(q2:match('^"'), "should quote YAML indicator *")

      -- Leading whitespace
      local q3 = ge._yaml_quote(" leading")
      assert.truthy(q3:match('^"'), "should quote leading whitespace")
    end)

    it("quotes empty string", function()
      assert.are.equal('""', ge._yaml_quote(""))
    end)
  end)

  -- ── validate_path_in_vault ───────────────────────────────────────────────
  -- Requires vault.config.options.root to be set (via minimal_init.lua)

  describe("validate_path_in_vault", function()
    it("accepts paths inside vault root", function()
      if not has_vault_config() then return pending("vault config not loaded") end
      local resolved, err = ge._validate_path_in_vault(fixture_root .. "/test_note.md")
      assert.truthy(resolved, "expected resolved path, got error: " .. tostring(err))
      assert.is_nil(err)
    end)

    it("rejects paths outside vault root", function()
      if not has_vault_config() then return pending("vault config not loaded") end
      local resolved, err = ge._validate_path_in_vault("/tmp/evil.md")
      assert.is_nil(resolved)
      assert.truthy(err)
      assert.truthy(err:match("escapes vault root"))
    end)

    it("rejects paths that are substrings of root but not actual children", function()
      if not has_vault_config() then return pending("vault config not loaded") end
      local config = require("vault.config")
      local root = vim.fn.resolve(vim.fn.expand(config.options.root))
      local evil_path = root .. "-evil/test.md"
      local resolved, err = ge._validate_path_in_vault(evil_path)
      assert.is_nil(resolved)
      assert.truthy(err)
    end)
  end)

  -- ── fmt_value ────────────────────────────────────────────────────────────

  describe("fmt_value", function()
    it("formats nil as empty cell", function()
      local empty = ge._fmt_value(nil)
      assert.are.equal("_", empty)
    end)

    it("formats booleans", function()
      assert.are.equal("true", ge._fmt_value(true))
      assert.are.equal("false", ge._fmt_value(false))
    end)

    it("formats tag lists with # prefix", function()
      local result = ge._fmt_value({ "foo", "bar" }, "tags")
      assert.are.equal("#foo #bar", result)
    end)

    it("formats tag list already prefixed", function()
      local result = ge._fmt_value({ "#foo", "bar" }, "tags")
      assert.are.equal("#foo #bar", result)
    end)

    it("formats generic lists with commas", function()
      local result = ge._fmt_value({ "a", "b", "c" }, "links")
      assert.are.equal("a, b, c", result)
    end)

    it("formats empty table as empty cell", function()
      assert.are.equal("_", ge._fmt_value({}))
    end)

    it("formats date wrapper", function()
      local result = ge._fmt_value({ _type = "date", epoch = 1704067200 })
      assert.truthy(result:match("^%d%d%d%d%-%d%d%-%d%d$"))
    end)
  end)

  -- ── parse_value ──────────────────────────────────────────────────────────

  describe("parse_value", function()
    it("parses empty cell as nil", function()
      assert.is_nil(ge._parse_value("_", "status"))
      assert.is_nil(ge._parse_value("", "status"))
    end)

    it("parses tag text into list", function()
      local result = ge._parse_value("#foo #bar", "tags")
      assert.are.same({ "foo", "bar" }, result)
    end)

    it("returns nil for tags with no hash prefixes", function()
      assert.is_nil(ge._parse_value("nohash", "tags"))
    end)

    it("returns text for normal columns", function()
      assert.are.equal("active", ge._parse_value("active", "status"))
    end)
  end)

  -- ── columns_from_base ────────────────────────────────────────────────────

  describe("columns_from_base", function()
    it("derives columns from base view order", function()
      local Base = require("vault.bases.base")
      local base = Base({
        name = "test",
        path = "/tmp/test.base",
        properties = {
          ["file.name"] = { displayName = "Name" },
          status = { displayName = "Status" },
          ["formula.x"] = { displayName = "Formula X" },
        },
        views = {
          { type = "table", name = "T", order = { "file.name", "status", "formula.x" } },
        },
      })

      local columns, display_names, formula_cols, visible_columns = ge._columns_from_base(base)

      -- slug should be prepended internally
      assert.are.equal("slug", columns[1])
      assert.truthy(vim.tbl_contains(columns, "file.name"))
      assert.truthy(vim.tbl_contains(columns, "status"))
      assert.truthy(vim.tbl_contains(columns, "formula.x"))

      -- visible_columns should NOT include slug (it wasn't in order)
      assert.falsy(vim.tbl_contains(visible_columns, "slug"))

      -- display names
      assert.are.equal("Name", display_names["file.name"])
      assert.are.equal("Status", display_names["status"])

      -- formula detection
      assert.are.equal(1, #formula_cols)
      assert.are.equal("formula.x", formula_cols[1])
    end)

    it("returns defaults when base has no properties", function()
      local Base = require("vault.bases.base")
      local base = Base({
        name = "empty",
        path = "/tmp/empty.base",
        properties = {},
        views = {},
      })

      local columns = ge._columns_from_base(base)
      assert.are.same({ "slug", "title", "status", "tags" }, columns)
    end)
  end)

  -- ── sort_from_base ───────────────────────────────────────────────────────

  describe("sort_from_base", function()
    it("extracts sort from base view", function()
      local Base = require("vault.bases.base")
      local base = Base({
        name = "sorted",
        path = "/tmp/sorted.base",
        properties = { status = {} },
        views = {
          { type = "table", name = "S", order = { "status" },
            sort_by = { key = "status", direction = "desc" } },
        },
      })

      local sort = ge._sort_from_base(base)
      assert.truthy(sort)
      assert.are.equal("status", sort.col)
      assert.are.equal("desc", sort.dir)
    end)

    it("returns nil when no sort defined", function()
      local Base = require("vault.bases.base")
      local base = Base({
        name = "nosort",
        path = "/tmp/nosort.base",
        properties = { status = {} },
        views = { { type = "table", name = "NS", order = { "status" } } },
      })

      assert.is_nil(ge._sort_from_base(base))
    end)
  end)

  -- ── make_classify ────────────────────────────────────────────────────────

  describe("make_classify", function()
    it("classifies slug edit as rename", function()
      local st = { note_paths = { ["old-note"] = "/tmp/old-note.md" } }
      local classify = ge._make_classify(st)
      local ctype, extra = classify("old-note", "slug", "old-note", "new-note")
      assert.are.equal("rename", ctype)
      assert.are.equal("old-note", extra.old_slug)
      assert.are.equal("new-note", extra.new_slug)
    end)

    it("classifies file.slug edit as rename", function()
      local st = { note_paths = {} }
      local classify = ge._make_classify(st)
      local ctype, extra = classify("my-note", "file.slug", "my-note", "renamed-note")
      assert.are.equal("rename", ctype)
      assert.are.equal("my-note", extra.old_slug)
      assert.are.equal("renamed-note", extra.new_slug)
    end)

    it("classifies file.name edit as rename with dir preserved", function()
      local st = { note_paths = {} }
      local classify = ge._make_classify(st)
      local ctype, extra = classify("Notes/old-stem", "file.name", "old-stem", "new-stem")
      assert.are.equal("rename", ctype)
      assert.are.equal("Notes/old-stem", extra.old_slug)
      assert.are.equal("Notes/new-stem", extra.new_slug)
    end)

    it("returns skip for same-slug edit", function()
      local st = { note_paths = {} }
      local classify = ge._make_classify(st)
      local ctype = classify("my-note", "slug", "my-note", "my-note")
      assert.are.equal("skip", ctype)
    end)

    it("classifies file.folder edit as update", function()
      local st = { note_paths = {} }
      local classify = ge._make_classify(st)
      local ctype = classify("note", "file.folder", "old/", "new/")
      assert.are.equal("update", ctype)
    end)

    it("classifies generic field as update", function()
      local st = { note_paths = {} }
      local classify = ge._make_classify(st)
      local ctype = classify("note", "status", "draft", "active")
      assert.are.equal("update", ctype)
    end)
  end)

  -- ── build_grid_columns ───────────────────────────────────────────────────

  describe("build_grid_columns", function()
    it("marks formula columns as readonly", function()
      local cols = ge._build_grid_columns(
        { "title", "status", "formula.x" },
        { title = "Title", status = "Status", ["formula.x"] = "FX" },
        { "formula.x" }
      )
      assert.are.equal(3, #cols)
      assert.are.equal("title", cols[1].name)
      assert.is_falsy(cols[1].readonly)
      assert.are.equal("formula.x", cols[3].name)
      assert.is_true(cols[3].readonly)
    end)

    it("marks readonly file columns", function()
      local cols = ge._build_grid_columns(
        { "title", "file.mtime" },
        {},
        {}
      )
      assert.are.equal("file.mtime", cols[2].name)
      assert.is_true(cols[2].readonly)
    end)

    it("attaches format and parse functions", function()
      local cols = ge._build_grid_columns({ "tags" }, {}, {})
      assert.is_function(cols[1].format)
      assert.is_function(cols[1].parse)
      -- Test roundtrip
      assert.are.equal("#foo #bar", cols[1].format({ "foo", "bar" }))
      assert.are.same({ "foo", "bar" }, cols[1].parse("#foo #bar"))
    end)
  end)

  -- ── frontmatter I/O ─────────────────────────────────────────────────────

  describe("read_frontmatter_fields", function()
    it("reads scalar fields", function()
      local path = fixture_root .. "/test_note.md"
      if vim.fn.filereadable(path) == 0 then pending("fixture missing") end
      local fields = ge._read_frontmatter_fields(path, { "title", "status", "tags" })
      -- test_note.md should have frontmatter
      assert.is_table(fields)
    end)

    it("returns empty for file without frontmatter", function()
      local path = fixture_root .. "/README.md"
      if vim.fn.filereadable(path) == 0 then pending("fixture missing") end
      local fields = ge._read_frontmatter_fields(path, { "title" })
      -- README.md might not have frontmatter
      assert.is_table(fields)
    end)
  end)

  -- ── atomic_writefile ─────────────────────────────────────────────────────

  describe("atomic_writefile", function()
    local tmp_path

    before_each(function()
      tmp_path = os.tmpname()
    end)

    after_each(function()
      pcall(os.remove, tmp_path)
      pcall(os.remove, tmp_path .. ".vault_tmp")
    end)

    it("writes file atomically", function()
      local ok, err = ge._atomic_writefile(tmp_path, { "line1", "line2" })
      assert.is_true(ok)
      assert.is_nil(err)
      local lines = vim.fn.readfile(tmp_path)
      assert.are.same({ "line1", "line2" }, lines)
    end)

    it("overwrites existing file", function()
      vim.fn.writefile({ "old" }, tmp_path)
      ge._atomic_writefile(tmp_path, { "new" })
      local lines = vim.fn.readfile(tmp_path)
      assert.are.same({ "new" }, lines)
    end)
  end)
end)

-- ═══════════════════════════════════════════════════════════════════════════════
-- 2. Integration tests (require buffer creation, vimtable loaded)
-- ═══════════════════════════════════════════════════════════════════════════════

describe("grid_editor (integration)", function()
  local ge
  local config_loaded = false

  before_each(function()
    -- Ensure vimtable is on rtp
    local vt_path = vim.fn.expand("~/projects/vimtable.nvim")
    if not vim.tbl_contains(vim.opt.rtp:get(), vt_path) then
      vim.opt.rtp:prepend(vt_path)
    end
    -- Check if vault config is loaded (requires minimal_init.lua)
    local ok, config = pcall(require, "vault.config")
    config_loaded = ok and config.options and config.options.root and config.options.root ~= ""
    package.loaded["vault.bases.grid_editor"] = nil
    ge = require("vault.bases.grid_editor")
  end)

  after_each(function()
    -- Clean up all vault:// and grid buffers
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      local name = vim.api.nvim_buf_get_name(buf)
      if name:match("vault://") then
        pcall(vim.api.nvim_buf_delete, buf, { force = true })
      end
    end
    -- Restore fixture files
    vim.fn.system({ "git", "checkout", "--", "tests/fixtures/demo-vault/" })
  end)

  --- Helper: skip test if vault config is not loaded. Must be used as: if not ... then return end
  local function check_config()
    return config_loaded
  end

  -- ── Open ─────────────────────────────────────────────────────────────────

  describe("open", function()
    it("should open a grid process buffer with fixture notes", function()
      if not check_config() then return pending("needs vault config") end
      local Notes = require("vault.notes")
      local notes = Notes()
      local note_count = vim.tbl_count(notes.map)
      assert(note_count >= 5, "expected at least 5 fixture notes, got " .. note_count)

      ge.open({ notes = notes, filter_desc = "grid-test-open" })

      local bufnr = vim.api.nvim_get_current_buf()
      local name = vim.api.nvim_buf_get_name(bufnr)
      assert.truthy(name:match("vault://grid%-process/grid%-test%-open"))

      local st = ge._buf_states[bufnr]
      assert.truthy(st, "buf_states should have entry")
      assert.truthy(st.grid, "state should have grid instance")
      assert.truthy(st.note_paths, "state should have note_paths")
      assert.truthy(vim.tbl_count(st.note_paths) >= 5, "should have paths for all notes")
    end)

    it("should prevent duplicate buffers for same filter_desc", function()
      if not check_config() then return pending("needs vault config") end
      local Notes = require("vault.notes")
      local notes = Notes()

      ge.open({ notes = notes, filter_desc = "grid-dedup-test" })
      local bufnr1 = vim.api.nvim_get_current_buf()

      ge.open({ notes = notes, filter_desc = "grid-dedup-test" })
      local bufnr2 = vim.api.nvim_get_current_buf()

      assert.are.equal(bufnr1, bufnr2, "should reuse existing buffer")
    end)
  end)

  -- ── Base-driven open ─────────────────────────────────────────────────────

  describe("base-driven open", function()
    it("derives columns and display names from base", function()
      if not check_config() then return pending("needs vault config") end
      local Base = require("vault.bases.base")
      local base = Base({
        name = "grid-cols-test",
        path = "/tmp/test.base",
        properties = {
          ["file.name"] = { displayName = "Name" },
          status = { displayName = "Status" },
          ["formula.greeting"] = { displayName = "Greeting" },
        },
        formulas = { greeting = '"Hello"' },
        views = {
          { type = "table", name = "Test",
            order = { "file.name", "status", "formula.greeting" } },
        },
      })

      local Notes = require("vault.notes")
      local notes = Notes()

      ge.open({ notes = notes, base = base, filter_desc = "grid-base-cols" })

      local bufnr = vim.api.nvim_get_current_buf()
      local st = ge._buf_states[bufnr]
      assert.truthy(st.base, "state should reference the base")

      -- Visible columns should include file.name, status, formula.greeting
      assert.truthy(vim.tbl_contains(st.visible_columns, "file.name"))
      assert.truthy(vim.tbl_contains(st.visible_columns, "status"))

      -- Slug should be in columns (internal) but hidden
      assert.truthy(vim.tbl_contains(st.columns, "slug"))
      assert.is_true(st.slug_hidden)
    end)
  end)

  -- ── Sort ─────────────────────────────────────────────────────────────────

  describe("sorting", function()
    it("delegates sort_by_cursor to grid", function()
      if not check_config() then return pending("needs vault config") end
      local Notes = require("vault.notes")
      local notes = Notes()

      ge.open({ notes = notes, filter_desc = "grid-sort-test" })
      local bufnr = vim.api.nvim_get_current_buf()

      -- Should not error
      ge.sort_by_cursor(bufnr)
      assert.truthy(vim.api.nvim_buf_is_valid(bufnr))
    end)
  end)

  -- ── Column resize/move ───────────────────────────────────────────────────

  describe("column resize", function()
    it("should not crash on resize", function()
      if not check_config() then return pending("needs vault config") end
      local Notes = require("vault.notes")
      local notes = Notes()

      ge.open({ notes = notes, filter_desc = "grid-resize-test" })
      local bufnr = vim.api.nvim_get_current_buf()

      -- Resize any visible column — should not error
      local st = ge._buf_states[bufnr]
      if not st then pending("grid buffer did not open (no notes?)") end
      local col = st.visible_columns[1]
      ge.resize_column(bufnr, col, 5)
      assert.truthy(vim.api.nvim_buf_is_valid(bufnr))
    end)
  end)

  describe("column reorder", function()
    it("should not crash on move", function()
      if not check_config() then return pending("needs vault config") end
      local Notes = require("vault.notes")
      local notes = Notes()

      ge.open({ notes = notes, filter_desc = "grid-move-test" })
      local bufnr = vim.api.nvim_get_current_buf()
      local st = ge._buf_states[bufnr]
      if not st then pending("grid buffer did not open (no notes?)") end

      if #st.visible_columns >= 2 then
        ge.move_column(bufnr, st.visible_columns[1], 1)
        assert.truthy(vim.api.nvim_buf_is_valid(bufnr))
      end
    end)
  end)

  -- ── Frontmatter write roundtrip ──────────────────────────────────────────

  describe("set_frontmatter_field", function()
    it("writes a new field to an existing note", function()
      if not check_config() then return pending("needs vault config") end
      -- Find a fixture note with frontmatter
      local path = fixture_root .. "/test_note.md"
      if vim.fn.filereadable(path) == 0 then pending("fixture missing") end

      ge._set_frontmatter_field(path, "grid_test_key", "grid_test_value")

      local lines = vim.fn.readfile(path)
      local found = false
      for _, l in ipairs(lines) do
        if l:match("^grid_test_key:%s*grid_test_value") then found = true; break end
      end
      assert.truthy(found, "field should be written to frontmatter")
    end)
  end)

  describe("set_frontmatter_fields (batch)", function()
    it("writes multiple fields atomically", function()
      if not check_config() then return pending("needs vault config") end
      local path = fixture_root .. "/test_note.md"
      if vim.fn.filereadable(path) == 0 then pending("fixture missing") end

      ge._set_frontmatter_fields(path, {
        batch_a = "value_a",
        batch_b = "value_b",
      })

      local lines = vim.fn.readfile(path)
      local found_a, found_b = false, false
      for _, l in ipairs(lines) do
        if l:match("^batch_a:%s*value_a") then found_a = true end
        if l:match("^batch_b:%s*value_b") then found_b = true end
      end
      assert.truthy(found_a, "batch_a should be in frontmatter")
      assert.truthy(found_b, "batch_b should be in frontmatter")
    end)
  end)

  -- ── Undo ─────────────────────────────────────────────────────────────────

  describe("undo", function()
    it("should report no snapshot when none exists", function()
      if not check_config() then return pending("needs vault config") end
      local Notes = require("vault.notes")
      local notes = Notes()

      ge.open({ notes = notes, filter_desc = "grid-undo-empty" })
      local bufnr = vim.api.nvim_get_current_buf()

      -- Should not error, just log a warning
      ge.undo(bufnr)
      local vt_undo = require("vimtable.undo")
      assert.is_false(vt_undo.has(bufnr))
    end)
  end)

  -- ── Reload ───────────────────────────────────────────────────────────────

  describe("reload", function()
    it("should refresh grid without crash", function()
      if not check_config() then return pending("needs vault config") end
      local Notes = require("vault.notes")
      local notes = Notes()

      ge.open({ notes = notes, filter_desc = "grid-reload-test" })
      local bufnr = vim.api.nvim_get_current_buf()

      ge.reload(bufnr)
      assert.truthy(vim.api.nvim_buf_is_valid(bufnr))
      assert.truthy(ge._buf_states[bufnr])
    end)
  end)

  -- ── Save with no changes ─────────────────────────────────────────────────

  describe("no-op save", function()
    it("should detect no changes on write", function()
      if not check_config() then return pending("needs vault config") end
      local Notes = require("vault.notes")
      local notes = Notes()

      ge.open({ notes = notes, filter_desc = "grid-noop-save" })
      local bufnr = vim.api.nvim_get_current_buf()

      -- Write without changes — should succeed without error
      vim.cmd("w")
      assert.truthy(vim.api.nvim_buf_is_valid(bufnr))
      -- No undo snapshot should be created for no-op save
      local vt_undo = require("vimtable.undo")
      assert.is_false(vt_undo.has(bufnr))
    end)
  end)
end)
