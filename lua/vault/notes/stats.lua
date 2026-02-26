local Object = require("vault.core.object")
local state = require("vault.core.state")
local Error = require("vault.utils.error")

--- @class vault.Stats: vault.Object
local Stats = Object("VaultStats")

--- @param notes vault.Notes
function Stats:init(notes)
    if not notes then
        error(Error.MISSING_PARAMETER("notes"))
    end

    self.notes = notes
end

function Stats:average_content_length()
    local total_content_count = 0
    for _, note in pairs(self.notes.map) do
        local note_content = note.data.content
        local note_content_count = #note_content
        total_content_count = total_content_count + note_content_count
    end

    local average_chars = total_content_count / self.notes:count()

    average_chars = math.floor(average_chars * 100) / 100
    return average_chars
end

function Stats:total_content_length()
    local total_content_count = 0
    for _, note in pairs(self.notes.map) do
        local note_content = note.data.content
        local note_content_count = #note_content
        total_content_count = total_content_count + note_content_count
    end
    return total_content_count
end

function Stats:shortest_note()
    local shortest_length = math.huge
    local shortest_note = nil

    for _, note in pairs(self.notes.map) do
        local content_length = #note.data.content
        if content_length < shortest_length then
            shortest_length = content_length
            shortest_note = note
        end
    end

    return shortest_note
end

function Stats:longest_note()
    local longest_length = 0
    local longest_note = nil

    for _, note in pairs(self.notes.map) do
        local content_length = #note.data.content
        if content_length > longest_length then
            longest_length = content_length
            longest_note = note
        end
    end

    return longest_note
end

function Stats:word_count()
    local total_words = 0
    for _, note in pairs(self.notes.map) do
        local content = note.data.content
        local words = 0
        for word in content:gmatch("%S+") do
            words = words + 1
        end
        total_words = total_words + words
    end
    return total_words
end

function Stats:average_words_per_note()
    local total_words = self:word_count()
    local average = total_words / self.notes:count()
    return math.floor(average * 100) / 100
end

function Stats:created_this_week()
    local count = 0
    local current_time = os.time()
    local week_seconds = 7 * 24 * 60 * 60

    for _, note in pairs(self.notes.map) do
        if note.data.created_at and (current_time - note.data.created_at) <= week_seconds then
            count = count + 1
        end
    end
    return count
end

function Stats:most_linked_note()
    local link_counts = {}
    local most_linked = nil
    local max_links = 0

    for _, note in pairs(self.notes.map) do
        link_counts[note.id] = 0
    end

    for _, note in pairs(self.notes.map) do
        if note.data.links then
            for _, link in ipairs(note.data.links) do
                if link_counts[link] then
                    link_counts[link] = link_counts[link] + 1
                    if link_counts[link] > max_links then
                        max_links = link_counts[link]
                        most_linked = self.notes.map[link]
                    end
                end
            end
        end
    end

    return most_linked, max_links
end

--- @alias VaultStats.constructor fun(notes: vault.Notes): vault.Stats
--- @type VaultStats.constructor|vault.Stats
local VaultStats = Stats

state.set_global_key("class.vault.Stats", VaultStats)
return VaultStats
