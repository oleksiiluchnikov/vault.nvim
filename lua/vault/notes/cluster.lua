--- That module contains `VaultNotesCluster` class.
local state = require("vault.core.state")
local error_formatter = require("vault.utils.error_formatter")

---@type VaultNotes.constructor
local Notes = state.get_global_key("_class.VaultNotes") or require("vault.notes")

---@class VaultNotesCluster: VaultNotes
--- Is sub set of `VaultNotes` object.
--- It used to build local scope of notes based on the note.
--- We could explore to look related notes.
--- On :increase_depth() it will expand the cluster by one level(one nesting level).
--- On :decrease_depth() it will decrease the cluster by one level(one nesting level).
--- On :reset_depth() it will reset the cluster to the initial state.
---@field notes VaultNotes|VaultNotesGroup -- The notes object which is the source of the cluster.
---@field note VaultNote -- The note which is the center of the cluster.
---@field depth number -- How deep we should go to fetch the cluster.
---@field map VaultMap.notes
---@diagnostic disable-next-line: undefined-field
local NotesCluster = Notes:extend("VaultNotesCluster")

--- Create new instance of `VaultNotesCluster`.
---
---@param notes VaultNotes
---@param note VaultNote
---@param depth number
function NotesCluster:init(notes, note, depth)
    if not note then
        error(error_formatter.missing_parameter("note"))
    end
    if not depth then
        error(error_formatter.missing_parameter("depth"))
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
---@return VaultNotesCluster
function NotesCluster:increase_depth()
    self.depth = self.depth + 1
    -- self:reset()
    self:fetch_cluster()
    return self
end

--- Decrease the depth of the cluster.
---
---@return VaultNotesCluster
function NotesCluster:decrease_depth()
    self.depth = self.depth - 1
    -- self:reset()
    self:fetch_cluster()
    return self
end

--- Reset the cluster to the initial state.
---
---@return VaultNotesCluster
function NotesCluster:reset_depth()
    self.depth = 0
    -- self:reset()
    self:fetch_cluster()
    return self
end

--- Fetch cluster of notes.
---
---@return VaultNotesCluster
function NotesCluster:fetch_cluster()
    ---@type VaultWikilinks
    local wikilinks = state.get_global_key("wikilinks") or self.notes:wikilinks()
    local notes = self.notes

    --- Fetch cluster recursively.
    ---
    ---@param note VaultNote
    ---@param depth number
    ---@return nil
    local function fetch_cluster_recursively(note, depth)
        -- depth = depth - 1
        if not note or not depth then
            -- error(error_formatter.missing_parameter("note or depth"))
            error("Missing parameter: note or depth")
        end

        --- Process note.
        ---
        ---@param target_note VaultNote
        ---@return nil
        local function process_note(target_note)
            if not target_note then
                return
            end
            if not target_note.class or target_note.class.name ~= "VaultNote" then
                return
            end

            if target_note then
                -- self:add_note(target_note)
                self.map[target_note.data.slug] = target_note
                if depth > 0 then
                    fetch_cluster_recursively(target_note, depth - 1)
                end
            end
        end

        ---@type VaultWikilinksGroup
        local wikilinks_group = {
            inlinks = wikilinks:by_target(note.data.slug, "exact"),
            outlinks = note.data.outlinks,
            resolved = {},
            unresolved = {},
        }

        for link_type, link in pairs(wikilinks_group) do
            for _, link in pairs(link) do
                if link_type == "inlinks" then
                    ---@type VaultMap.sources
                    local sources = link.sources
                    if sources then
                        for source, _ in pairs(sources) do
                            if not self.map[source] then
                                process_note(notes._raw_map[source])
                                goto continue
                            end
                        end
                    end
                end
                if link_type == "outlinks" then
                    local target = link.target
                    if target then
                        if not self.map[target] then
                            process_note(notes._raw_map[target])
                        end
                    end
                end
                ::continue::
            end
        end
    end

    fetch_cluster_recursively(self.note, self.depth)

    state.set_global_key("notes.cluster", self)
    return self
end

---@alias VaultNotesCluster.constructor fun(notes: VaultNotes, note: VaultNote, depth: number): VaultNotesCluster
---@type VaultNotesCluster.constructor|VaultNotesCluster
local VaultNotesCluster = NotesCluster

state.set_global_key("_class.VaultNotesCluster", VaultNotesCluster)
return VaultNotesCluster
