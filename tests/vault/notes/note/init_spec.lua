local assert = require("luassert")
local Notes = require("vault.notes")
local Note = require("vault.notes.note")
local config = require("vault.config")

local plugin_path = debug.getinfo(1, "S").source:sub(2):match("(.*/vault.nvim)/.*")
--- @type vault.Config.options.root
local demo_vault_path = string.format("%s/%s", plugin_path, "demo_vault")
config.options.root = demo_vault_path

--- @return vault.path
local function generate_random_path()
    local random_text = string.format("test_note_%s", vim.fn.rand())
    local slug = string.format("%s/%s", "Project", random_text)
    local relpath = string.format("%s%s", slug, config.options.ext)
    local path = string.format("%s/%s", demo_vault_path, relpath)
    return path
end

--- @type vault.path
local note_path = string.format("%s/%s", demo_vault_path, "Project/My awesome neovim plugin.md")
local note = Note(note_path)

--- Generate a new note that does not exist.
--- @return vault.Note
local function generate_note()
    local new_path = generate_random_path()
    if vim.fn.filereadable(new_path) == 1 then
        error("File already exists")
    end

    local new_note = Note({
        path = new_path,
        content = [=[# foobarbuzz
            This is a test note.

            ## Links

            - [[Project/My awesome neovim plugin]]
            ]=],
    })
    return new_note
end

describe("Note:init()", function()
    local function new_note()
        return Note(note_path)
    end

    it("should return a new Note object", function()
        local test_note = new_note()

        assert.is_true(test_note.data.slug == "Project/My awesome neovim plugin")
        assert.is_true(test_note.data.path == note_path)
        assert.is_true(test_note.data.relpath == "Project/My awesome neovim plugin.md")
    end)

    it("should not return a new Note object", function()
        assert.is_false(note.data.slug == "foobarbuzz.md")
    end)
end)

describe("Note:write()", function()
    it("should write a note", function()
        local new_note = generate_note()
        -- try to write the note
        -- then check if the note exists
        -- then delete the note
        local new_path = generate_random_path()
        new_note:write(new_path)
        new_note.data.path = new_path
        assert.is_true(vim.fn.filereadable(new_note.data.path) == 1)
        vim.fn.delete(new_note.data.path)
    end)
end)

describe("Note.data.outlinks", function()
    local function get_outlinks()
        return note.data.outlinks
    end

    it("should return a table of outlinks", function()
        local outlinks = get_outlinks()
        assert.is_true(type(outlinks) == "table")
    end)
end)

describe("Note.data.inlinks", function()
    local function get_inlinks()
        return note.data.inlinks
    end

    it("should return a table of inlinks", function()
        local inlinks = get_inlinks()
        assert.is_true(type(inlinks) == "table")
    end)
end)
