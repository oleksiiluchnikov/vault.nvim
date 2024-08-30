--- That module contains `VaultNotesCluster` class.
local state = require("vault.core.state")
local error_msg = require("vault.utils.fmt.error")

--- @type vault.Notes.constructor|vault.Notes
local Notes = require("vault.notes")

--- @class VaultNotesCluster: vault.Notes
--- Is sub set of `VaultNotes` object.
--- It used to build local scope of notes based on the note.
--- We could explore to look related notes.
--- On :increase_depth() it will expand the cluster by one level(one nesting level).
--- On :decrease_depth() it will decrease the cluster by one level(one nesting level).
--- On :reset_depth() it will reset the cluster to the initial state.
--- @field notes vault.Notes|vault.Notes.Group -- The notes object which is the source of the cluster.
--- @field note vault.Note -- The note which is the center of the cluster.
--- @field depth number -- How deep we should go to fetch the cluster.
--- @field map vault.Notes.map
--- @diagnostic disable-next-line: undefined-field
local NotesCluster = Notes:extend("VaultNotesCluster")

--- Create new instance of `VaultNotesCluster`.
---
--- @param notes vault.Notes
--- @param note vault.Note
--- @param depth number
function NotesCluster:init(notes, note, depth)
    if not note then
        error(error_msg.MISSING_PARAMETER("note"))
    end
    if not depth then
        error(error_msg.MISSING_PARAMETER("depth"))
    end

    self.notes = notes
    self.note = note
    self.depth = depth
    self.map = {}
    self._raw_map = {}

    -- self:increase_depth()
    self:fetch_cluster()
end

--- Increase the depth of the cluster.
---
--- @return VaultNotesCluster
function NotesCluster:increase_depth()
    self.depth = self.depth + 1
    -- self:reset()
    self:fetch_cluster()
    return self
end

--- Decrease the depth of the cluster.
---
--- @return VaultNotesCluster
function NotesCluster:decrease_depth()
    self.depth = self.depth - 1
    -- self:reset()
    self:fetch_cluster()
    return self
end

--- Reset the cluster to the initial state.
---
--- @return VaultNotesCluster
function NotesCluster:reset_depth()
    self.depth = 0
    -- self:reset()
    self:fetch_cluster()
    return self
end

--- Fetch cluster of notes.
---
--- @return VaultNotesCluster
function NotesCluster:fetch_cluster()
    local notes = self.notes
    --- Fetch cluster recursively.
    ---
    --- @param note vault.Note
    --- @param depth number
    --- @return nil
    local function fetch_cluster_recursively(note, depth)
        -- depth = depth - 1
        if not note or not depth then
            -- error(error_formatter.missing_parameter("note or depth"))
            error("Missing parameter: note or depth")
        end

        --- Process note.
        ---
        --- @param target_note vault.Note
        --- @return nil
        local function process_note(target_note)
            if not target_note then
                return
            elseif not target_note.class or target_note.class.name ~= "VaultNote" then
                return
            end

            self.map[target_note.data.slug] = target_note
            if depth > 0 then
                fetch_cluster_recursively(target_note, depth - 1)
            end
        end

        local inlinks = note.data.inlinks

        --- @type table<vault.slug, vault.Note>
        local inlinks_sources = {}
        for slug, wikilinks in pairs(inlinks) do
            for _, wikilink in pairs(wikilinks) do
                local sources = wikilink.data.sources
                for source, _ in pairs(sources) do
                    inlinks_sources[source] = self.notes._raw_map[source]
                end
            end
        end

        local outlinks = note.data.outlinks
        --- @type table<vault.slug, vault.Note>
        local targets = {}
        for slug, wikilink in pairs(outlinks) do
            local target = wikilink.data.target
            if target then
                targets[target] = self.notes._raw_map[target]
            end
        end

        local notes_group = vim.tbl_extend("keep", inlinks_sources, targets)

        for _, target_note in pairs(notes_group) do
            process_note(target_note)
        end
    end

    fetch_cluster_recursively(self.note, self.depth)

    state.set_global_key("notes.cluster", self)
    return self
end

--- @alias VaultNotesCluster.constructor fun(notes: vault.Notes, note: vault.Note, depth: number): VaultNotesCluster
--- @type VaultNotesCluster.constructor|VaultNotesCluster
local VaultNotesCluster = NotesCluster

state.set_global_key("class.vault.NotesCluster", VaultNotesCluster)
return VaultNotesCluster
