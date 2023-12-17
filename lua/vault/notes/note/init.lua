local Object = require("vault.core.object")

local utils = require("vault.utils")
---@type VaultConfig|VaultConfig.options
local config = require("vault.config")
local metadata = require("vault.notes.note.metadata")
local data = require("vault.notes.note.data")
local state = require("vault.core.state")

---@class VaultNote.data: VaultObject
local NoteData = Object("VaultNoteData")

---@param this VaultNote.data
function NoteData:init(this)
    this = this or {}
    for k, _ in pairs(this) do
        -- if not metadata.is_valid(k) then
        if not data[k] then
            error(
                "Invalid key: " .. vim.inspect(k) .. ". Valid keys: " .. vim.inspect(metadata.keys)
            )
        end
    end
    for k, v in pairs(this) do
        self[k] = v
    end
    self.slug = this.slug or utils.path_to_slug(this.path)
    self.relpath = this.relpath or utils.path_to_relpath(this.path)
end

function NoteData:__index(key)
    self[key] = rawget(self, key) or data[key](self)
    if self[key] == nil then
        error("Invalid key: " .. vim.inspect(key) .. ". Valid keys: " .. vim.inspect(metadata.keys))
    end
    return self[key]
end

--- Create a new note if it does not exist.
---
---@class VaultNote: VaultObject
---@field data VaultNote.data - The data of the note.data.
local Note = Object("VaultNote")

---@param this VaultPath.absolute|VaultNote.data
function Note:init(this)
    if type(this) == "string" then -- it's a possible path to the note
        local path = vim.fn.expand(this)
        -- assert(type(path) == "string", "Failed to expand path: " .. vim.inspect(path))
        if type(path) ~= "string" then
            error("Failed to expand path: " .. vim.inspect(path))
        end
        this = {
            path = path,
        }
    end

    if type(this) ~= "table" then
        error("Invalid argument: " .. vim.inspect(this))
    end

    if not this.path then
        error("missing `path` : " .. vim.inspect(this))
    end

    -- this.relpath = this.relpath or utils.path_to_relpath(this.path)

    ---@type VaultNote.data
    local note_data = NoteData(this)
    self.data = note_data
end

function Note:__tostring()
    return "VaultNote: " .. vim.inspect(self)
end

--- Write note file to the specified path.
---
---@param path string?
---@param content string?
function Note:write(path, content)
    path = path or self.data.path
    if type(path) ~= "string" then
        error("Invalid path: " .. vim.inspect(path))
    end

    content = content or self.data.content

    local root_dir = config.root
    local ext = config.ext

    if not path:match(ext .. "$") then
        error("Invalid file extension: " .. vim.inspect(path))
    end

    if not path:match(root_dir) then
        error("Invalid path: " .. vim.inspect(path))
    end

    local basename = vim.fn.fnamemodify(path, ":t")
    if not basename then
        error("Invalid basename: " .. vim.inspect(path))
    end

    local f = io.open(path, "w")
    if not f then
        error("Failed to open file: " .. vim.inspect(path))
    end

    f:write(content)
    f:close()

    if config.notify.on_write == true then
        vim.notify("Note created: " .. path)
    end
end

--- Edit note
---
---@class VaultNote
---@param path string
function Note:edit(path)
    path = path or self.data.path
    if vim.fn.filereadable(path) == 0 then
        error("File not found: " .. path)
        return
    end
    vim.cmd("e " .. path)
end

--- Open a note in the vault
---
---@class VaultNote
---@param path string
function Note:open(path)
    path = path or self.data.path
    -- if path.sub(1, -4) ~= ".md" then
    local ext = config.ext
    local pattern = ext .. "$"
    if path:match(pattern) == nil then
        ---@type VaultNote
        local note = Note({
            path = path,
        })
        if note == nil then
            return
        end
        path = note.data.path
    end

    vim.cmd("e " .. path)
end

--- Preview with Glow.nvim
---
function Note:preview()
    if vim.fn.executable("glow") == 0 and package.loaded["glow"] == nil then
        vim.notify("Glow is not installed")
        return
    end
    vim.cmd("Glow " .. self.data.path)
end

--- Check if note has an exact tag name.
---
---@param tag_name string - Exact tag name to search for.
---@param match_opt VaultMatchOptsKey? - Match option. @see utils.matcher
function Note:has_tag(tag_name, match_opt)
    if not tag_name then
        error("`tag_name` is required")
    end
    local note_tags = self.data.tags
    if not note_tags then
        return false
    end

    match_opt = match_opt or "exact"

    for _, tag in ipairs(note_tags) do
        if utils.match(tag.data.name, tag_name, match_opt) then
            return true
        end
    end
    return false
end

-- TEST: This function is not tested.
---@param path string - The path to the note to update inlinks.
function Note:update_inlinks(path)
    local root_dir = config.root
    if type(root_dir) ~= "string" then
        return
    end

    if type(path) ~= "string" then
        return
    end

    local relpath = utils.path_to_relpath(path) -- current note path with relative path
    if relpath:sub(#relpath - 2) == ".md" then
        relpath = relpath:sub(1, #relpath - 3)
    end

    local inlinks = self.data.inlinks
    if inlinks == nil then
        return
    end

    for _, inlink in ipairs(inlinks) do
        local new_link = inlink.link
        local new_link_title = relpath -- new link title will be relative path to the current note
        if inlink.heading ~= nil then
            new_link_title = new_link_title .. "#" .. inlink.heading
        end
        if inlink.custom_title ~= nil then
            new_link_title = new_link_title .. "|" .. inlink.custom_title
        end
        new_link = new_link:gsub(inlink.link, new_link_title)
        local f = io.open(inlink.source.data.path, "r")
        if f == nil then
            return
        end
        local content = f:read("*all")
        f:close()
        content = content:gsub(inlink.link, new_link)
        f = io.open(inlink.source.data.path, "w")
        if f == nil then
            return
        end
        f:write(content)
        f:close()
        vim.notify(inlink.link .. " -> " .. new_link)
    end
end

--- Compare two values of a note keys.
---
---@param key_a string - The key to compare.
---@param key_b string - The key to compare.
function Note:compare_values_of(key_a, key_b)
    if not metadata.is_valid(key_a) then
        error(
            "Invalid key: " .. vim.inspect(key_a) .. ". Valid keys: " .. vim.inspect(metadata.keys)
        )
    end
    if not metadata.is_valid(key_b) then
        error(
            "Invalid key: " .. vim.inspect(key_b) .. ". Valid keys: " .. vim.inspect(metadata.keys)
        )
    end

    if type(key_a) ~= "string" or type(key_b) ~= "string" then
        return false
    end

    if self[key_a] == nil or self[key_b] == nil then
        return false
    end

    if self[key_a] == self[key_b] then
        return true
    end

    return false
end

---@alias VaultNote.constructor fun(this: VaultNote|string): VaultNote
---@type VaultNote|VaultNote.constructor
local VaultNote = Note

state.set_global_key("_class.VaultNote", VaultNote)
return VaultNote -- [[@as VaultNote.constructor]]
