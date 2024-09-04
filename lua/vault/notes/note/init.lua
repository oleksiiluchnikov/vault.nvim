local Object = require("vault.core.object")
local fetcher = require("vault.fetcher")

local utils = require("vault.utils")
--- @type vault.Config|vault.Config.options
local config = require("vault.config")
local metadata = require("vault.notes.note.metadata")
local data = require("vault.notes.note.data")
local state = require("vault.core.state")

--- State object for |vault.Note|.
--- @class vault.Note.Data: vault.Object
local NoteData = Object("VaultNoteData")

--- @param this vault.Note.Data
function NoteData:init(this)
    this = this or {}
    for k, _ in pairs(this) do
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

--- Metamethod to handle indexing into `VaultNote.data` table.
---
--- This allows accessing fields like regular table fields.
--- It will first check if the field already exists, if not it will initialize it by calling the corresponding function in the data table.
---
--- @param key string
--- @return any
function NoteData:__index(key)
    --- Initialize field if not set
    self[key] = rawget(self, key) or data[key](self)

    if self[key] == nil then
        error("Invalid key: " .. vim.inspect(key) .. ". Valid keys: " .. vim.inspect(metadata.keys))
    end

    return self[key]
end

--- Create a new note if it does not exist.
---
--- @class vault.Note: vault.Object
--- @field data vault.Note.Data - The data of the note.data.
local Note = Object("VaultNote")

--- Initialize a new Note object.
---
--- This handles converting a path string to a note data table.
--- It also validates the note data and initializes the NoteData object.
---
--- @param this vault.path|vault.Note.Data - Either a path string or note data table.
function Note:init(this)
    if type(this) == "string" then -- it's a possible path to the note
        local path = vim.fn.expand(this)

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

    utils.validate_path(this.path)

    --- @type vault.Note.Data
    local note_data = NoteData(this)

    self.data = note_data
end

--- @param path vault.path - The path to the note to delete.
local function validate_new_path(path)
    if type(path) ~= "string" then
        error("Invalid path: " .. vim.inspect(path))
    end

    if path == "" then
        error("Invalid path: " .. vim.inspect(path))
    end

    if not path:match(config.options.ext .. "$") then
        error("Invalid file extension: " .. vim.inspect(path))
    end

    if vim.fn.filereadable(path) == 1 then
        error("File already exists: " .. vim.inspect(path))
    end

    local basename = vim.fn.fnamemodify(path, ":t")
    if not basename then
        error("Invalid basename: " .. vim.inspect(path))
    end
end

--- Write note file to the specified path.
---
--- @param path? vault.path - The path to write the note to.
--- @param force? boolean - Whether to force the write even if the file already exists.
function Note:write(path, force)
    path = path or self.data.path
    validate_new_path(path)

    local content = self.data.content or ""
    local content_lines = vim.split(content, "\n")
    if vim.fn.filereadable(path) == 1 then
        vim.fn.writefile(content_lines, path)
        if config.options.notify.on_write == true then
            vim.notify("Note created: " .. path)
        end
        return
    end

    local slug = self.data.slug or utils.path_to_slug(path)
    -- Check if the note with same basename exists in the whole vault
    -- if config.options.check_duplicate_basename == true then
    if config.options.check_duplicate_basename == true or force == false then
        local new_stem = vim.fn.fnamemodify(path, ":t:r")
        --- @type table<string, table<string, string>>
        local paths = fetcher.paths()
        for _, t in pairs(paths) do
            local stem = vim.fn.fnamemodify(t.path, ":t:r")
            if utils.match(stem, new_stem, "exact", false) == true then
                vim.notify("Note with same stem already exists: " .. vim.inspect(t.slug))
                return
            end
        end
    end
    if slug:find("/") then
        vim.fn.mkdir(vim.fn.fnamemodify(path, ":p:h"), "p")
    end

    vim.fn.writefile(content_lines, path)
    if config.options.notify.on_write == true then
        vim.notify("Note created: " .. path)
    end
end

--- Edit note
---
--- @class vault.Note
--- @param path? string
function Note:edit(path)
    path = path or self.data.path
    if vim.fn.filereadable(path) == 0 then
        error("File not found: " .. path)
        return
    end
    vim.cmd("e " .. path)
end

--- Preview with Glow.nvim
---
function Note:preview()
    local previewer = config.options.previewer or "glow"

    if vim.fn.executable(previewer) == 0 and package.loaded["glow"] == nil then
        vim.notify("Glow is not installed")
        return
    end
    vim.cmd("Glow " .. self.data.path)
end

--- Check if note has an exact tag name.
---
--- @param tag_name string - Exact tag name to search for.
--- @param match_opt? vault.enum.MatchOpts.key - Match option. @see utils.matcher
function Note:has_tag(tag_name, match_opt)
    if not tag_name then
        error("`tag_name` is required")
    end
    local note_tags = self.data.tags
    if not note_tags then
        return false
    end

    match_opt = match_opt or "exact"

    for _, tag in pairs(note_tags) do
        if utils.match(tag.data.name, tag_name, match_opt) then
            return true
        end
    end
    return false
end

-- TEST: This function is not tested.
--- @param path string - The path to the note to update inlinks.
function Note:update_inlinks(path)
    local root_dir = config.options.root
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
--- @param key_a string - The key to compare.
--- @param key_b string - The key to compare.
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

--- Refreshes the buffers for the given paths in the current Neovim instance.
---@param paths vault.path[]
local function refresh_buffers(paths)
    local bufnrs = vim.fn.getbufinfo({ buflisted = 1 })
    for _, path in ipairs(paths) do
        for _, bufinfo in ipairs(bufnrs) do
            if bufinfo.name == path then
                vim.api.nvim_buf_call(bufinfo.bufnr, function()
                    vim.cmd("e")
                end)
            end
        end
    end
end

--- Handle existing note stem
--- @param new_path vault.path
--- @return vault.slug
local function handle_existing_note_stem(new_path)
    --- @type vault.Notes
    local notes = state.get_global_key("notes") or require("vault.notes")()
    notes:init()
    local new_stem = utils.path_to_stem(new_path)
    local new_slug = utils.path_to_slug(new_path)
    local is_stem_exists = notes:has_note("stem", new_stem)

    if is_stem_exists == true then
        new_slug = vim.fn.input("New slug: ")
    end
    return new_slug
end

-- Create parent directories if they don't exist
--- @param path vault.path
--- @return nil
local function create_parent_directories(path)
    local new_path_dir = vim.fn.fnamemodify(path, ":p:h")
    vim.fn.mkdir(new_path_dir, "p")
    -- TODO: notify if the directory doesn't exist and created
end

--- Rename(Move) a note and update connected notes.
--- @param new_path vault.path - The new path to move the note to.
--- @param force? boolean - Whether to force rename even if the note with the same stem already exists.
--- @param verbose? boolean - Whether to print a notification when the connected notes are updated.
function Note:move(new_path, force, verbose)
    if self.data.path == new_path then
        vim.notify("Same path: " .. vim.inspect(new_path))
        return
    end
    force = force or false
    verbose = verbose or true

    if new_path == "" then
        error("Invalid path: " .. vim.inspect(new_path))
    end

    create_parent_directories(new_path)

    --- @type vault.slug[]
    local inlinks = vim.tbl_keys(self.data.inlinks)
    -- local has_inlinks = next(inlinks) ~= nil
    --

    local paths_to_update = {}
    if next(inlinks) ~= nil then
        -- local paths_to_update = vim.tbl_map(function()
        --     return utils.slug_to_path(path)
        -- end, inlinks)
        for slug, _ in pairs(inlinks) do
            paths_to_update[utils.slug_to_path(slug)] = true
        end

        local prev_wikilink = self.data.slug
        local new_wikilink = utils.path_to_slug(new_path)
        local message = ""
        if verbose then
            message = prev_wikilink .. " -> " .. new_wikilink .. " in " .. self.data.slug
        end
        -- Update connected notes
        for path, _ in pairs(paths_to_update) do
            local note = Note(path)
            note:update_content(prev_wikilink, new_wikilink)
            if verbose then
                message = message
                    .. "\n"
                    .. prev_wikilink
                    .. " -> "
                    .. new_wikilink
                    .. " in "
                    .. note.data.slug
            end
        end
        if verbose then
            vim.notify("", vim.log.levels.INFO, {
                title = "Vault",
                on_open = function(win)
                    local buf = vim.api.nvim_win_get_buf(win)
                    vim.api.nvim_set_option_value("filetype", "markdown", { buf = buf })
                    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { message })
                end,
                timeout = 100,
            })
        end
    end

    vim.fn.rename(self.data.path, new_path)

    -- Update note data
    self.data.path = new_path
    self.data.slug = utils.path_to_slug(new_path)

    ---@type vault.path[]
    local paths_to_refresh = {
        self.data.path,
    }
    paths_to_refresh = vim.list_extend(paths_to_refresh, vim.deepcopy(paths_to_update) or {}) -- TODO: check if this is needed
    refresh_buffers(paths_to_refresh)
end

--- This will rename the note file and update the note data, and connected notes.
--- @param slug vault.slug
function Note:rename(slug)
    if type(slug) ~= "string" then
        error("Invalid new name: " .. vim.inspect(slug))
    end

    local new_path = utils.slug_to_path(slug)

    self:move(new_path)
end

--- Update content of the note
--- @param search_string string
--- @param replace_string string
--- @param lnums? vault.source.lnums
function Note:update_content(search_string, replace_string, lnums)
    if type(search_string) ~= "string" then
        return
    end
    if type(replace_string) ~= "string" then
        return
    end
    local root_dir = config.options.root
    local f, err = io.open(self.data.path, "r")
    if not f then
        return
    end
    local content = f:read("*all")
    f:close()
    local lines = vim.split(content, "\n")
    if next(lines) == nil then
        return
    end

    -- TODO: handle multiple matches in whole file
    -- sources = {
    --   ["Meta/finace-freedom"] = {
    --     [10] = {
    --       ["end"] = 13,
    --       line = "#finance-freedom #finance #freedom",
    --       start = 1
    --     }
    --   }
    -- },
    if lnums then
        for _, occurence in pairs(lnums) do
            local line = lines[occurence.lnum_start]
            if line and utils.match(line, search_string, "contains", false) == true then
                local escaped_search_string = vim.pesc(search_string)
                lines[occurence.lnum_start] = line:gsub(escaped_search_string, replace_string)
            end
        end
    else
        for i, line in pairs(lines) do
            if utils.match(line, search_string, "contains", false) == true then
                local escaped_search_string = vim.pesc(search_string)
                lines[i] = line:gsub(escaped_search_string, replace_string)
            end
        end
    end

    -- write the new content to the file
    f, err = io.open(self.data.path, "w")
    if f == nil then
        error(err)
        return
    end
    f:write(table.concat(lines, "\n"))
    f:close()
end

--- Get list of available metohods
--- @return string[]
function Note:methods()
    local methods = {}
    for k, _ in pairs(self.__meta) do
        table.insert(methods, k)
    end
    return methods
end

--- @alias vault.Note.constructor fun(this: vault.Note|string): vault.Note
--- @type vault.Note|vault.Note.constructor
local VaultNote = Note

state.set_global_key("class.vault.Note", VaultNote)

--- @alias vault.Note.data.constructor fun(this: vault.Note.Data): vault.Note.Data -- [[@as VaultNote.data.constructor]]
--- @type vault.Note.data.constructor|vault.Note.Data
local VaultNoteData = NoteData
state.set_global_key("class.vault.NoteData", VaultNoteData)
return VaultNote -- [[@as VaultNote.constructor]]
