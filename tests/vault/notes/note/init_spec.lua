local assert = require("luassert")
local Note = require("vault.notes.note")

local test_note_path = "~/vault.nvim/test_vault/Project/My awesome neovim plugin.md"

describe("Note", function()

  it("should return a new Note object", function()
    local note = Note(vim.fn.expand(test_note_path))
    print(vim.inspect(note.data.basename))
    assert.is_true(note.data.basename == "README.md")
    assert.is_true(note.data.path == vim.fn.expand(test_note_path))
    assert.is_true(note["data.relpath"] == "README.md")
  end)

  it("should not return a new Note object", function()
    local note = Note(test_note_path)
    assert.is_false(note.data.basename == "foobarbuzz.md")
  end)
end)
