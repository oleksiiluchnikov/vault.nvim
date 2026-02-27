-- tests/vault/bases/editor_spec.lua
-- Tests for bases editor extmark drift reconciliation.

local fixture_root = vim.fn.getcwd() .. "/tests/fixtures/demo-vault"

describe("bases.editor", function()
  local editor

  before_each(function()
    package.loaded["vault.bases.editor"] = nil
    editor = require("vault.bases.editor")
  end)

  after_each(function()
    -- Clean up all vault:// buffers
    for _, buf in ipairs(vim.api.nvim_list_bufs()) do
      local name = vim.api.nvim_buf_get_name(buf)
      if name:match("vault://") then
        pcall(vim.api.nvim_buf_delete, buf, { force = true })
      end
    end
  end)

  describe("open + save (no changes)", function()
    it("should open a process buffer with fixture notes", function()
      local Notes = require("vault.notes")
      local notes = Notes()
      assert(vim.tbl_count(notes.map) >= 5, "expected at least 5 fixture notes")

      editor.open({ notes = notes, filter_desc = "test-open" })

      local bufnr = vim.api.nvim_get_current_buf()
      local name = vim.api.nvim_buf_get_name(bufnr)
      assert.truthy(name:match("vault://process/test%-open"))

      local line_count = vim.api.nvim_buf_line_count(bufnr)
      assert.are.equal(vim.tbl_count(notes.map), line_count)

      -- All lines should have extmark identity
      local st = editor._buf_states[bufnr]
      assert.truthy(st, "buf_states should have entry")
      local NS = vim.api.nvim_create_namespace("vault_bases_editor")
      for row = 0, line_count - 1 do
        local marks = vim.api.nvim_buf_get_extmarks(bufnr, NS, { row, 0 }, { row, -1 }, {})
        local found = false
        for _, mk in ipairs(marks) do
          if st.mark_to_slug[mk[1]] then found = true end
        end
        assert.truthy(found, "row " .. row .. " should have a slug extmark")
      end
    end)
  end)

  describe("extmark drift reconciliation", function()
    it("should reconcile drifted extmarks via title matching on save", function()
      local Notes = require("vault.notes")
      local notes = Notes()

      editor.open({ notes = notes, filter_desc = "test-drift" })
      local bufnr = vim.api.nvim_get_current_buf()
      local st = editor._buf_states[bufnr]
      local NS = vim.api.nvim_create_namespace("vault_bases_editor")
      local line_count = vim.api.nvim_buf_line_count(bufnr)

      -- Record original slug-per-row
      local original_slugs = {}
      for row = 0, line_count - 1 do
        local marks = vim.api.nvim_buf_get_extmarks(bufnr, NS, { row, 0 }, { row, -1 }, {})
        for _, mk in ipairs(marks) do
          if st.mark_to_slug[mk[1]] then
            original_slugs[row] = st.mark_to_slug[mk[1]]
          end
        end
      end

      -- Simulate batch edit: replace status column on every line using set_lines
      -- Column order: slug(1), title(2), status(3), tags(4)
      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      for i = 1, #lines do
        local parts = vim.split(lines[i], " │ ", { plain = true })
        if parts[3] then parts[3] = "done         " end
        local new_line = table.concat(parts, " │ ")
        vim.api.nvim_buf_set_lines(bufnr, i - 1, i, false, { new_line })
      end

      -- Write the buffer (triggers on_save → diff_buffer with reconciliation)
      -- We need to capture what happens. Let's call diff_buffer-like logic directly.
      -- Actually, just :w and check the files
      vim.cmd("w")

      -- After save, the buffer reloads. Check that each note got status=done
      -- and that the CORRECT file was updated (not a wrong one due to drift)
      for row = 0, line_count - 1 do
        local slug = original_slugs[row]
        if slug then
          local path = st.note_paths[slug]
          if path and vim.fn.filereadable(path) == 1 then
            local file_lines = vim.fn.readfile(path, "", 30)
            local found_done = false
            for _, l in ipairs(file_lines) do
              if l:match("^status:%s*done") then
                found_done = true
                break
              end
            end
            assert.truthy(found_done,
              string.format("Note '%s' at %s should have status: done", slug, path))
          end
        end
      end
    end)

    -- Cleanup: restore fixture files
    after_each(function()
      -- Reset status field in all fixture notes
      vim.fn.system({ "git", "checkout", "--", "tests/fixtures/demo-vault/" })
    end)
  end)

  describe("batch edit does not corrupt titles", function()
    it("should not write status to wrong note when extmarks drift", function()
      local Notes = require("vault.notes")
      local notes = Notes()

      editor.open({ notes = notes, filter_desc = "test-no-corrupt" })
      local bufnr = vim.api.nvim_get_current_buf()
      local st = editor._buf_states[bufnr]
      local line_count = vim.api.nvim_buf_line_count(bufnr)

      -- Record the title for each slug from the file (ground truth)
      local slug_titles = {}
      for slug, snap in pairs(st.snapshot) do
        slug_titles[slug] = snap.title
      end

      -- Edit status on all lines
      -- Column order: slug(1), title(2), status(3), tags(4)
      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      for i = 1, #lines do
        local parts = vim.split(lines[i], " │ ", { plain = true })
        if parts[3] then parts[3] = "batch-test   " end
        vim.api.nvim_buf_set_lines(bufnr, i - 1, i, false, { table.concat(parts, " │ ") })
      end

      vim.cmd("w")

      -- After save: verify each file's title in frontmatter was NOT changed
      for slug, expected_title in pairs(slug_titles) do
        local path = st.note_paths[slug]
        if path and vim.fn.filereadable(path) == 1 then
          local file_lines = vim.fn.readfile(path, "", 30)
          for _, l in ipairs(file_lines) do
            if l:match("^title:") then
              local file_title = l:match("^title:%s*(.+)")
              if file_title then
                file_title = file_title:gsub('^"(.*)"$', '%1'):gsub("^'(.*)'$", '%1')
                -- The title should match the original — not some other note's title
                assert.are.equal(expected_title, file_title,
                  string.format("Title corruption detected in %s: expected '%s' got '%s'",
                    slug, expected_title, file_title))
              end
              break
            end
          end
        end
      end
    end)

    after_each(function()
      vim.fn.system({ "git", "checkout", "--", "tests/fixtures/demo-vault/" })
    end)
  end)

  describe("base-driven editor", function()
    after_each(function()
      for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        local n = vim.api.nvim_buf_get_name(buf)
        if n:match("vault://") then
          pcall(vim.api.nvim_buf_delete, buf, { force = true })
        end
      end
      vim.fn.system({ "git", "checkout", "--", "tests/fixtures/demo-vault/" })
    end)

    it("should derive columns and display names from base properties", function()
      local Base = require("vault.bases.base")
      -- Create a synthetic base with known columns but no filters
      local base = Base({
        name = "test-columns",
        path = "/tmp/test.base",
        formulas = {
          greeting = '"Hello " + file.name',
        },
        properties = {
          ["file.name"] = { displayName = "Name" },
          status = { displayName = "Status" },
          ["formula.greeting"] = { displayName = "Greeting" },
        },
        views = {
          { type = "table", name = "Test", order = { "file.name", "status", "formula.greeting" } },
        },
      })

      local Notes = require("vault.notes")
      local notes = Notes()

      editor.open({ notes = notes, base = base, filter_desc = "base-cols-test" })

      local bufnr = vim.api.nvim_get_current_buf()
      local st = editor._buf_states[bufnr]
      assert.truthy(st, "state should exist")
      assert.truthy(st.base, "state should reference the base")

      -- Columns from synthetic base view: file.name, status, formula.greeting
      assert.truthy(vim.tbl_contains(st.columns, "title"), "should have title column (from file.name)")
      assert.truthy(vim.tbl_contains(st.columns, "status"), "should have status column")

      -- Display names
      assert.are.equal("Name", st.display_names["title"])
      assert.are.equal("Status", st.display_names["status"])

      -- Formula columns
      assert.are.equal(1, #st.formula_cols, "should have 1 formula column")
      assert.truthy(vim.tbl_contains(st.formula_cols, "formula.greeting"))
      assert.are.equal("Greeting", st.display_names["formula.greeting"])
    end)

    it("should evaluate formula columns in the buffer", function()
      local Base = require("vault.bases.base")
      local base = Base({
        name = "test-formulas",
        path = "/tmp/test.base",
        formulas = {
          name_upper = "file.name.upper()",
        },
        properties = {
          ["file.name"] = { displayName = "Name" },
          ["formula.name_upper"] = { displayName = "UPPER" },
        },
        views = {
          { type = "table", name = "Test", order = { "file.name", "formula.name_upper" } },
        },
      })

      local Notes = require("vault.notes")
      local notes = Notes()

      editor.open({ notes = notes, base = base, filter_desc = "formula-eval-test" })

      local bufnr = vim.api.nvim_get_current_buf()
      local st = editor._buf_states[bufnr]
      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

      -- Find the name_upper formula column
      local name_upper_idx = nil
      for i, col in ipairs(st.columns) do
        if col == "formula.name_upper" then
          name_upper_idx = i
          break
        end
      end
      assert.truthy(name_upper_idx, "should have formula.name_upper column")

      -- At least one line should have an uppercased value
      local found_value = false
      for _, line in ipairs(lines) do
        local cells = vim.split(line, " │ ", { plain = true })
        local cell = vim.trim(cells[name_upper_idx] or "")
        if cell ~= "" and cell ~= "∅" then
          found_value = true
          -- Verify it's actually uppercased
          assert.are.equal(cell, cell:upper(), "formula should produce uppercased name")
          break
        end
      end
      assert.truthy(found_value, "formula.name_upper should produce non-empty values")
    end)

    it("should apply base filters to select matching notes", function()
      local Bases = require("vault.bases")
      local bases = Bases()

      -- all-notes base has no filters — should show all notes
      local base = bases:get("all-notes")
      assert.truthy(base, "all-notes base should exist")
      assert.falsy(base:has_filters(), "all-notes should have no filters")

      local Notes = require("vault.notes")
      local notes = Notes()
      local total = vim.tbl_count(notes.map)

      editor.open({ notes = notes, base = base })

      local bufnr = vim.api.nvim_get_current_buf()
      local line_count = vim.api.nvim_buf_line_count(bufnr)
      assert.are.equal(total, line_count, "all-notes base should show all notes")
    end)

    it("should skip formula columns when saving edits", function()
      local Base = require("vault.bases.base")
      local base = Base({
        name = "test-skip",
        path = "/tmp/test.base",
        formulas = { greeting = '"Hello"' },
        properties = {
          ["file.name"] = { displayName = "Name" },
          status = { displayName = "Status" },
          ["formula.greeting"] = { displayName = "Greeting" },
        },
        views = {
          { type = "table", name = "Test", order = { "file.name", "status", "formula.greeting" } },
        },
      })

      local Notes = require("vault.notes")
      local notes = Notes()

      editor.open({ notes = notes, base = base, filter_desc = "formula-skip-test" })

      local bufnr = vim.api.nvim_get_current_buf()
      local st = editor._buf_states[bufnr]

      -- Edit a formula cell — this should NOT be written to disk
      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, 1, false)
      local parts = vim.split(lines[1], " │ ", { plain = true })
      -- Find formula column index
      local formula_idx = nil
      for i, col in ipairs(st.columns) do
        if col:match("^formula%.") then formula_idx = i; break end
      end
      if formula_idx and parts[formula_idx] then
        parts[formula_idx] = "HACKED          "
        vim.api.nvim_buf_set_lines(bufnr, 0, 1, false, { table.concat(parts, " │ ") })
      end

      -- Also edit status (should be saved)
      local status_idx = nil
      for i, col in ipairs(st.columns) do
        if col == "status" then status_idx = i; break end
      end
      if status_idx then
        lines = vim.api.nvim_buf_get_lines(bufnr, 0, 1, false)
        parts = vim.split(lines[1], " │ ", { plain = true })
        parts[status_idx] = "formula-test    "
        vim.api.nvim_buf_set_lines(bufnr, 0, 1, false, { table.concat(parts, " │ ") })
      end

      vim.cmd("w")

      -- The file should have status: formula-test but NOT formula.name_upper: HACKED
      local slug = nil
      for s, _ in pairs(st.snapshot) do slug = s; break end
      if slug then
        local path = st.note_paths[slug]
        if path and vim.fn.filereadable(path) == 1 then
          local file_lines = vim.fn.readfile(path, "", 30)
          local has_hacked = false
          for _, l in ipairs(file_lines) do
            if l:match("HACKED") then has_hacked = true end
          end
          assert.falsy(has_hacked, "formula value should NOT be written to disk")
        end
      end
    end)
  end)

  describe("sorting", function()
    after_each(function()
      for _, buf in ipairs(vim.api.nvim_list_bufs()) do
        local n = vim.api.nvim_buf_get_name(buf)
        if n:match("vault://") then
          pcall(vim.api.nvim_buf_delete, buf, { force = true })
        end
      end
      vim.fn.system({ "git", "checkout", "--", "tests/fixtures/demo-vault/" })
    end)

    it("should sort records by a column ascending", function()
      local Notes = require("vault.notes")
      local notes = Notes()

      editor.open({ notes = notes, filter_desc = "sort-asc-test" })

      local bufnr = vim.api.nvim_get_current_buf()
      local st = editor._buf_states[bufnr]

      -- Sort by title ascending
      editor.cycle_sort(bufnr, "title")
      assert.truthy(st.sort_by)
      assert.are.equal("title", st.sort_by.col)
      assert.are.equal("asc", st.sort_by.dir)

      -- Verify lines are sorted
      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      local titles = {}
      for _, line in ipairs(lines) do
        local title = vim.trim((line:match("^(.-)  ") or line):match("^(.-)%s*│") or "")
        table.insert(titles, title:lower())
      end
      for i = 2, #titles do
        assert.truthy(titles[i - 1] <= titles[i],
          string.format("Expected '%s' <= '%s'", titles[i - 1], titles[i]))
      end
    end)

    it("should cycle sort: asc -> desc -> none", function()
      local Notes = require("vault.notes")
      local notes = Notes()

      editor.open({ notes = notes, filter_desc = "sort-cycle-test" })

      local bufnr = vim.api.nvim_get_current_buf()
      local st = editor._buf_states[bufnr]

      -- Cycle 1: asc
      editor.cycle_sort(bufnr, "title")
      assert.are.equal("asc", st.sort_by.dir)

      -- Cycle 2: desc
      editor.cycle_sort(bufnr, "title")
      assert.are.equal("desc", st.sort_by.dir)

      -- Cycle 3: none
      editor.cycle_sort(bufnr, "title")
      assert.is_nil(st.sort_by)
    end)

    it("should apply sort_by from base view", function()
      local Base = require("vault.bases.base")
      local base = Base({
        name = "sort-test",
        path = "/tmp/test.base",
        properties = {
          ["file.name"] = { displayName = "Name" },
          status = { displayName = "Status" },
        },
        views = {
          {
            type = "table",
            name = "Sorted",
            order = { "file.name", "status" },
            sort_by = { key = "file.name", direction = "desc" },
          },
        },
      })

      local Notes = require("vault.notes")
      local notes = Notes()

      editor.open({ notes = notes, base = base, filter_desc = "base-sort-test" })

      local bufnr = vim.api.nvim_get_current_buf()
      local st = editor._buf_states[bufnr]

      -- Sort should be applied from the base
      assert.truthy(st.sort_by)
      assert.are.equal("title", st.sort_by.col)
      assert.are.equal("desc", st.sort_by.dir)

      -- Verify lines are sorted descending
      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      local titles = {}
      for _, line in ipairs(lines) do
        local title = vim.trim((line:match("^(.-)  ") or line):match("^(.-)%s*│") or "")
        table.insert(titles, title:lower())
      end
      for i = 2, #titles do
        assert.truthy(titles[i - 1] >= titles[i],
          string.format("Expected '%s' >= '%s' (desc sort)", titles[i - 1], titles[i]))
      end
    end)
  end)
end)
