-- tests/vault/bases/views/grid_spec.lua
-- Unit and integration tests for the grid-backed vault process buffer.
--
-- Run with: PlenaryBustedFile tests/vault/bases/views/grid_spec.lua {minimal_init='tests/minimal_init.lua'}
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

describe("grid (unit)", function()
  local ge

  before_each(function()
    package.loaded["vault.views.grid"] = nil
    ge = require("vault.views.grid")
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

    it("reuses formatter and parser closures across reloads for same column", function()
      local cols1 = ge._build_grid_columns({ "tags" }, {}, {})
      local cols2 = ge._build_grid_columns({ "tags" }, {}, {})
      assert.is_true(cols1[1].format == cols2[1].format)
      assert.is_true(cols1[1].parse == cols2[1].parse)
    end)

    it("creates distinct formatter and parser closures for different columns", function()
      local cols = ge._build_grid_columns({ "tags", "status" }, {}, {})
      assert.is_true(cols[1].format ~= cols[2].format)
      assert.is_true(cols[1].parse ~= cols[2].parse)
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

describe("grid (integration)", function()
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
    package.loaded["vault.views.grid"] = nil
    ge = require("vault.views.grid")
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

    it("does not reuse buffer when config shape differs", function()
      if not check_config() then return pending("needs vault config") end
      local Notes = require("vault.notes")
      local notes = Notes()

      ge.open({ notes = notes, filter_desc = "grid-dedup-shape", columns = { "title", "status" } })
      local bufnr1 = vim.api.nvim_get_current_buf()

      ge.open({ notes = notes, filter_desc = "grid-dedup-shape", columns = { "title", "tags" } })
      local bufnr2 = vim.api.nvim_get_current_buf()

      assert.are_not.equal(bufnr1, bufnr2)
    end)

    it("passes process.identity_mode to vimtable grid when slug is hidden", function()
      if not check_config() then return pending("needs vault config") end
      local cfg = require("vault.config")
      local Notes = require("vault.notes")
      local notes = Notes()
      local old_mode = cfg.options.process.identity_mode
      local old_mod = package.loaded["vimtable.views.grid"]
      local captured

      package.loaded["vimtable.views.grid"] = {
        Grid = {
          new = function(opts)
            captured = opts.identity
            local bufnr = vim.api.nvim_create_buf(false, true)
            return {
              bufnr = function() return bufnr end,
              attach = function() vim.api.nvim_set_current_buf(bufnr) end,
              state = function() return { snapshot = { data = {} } } end,
              diff = function() return { updates = {}, deletes = {}, creates = {}, custom = {}, errors = {} } end,
              reload = function() end,
              cycle_sort = function() end,
              sort_by_cursor = function() end,
              resize_column = function() end,
              resize_cursor_column = function() end,
              move_column = function() end,
              move_cursor_column = function() end,
              records = function() return {} end,
            }
          end,
        },
      }

      cfg.options.process.identity_mode = "extmark"
      ge.open({ notes = notes, filter_desc = "grid-extmark-mode-prop", columns = { "title", "status" } })

      cfg.options.process.identity_mode = old_mode
      package.loaded["vimtable.views.grid"] = old_mod

      assert.are.equal("extmark", captured)
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

    it("restores a folder move and invalidates note caches", function()
      if not check_config() then return pending("needs vault config") end
      local state = require("vault.core.state")
      local bufnr = vim.api.nvim_create_buf(false, true)
      local src = fixture_root .. "/test_note.md"
      local moved_dir = fixture_root .. "/Moved"
      local moved = moved_dir .. "/test_note.md"
      vim.fn.mkdir(moved_dir, "p")

      local diff = {
        updates = {
          { id = "test_note", fields = { ["file.folder"] = "Moved" } },
        },
        deletes = {},
        creates = {},
        custom = {},
        errors = {},
      }
      local st = {
        note_paths = { test_note = src },
        note_mtimes = { test_note = ge._get_mtime(src) },
      }

      local snap = ge._snapshot_for_undo(diff, st, bufnr, {
        { old_slug = "test_note", new_slug = "Moved/test_note", source_field = "file.folder" },
      })

      local ok_apply, renamed = pcall(ge._apply_structural_ops,
        { { old_slug = "test_note", new_slug = "Moved/test_note", source_field = "file.folder" } },
        { updates = {}, deletes = {}, creates = {}, custom = {}, errors = {} },
        {
          note_paths = { test_note = src },
          note_mtimes = { test_note = ge._get_mtime(src) },
        },
        snap)
      assert.is_true(ok_apply)
      assert.are.equal(1, renamed)
      assert.are.equal(1, vim.fn.filereadable(moved))

      ge._buf_states[bufnr] = {
        grid = { reload = function() end },
        note_paths = { ["Moved/test_note"] = moved },
        note_mtimes = { ["Moved/test_note"] = ge._get_mtime(moved) },
        base = nil,
        filter_desc = "undo-move",
        session_key = "undo-move",
        columns = { "slug", "title" },
        visible_columns = { "title" },
        display_names = {},
        formula_cols = {},
        readonly_columns = {},
        slug_hidden = false,
        saving = false,
      }
      state.set_global_key("cache.notes.paths", { stale = true })

      ge._apply_undo(bufnr, snap)

      assert.are.equal(1, vim.fn.filereadable(src))
      assert.are.equal(0, vim.fn.filereadable(moved))
      assert.is_nil(state.get_global_key("cache.notes.paths"))

      ge._buf_states[bufnr] = nil
      pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
    end)
  end)

  describe("save safety", function()
    it("skips stale deletes", function()
      if not check_config() then return pending("needs vault config") end
      local path = fixture_root .. "/test_note.md"
      local st = {
        note_paths = { test_note = path },
        note_mtimes = { test_note = 1 },
      }

      local _, deletes = ge._apply_mutations({ updates = {}, deletes = { "test_note" }, creates = {} }, st)
      assert.are.equal(0, deletes)
      assert.are.equal(1, vim.fn.filereadable(path))
    end)

    it("uses the configured extension for structural slug renames", function()
      if not check_config() then return pending("needs vault config") end
      local config = require("vault.config")
      local old_ext = config.options.ext
      local tmp_root = vim.fn.tempname()
      vim.fn.mkdir(tmp_root, "p")
      config.options.root = tmp_root
      config.options.ext = ".markdown"

      local path = tmp_root .. "/demo.markdown"
      vim.fn.writefile({ "# demo" }, path)
      local done_err = "PENDING"
      local st = {
        grid = { bufnr = function() return vim.api.nvim_create_buf(false, true) end },
        note_paths = { demo = path },
        note_mtimes = { demo = ge._get_mtime(path) },
        save_mode = nil,
        saving = false,
      }
      local on_save = ge._make_on_save(st)

      on_save({
        updates = {},
        deletes = {},
        creates = {},
        custom = { { type = "rename", extra = { old_slug = "demo", new_slug = "renamed", source_field = "slug" } } },
        errors = {},
      }, function(err)
        done_err = err or false
      end)

      assert.is_false(done_err)
      assert.are.equal(1, vim.fn.filereadable(tmp_root .. "/renamed.markdown"))

      config.options.root = fixture_root
      config.options.ext = old_ext
      vim.fn.delete(tmp_root, "rf")
    end)

    it("applies batched structural renames without dropping earlier link updates", function()
      if not check_config() then return pending("needs vault config") end
      local config = require("vault.config")
      local old_root = config.options.root
      local old_ext = config.options.ext
      local old_prompt = config.options.watcher.prompt_on_rename
      local old_notify = config.options.watcher.notify_on_rename
      local tmp_root = vim.fn.tempname()
      vim.fn.mkdir(tmp_root, "p")
      config.options.root = tmp_root
      config.options.ext = ".md"
      config.options.watcher.prompt_on_rename = false
      config.options.watcher.notify_on_rename = false

      local alpha = tmp_root .. "/alpha.md"
      local beta = tmp_root .. "/beta.md"
      local links = tmp_root .. "/links.md"
      vim.fn.writefile({ "# Alpha" }, alpha)
      vim.fn.writefile({ "# Beta" }, beta)
      vim.fn.writefile({ "[[alpha]] and [[beta]]" }, links)

      local bufnr = vim.api.nvim_create_buf(false, true)
      local st = {
        grid = {
          bufnr = function() return bufnr end,
          reload = function() end,
        },
        note_paths = {
          alpha = alpha,
          beta = beta,
          links = links,
        },
        note_mtimes = {
          alpha = ge._get_mtime(alpha),
          beta = ge._get_mtime(beta),
          links = ge._get_mtime(links),
        },
        columns = { "slug", "title" },
        save_mode = nil,
        saving = false,
      }
      ge._buf_states[bufnr] = st

      local done_err = "PENDING"
      local on_save = ge._make_on_save(st)
      on_save({
        updates = {},
        deletes = {},
        creates = {},
        custom = {
          { type = "rename", extra = { old_slug = "alpha", new_slug = "alpha-new", source_field = "slug" } },
          { type = "rename", extra = { old_slug = "beta", new_slug = "beta-new", source_field = "slug" } },
        },
        errors = {},
      }, function(err)
        done_err = err or false
      end)

      assert.is_false(done_err)
      assert.are.equal(1, vim.fn.filereadable(tmp_root .. "/alpha-new.md"))
      assert.are.equal(1, vim.fn.filereadable(tmp_root .. "/beta-new.md"))

      local link_lines = vim.fn.readfile(links)
      assert.are.same({ "[[alpha-new]] and [[beta-new]]" }, link_lines)

      ge._buf_states[bufnr] = nil
      pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
      config.options.root = old_root
      config.options.ext = old_ext
      config.options.watcher.prompt_on_rename = old_prompt
      config.options.watcher.notify_on_rename = old_notify
      vim.fn.delete(tmp_root, "rf")
    end)

    it("drops mixed create-delete structural guesses instead of pairing them", function()
      if not check_config() then return pending("needs vault config") end
      local calls = 0
      local path = fixture_root .. "/test_note.md"
      local st = {
        grid = { bufnr = function() return vim.api.nvim_create_buf(false, true) end },
        note_paths = { test_note = path },
        note_mtimes = { test_note = ge._get_mtime(path) },
        save_mode = nil,
        saving = false,
      }
      local original_apply = ge._apply_mutations
      ge._apply_mutations = function(diff)
        calls = calls + 1
        assert.are.equal(0, #diff.creates)
        assert.are.equal(0, #diff.deletes)
        return 0, 0, 0
      end

      local on_save = ge._make_on_save(st)
      on_save({
        updates = {},
        deletes = { "test_note" },
        creates = { { fields = { slug = "new-note", title = "New note" } } },
        custom = {},
        errors = {},
      }, function() end)

      ge._apply_mutations = original_apply
      assert.are.equal(1, calls)
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

  describe("refresh_current", function()
    it("rebuilds from current files without calling reload_notes", function()
      if not check_config() then return pending("needs vault config") end

      local path = fixture_root .. "/test_note.md"
      local bufnr = vim.api.nvim_create_buf(false, true)
      local seen_records = nil
      local reload_calls = 0

      ge._buf_states[bufnr] = {
        grid = {
          reload = function(_, records)
            seen_records = records
          end,
        },
        note_paths = { ["test_note"] = path },
        note_mtimes = {},
        base = nil,
        filter_desc = "grid-refresh-current",
        columns = { "slug", "title", "status" },
        visible_columns = { "title", "status" },
        display_names = {},
        formula_cols = {},
        readonly_columns = {},
        slug_hidden = false,
        saving = false,
        reload_notes = function()
          reload_calls = reload_calls + 1
          return { map = {} }
        end,
        retain_note = function()
          return false
        end,
      }

      ge.refresh_current(bufnr)

      assert.are.equal(0, reload_calls)
      assert.is_table(seen_records)
      assert.are.equal(0, #seen_records)

      ge._buf_states[bufnr] = nil
      pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
    end)

    it("reapplies base filters to the current note set", function()
      if not check_config() then return pending("needs vault config") end

      local Base = require("vault.bases.base")
      local path = fixture_root .. "/test_note.md"
      local bufnr = vim.api.nvim_create_buf(false, true)
      local seen_records = nil
      local base = Base({
        name = "active-only",
        path = "/tmp/active-only.base",
        filters = { ["and"] = { 'status == "active"' } },
      })

      ge._buf_states[bufnr] = {
        grid = {
          reload = function(_, records)
            seen_records = records
          end,
        },
        note_paths = { ["test_note"] = path },
        note_mtimes = {},
        base = base,
        filter_desc = "grid-refresh-base-filter",
        columns = { "slug", "title", "status" },
        visible_columns = { "title", "status" },
        display_names = {},
        formula_cols = {},
        readonly_columns = {},
        slug_hidden = false,
        saving = false,
      }

      ge._set_frontmatter_field(path, "status", "archived")
      ge.refresh_current(bufnr)

      assert.is_table(seen_records)
      assert.are.equal(0, #seen_records)

      ge._buf_states[bufnr] = nil
      pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
    end)

    it("uses reload_notes only for explicit full reload", function()
      if not check_config() then return pending("needs vault config") end

      local Note = require("vault.notes.note")
      local path = fixture_root .. "/test_note.md"
      local note = Note(path)
      local bufnr = vim.api.nvim_create_buf(false, true)
      local seen_records = nil
      local reload_calls = 0

      ge._buf_states[bufnr] = {
        grid = {
          reload = function(_, records)
            seen_records = records
          end,
        },
        note_paths = {},
        note_mtimes = {},
        base = nil,
        filter_desc = "grid-full-reload",
        columns = { "slug", "title", "status" },
        visible_columns = { "title", "status" },
        display_names = {},
        formula_cols = {},
        readonly_columns = {},
        slug_hidden = false,
        saving = false,
        reload_notes = function()
          reload_calls = reload_calls + 1
          return { map = { [note.data.slug] = note } }
        end,
      }

      ge.reload(bufnr)

      assert.are.equal(1, reload_calls)
      assert.is_table(seen_records)
      assert.are.equal(1, #seen_records)
      assert.are.equal(note.data.slug, seen_records[1].slug)

      ge._buf_states[bufnr] = nil
      pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
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
