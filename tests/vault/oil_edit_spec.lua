-- tests/vault/oil_edit_spec.lua
-- Tests for oil_edit extmark drift reconciliation.

local fixture_root = vim.fn.getcwd() .. "/tests/fixtures/demo-vault"

describe("oil_edit", function()
  local oil_edit

  before_each(function()
    package.loaded["vault.oil_edit"] = nil
    oil_edit = require("vault.oil_edit")
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

      oil_edit.open({ notes = notes, filter_desc = "test-open" })

      local bufnr = vim.api.nvim_get_current_buf()
      local name = vim.api.nvim_buf_get_name(bufnr)
      assert.truthy(name:match("vault://process/test%-open"))

      local line_count = vim.api.nvim_buf_line_count(bufnr)
      assert.are.equal(vim.tbl_count(notes.map), line_count)

      -- All lines should have extmark identity
      local st = oil_edit._buf_states[bufnr]
      assert.truthy(st, "buf_states should have entry")
      local NS = vim.api.nvim_create_namespace("vault_oil_edit")
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

      oil_edit.open({ notes = notes, filter_desc = "test-drift" })
      local bufnr = vim.api.nvim_get_current_buf()
      local st = oil_edit._buf_states[bufnr]
      local NS = vim.api.nvim_create_namespace("vault_oil_edit")
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
      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      for i = 1, #lines do
        local parts = vim.split(lines[i], " │ ", { plain = true })
        if parts[2] then parts[2] = "done         " end
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

      oil_edit.open({ notes = notes, filter_desc = "test-no-corrupt" })
      local bufnr = vim.api.nvim_get_current_buf()
      local st = oil_edit._buf_states[bufnr]
      local line_count = vim.api.nvim_buf_line_count(bufnr)

      -- Record the title for each slug from the file (ground truth)
      local slug_titles = {}
      for slug, snap in pairs(st.snapshot) do
        slug_titles[slug] = snap.title
      end

      -- Edit status on all lines
      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
      for i = 1, #lines do
        local parts = vim.split(lines[i], " │ ", { plain = true })
        if parts[2] then parts[2] = "batch-test   " end
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
end)
