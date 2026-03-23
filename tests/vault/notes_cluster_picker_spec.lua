local MODULE = "telescope._extensions.vault.pickers.notes_cluster"

describe("vault notes cluster picker", function()
    local originals

    before_each(function()
        originals = {
            notes = package.loaded["vault.notes"],
            note = package.loaded["vault.notes.note"],
            cluster = package.loaded["vault.notes.cluster"],
            picker = package.loaded["telescope._extensions.vault.pickers.notes"],
            module = package.loaded[MODULE],
        }

        package.loaded[MODULE] = nil
    end)

    after_each(function()
        package.loaded["vault.notes"] = originals.notes
        package.loaded["vault.notes.note"] = originals.note
        package.loaded["vault.notes.cluster"] = originals.cluster
        package.loaded["telescope._extensions.vault.pickers.notes"] = originals.picker
        package.loaded[MODULE] = originals.module
    end)

    it("passes the computed cluster to the notes picker", function()
        local captured
        local fake_notes = { class = { name = "VaultNotes" } }
        local fake_note = { data = { path = "/tmp/current.md" } }
        local fake_cluster = {
            map = {
                ["cluster-center"] = true,
                ["cluster-neighbor"] = true,
            },
        }

        package.loaded["vault.notes"] = function()
            return fake_notes
        end
        package.loaded["vault.notes.note"] = function(path)
            assert.are.equal("/tmp/current.md", path)
            return fake_note
        end
        package.loaded["vault.notes.cluster"] = function(notes, note, depth)
            assert.are.equal(fake_notes, notes)
            assert.are.equal(fake_note, note)
            assert.are.equal(2, depth)
            return fake_cluster
        end
        package.loaded["telescope._extensions.vault.pickers.notes"] = function(opts)
            captured = opts
            return "picker"
        end

        local picker = require(MODULE)
        local result = picker({ path = "/tmp/current.md", depth = 2 })

        assert.are.equal("picker", result)
        assert.are.equal(fake_cluster, captured.notes)
        assert.are.equal("/tmp/current.md", captured.path)
        assert.are.equal(2, captured.depth)
    end)
end)
