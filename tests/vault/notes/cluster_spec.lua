-- Import the classes and modules
local Notes = require("vault.notes")
local Note = require("vault.notes.note")
local NotesCluster = require("vault.notes.cluster")
local assert = require("luassert")
local config = require("vault.config")

local plugin_path = debug.getinfo(1, "S").source:sub(2):match("(.*/vault.nvim)/.*")
--- @type vault.Config.options.root
local demo_vault_path = plugin_path .. "/demo_vault"
config.options.root = demo_vault_path

local note = Note(string.format("%s/%s", demo_vault_path, "Project/My awesome neovim plugin.md"))

describe("NotesCluster", function()
    --- @type vault.Notes
    local notes
    --- @type vault.Note
    local note

    before_each(function()
        -- Initialize any necessary objects or variables
        notes = Notes() -- You may need to adjust this based on your actual implementation
        note = Note(test_path)
    end)

    it("should initialize", function()
        local cluster = NotesCluster(notes, note, 0)
        assert(cluster)
    end)

    it("should increase depth", function()
        local cluster = NotesCluster(notes, note, 0)
        cluster:increase_depth()
        assert(cluster.depth == 1)
    end)

    it("should decrease depth", function()
        local cluster = NotesCluster(notes, note, 1)
        cluster:decrease_depth()
        assert(cluster.depth == 0)
    end)

    it("should reset depth", function()
        local cluster = NotesCluster(notes, note, 1)
        cluster:reset_depth()
        assert(cluster.depth == 0)
    end)

    it("should fetch cluster", function()
        local cluster = NotesCluster(notes, note, 0)
        cluster:fetch_cluster()
        assert(cluster)
    end)

    it("should fetch cluster recursively", function()
        local cluster = NotesCluster(notes, note, 0)
        cluster:fetch_cluster()
        assert(cluster)
    end)

    it("should not have equal `VaultNotesCluster` instances", function()
        local cluster_a = NotesCluster(notes, note, 0)
        local cluster_b = NotesCluster(notes, note, 1)

        assert(cluster_a:count() ~= cluster_b:count())
    end)
end)
