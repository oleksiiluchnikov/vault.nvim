local Object = require("vault.core.object")
local function scanner()
    return require("vault.scanner")
end

local utils = require("vault.utils")
--- @type vault.Config|vault.Config.options
local config = require("vault.config")
local data = require("vault.notes.note.data")
local state = require("vault.core.state")

local metadata = {}

metadata.unique = {
    relpath = true,
    path = true,
}

metadata.keys = {
    relpath = true,
    path = true,
    basename = true,
    stem = true,
    title = true,
    content = true,
    frontmatter = true,
    body = true,
    tags = true,
    inlinks = true,
    outlinks = true,
    type = true,
    status = true,
}

function metadata.is_valid(key)
    return metadata.keys[key] ~= nil
end

--- @class vault.Note.Data.basename
local NoteBasename = Object("VaultNoteBasename")

function NoteBasename:init(s)
    if not s then
        error("NoteBasename:init() requires a string")
    end

    local replaces = {
        ["/"] = "-",
        [":"] = "-",
        ["*"] = "-",
        ["?"] = "-",
        ['"'] = "-",
        ["<"] = "-",
        [">"] = "-",
        ["|"] = "-",
        ["\n"] = "",
        ["\r"] = "",
        ["#"] = " ",
    }

    for k, v in pairs(replaces) do
        s = s:gsub(k, v)
    end

    local ext = config.options.ext
    if not s:match(ext .. "$") then
        s = s .. ext
    end

    local this = {}
    setmetatable(this, self)
    this.__index = s
    return this
end

function NoteBasename:__tostring()
    return self.__index
end

--- @class vault.Note.Title
--- @field text string
--- @field __index string
local Title = Object("VaultNoteTitle")

function Title:init(str)
    if not str then
        error("missing argument: str")
    end
    if type(str) ~= "string" then
        error("str must be a string")
    end
    self.text = str
end

function Title:sync(path)
    if path == nil then
        local bufpath = vim.fn.expand("%:p")
        if type(bufpath) ~= "string" then
            return
        end
        path = bufpath
    end

    local Note = require("vault.notes.note")
    local note = Note({ path = path })
    local title = note.data.title
    if title == nil then
        return
    end

    local new_path = vim.fn.fnamemodify(path, ":h") .. "/" .. title .. ".md"
    if vim.fn.filereadable(new_path) == 1 then
        vim.notify("File already exists: " .. new_path, vim.log.levels.ERROR, {
            title = "Knowledge",
            timeout = 200,
        })
        return
    end

    local rename_success = vim.fn.rename(path, new_path)
    if rename_success == 0 then
        vim.notify("Renamed: " .. path .. " -> " .. new_path, vim.log.levels.INFO, {
            title = "Knowledge",
            timeout = 200,
        })

        local inlinks = note.inlinks(path)
        if #inlinks > 0 then
            note.update_inlinks(path)
        end
    else
        vim.notify("Failed to rename: " .. path .. " -> " .. new_path, vim.log.levels.ERROR, {
            title = "Knowledge",
            timeout = 200,
        })
        return
    end

    vim.cmd("e " .. vim.fn.fnameescape(new_path))
end

function Title:__tostring()
    return self.__index
end

function Title:from_string(str)
    if not str then
        error("Vault: Title:from_string() - s is nil.")
    end

    if str:match("^#") then
        str = str:gsub("^#", "")
    end
    str = str:gsub("%s+", " ")
    str = str:gsub("%s+$", "")
    str = str:gsub("^%s+", "")

    self.text = str
end

function Title:to_basename()
    local str = self.__index
    if not str then
        error("Vault: Title:to_basename() - s is nil.")
    end
    return NoteBasename:new(str)
end

function NoteBasename:to_title()
    local s = self.__index
    s = s:gsub(config.options.ext .. "$", "")
    local title = Title:from_string(s)
    return title
end

--- State object for |vault.Note|.
--- @class vault.Note.Data: vault.Object
local NoteData = Object("VaultNoteData")

--- @param this vault.Note.Data
function NoteData:init(this)
    this = this or {}
    for k, v in pairs(this) do
        if not data[k] then
            error(
                "Invalid key: " .. vim.inspect(k) .. ". Valid keys: " .. vim.inspect(metadata.keys)
            )
        end
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

--[[
================================================================================
VaultNote                                                              *vault.Note*
================================================================================

A powerful abstraction for working with markdown notes in your vault.

DESCRIPTION                                                   *vault.Note-description*

VaultNote provides a comprehensive API for managing markdown notes, including
metadata handling, file operations, content manipulation, and preview capabilities.

FEATURES                                                       *vault.Note-features*

  • Full metadata management (frontmatter)
  • File operations (create, move, rename, delete)
  • Content manipulation (search, replace, update)
  • Bidirectional link management
  • Note preview integration
  • Obsidian compatibility

USAGE                                                           *vault.Note-usage*

Basic initialization: >lua
    -- Create from path
    local note = require("vault.notes.note")("/path/to/note.md")

    -- Create from data table
    local note = require("vault.notes.note")({
      path = "/path/to/note.md",
      title = "My Note"
    })
<

Common operations: >lua
    -- Read note content
    print(note.data.content)

    -- Update content
    note:update_content("old text", "new text")

    -- Move/rename note
    note:move("new/path/note.md")

    -- Open in editor
    note:edit()

    -- Preview with Glow
    note:preview()
<

METHODS                                                       *vault.Note-methods*

                                                              *vault.Note.init()*
init({path})
    Initialize a new note from path or data table.
    Parameters: ~
        {path}  string|table Path to note or data table

                                                              *vault.Note.write()*
write({path}, {force})
    Write note content to disk.
    Parameters: ~
        {path}   string  Optional path to write to
        {force}  boolean Force write if file exists

                                                               *vault.Note.edit()*
edit({path})
    Open note in Neovim buffer.
    Parameters: ~
        {path}  string Optional path to edit

                                                            *vault.Note.preview()*
preview()
    Preview note using configured previewer (default: Glow)

                                                               *vault.Note.move()*
move({new_path}, {force}, {verbose})
    Move/rename note and update all references.
    Parameters: ~
        {new_path}  string  New path for the note
        {force}     boolean Force move if target exists
        {verbose}   boolean Show detailed notifications

See also:
    |vault.Filter|       Note filtering and queries
    |vault.Tags|         Tag management
    |vault.metadata|     Note metadata handling

EXAMPLES                                                     *vault.Note-examples*

Create and write a new note: >lua
    local note = require("vault.notes.note")({
      path = "journal/2024-02-12.md",
      title = "Daily Note",
      tags = {"journal", "daily"}
    })
    note:write()
<

Update note content and links: >lua
    -- Replace text
    note:update_content("old link", "new link")

    -- Move note to new location
    note:move("archive/old-note.md")
<

Working with metadata: >lua
    -- Check if note has specific tags
    if note:has("tags", {"important", "todo"}) then
      -- Do something
    end

    -- Access metadata
    print(note.data.title)
    print(note.data.created)
<
]]
--- @class vault.Note: vault.Object
--- @field data vault.Note.Data - The Data of the note.Data.
local Note = Object("VaultNote")

--- Initialize a new Note object.
---
--- This handles converting a path string to a note data table.
--- It also validates the note data and initializes the NoteData object.
---
--- @param this vault.path|vault.Note.Data|vault.EntryInfo|table<{path: vault.path}>|string - The path to the note or the note data.
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
        local paths = scanner().paths()
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

--- Append a line to the note file on disk.
--- Creates the file (with parent dirs) if it doesn't exist yet.
---
--- @param line string  Text to append (written as-is, no prefix added)
function Note:append(line)
    local path = self.data.path
    local parent = vim.fn.fnamemodify(path, ":h")
    if vim.fn.isdirectory(parent) == 0 then
        vim.fn.mkdir(parent, "p")
    end
    local lines = vim.fn.filereadable(path) == 1 and vim.fn.readfile(path) or {}
    table.insert(lines, line)
    vim.fn.writefile(lines, path)
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
    vim.cmd("e " .. vim.fn.fnameescape(path))
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

--- Check if note has values for the specified keys.
---
--- @param keys string|string[] - The key(s) to check
--- @param values string|string[] - The value(s) to match against
--- @param match_opt? "exact"|"fuzzy"|"contains"|"start"|"end" - Match option
--- @return boolean
function Note:has(keys, values, match_opt)
    -- TEST: This function is not tested.
    if not values then
        error("values parameter is required")
    end

    -- Convert single key/value to tables for consistent handling
    keys = type(keys) == "string" and { keys } or keys
    values = type(values) == "string" and { values } or values

    -- Validate inputs
    if type(keys) ~= "table" or type(values) ~= "table" then
        error("keys and values must be strings or arrays")
    end

    match_opt = match_opt or "exact"

    -- Check each key
    for _, key in ipairs(keys) do
        local data_value = self.data[key]
        if not data_value then
            return false
        end

        -- Convert single value to table
        data_value = type(data_value) == "table" and data_value or { data_value }

        -- Look for matches
        for _, value in pairs(data_value) do
            for _, target in ipairs(values) do
                -- Handle both objects with .data.name and direct values
                local compare_value = type(value) == "table" and value.data.name or value
                if utils.match(compare_value, target, match_opt) then
                    return true
                end
            end
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
        utils.safe_write(inlink.source.data.path, content)
        vim.notify(inlink.link .. " -> " .. new_link)
    end
end

--- Open note in the Obsidian app.
--- ```lua
--- require("vault.notes")():get_random():open_in_obsidian()
--- ```
--- @param path? string - Optional path to the note to open (defaults to current note).
function Note:open_in_obsidian(path)
    local root = config.options.root
    if not root then
        error("Vault root is not configured")
    end

    local vault_name = vim.fn.fnamemodify(root, ":t")
    local note_path = path or self.data.path

    -- Ensure we have a relative path from the vault root for Obsidian's 'file' parameter
    local rel_path = utils.path_to_relpath(note_path)

    local obsidian_url = string.format(
        "obsidian://open?vault=%s&file=%s",
        vim.uri_encode(vault_name, "rfc2396"),
        vim.uri_encode(rel_path, "rfc2396")
    )

    local opener = vim.fn.has("mac") == 1 and "open"
        or (vim.fn.has("win32") == 1 and "start" or "xdg-open")

    local success, err = pcall(function()
        vim.fn.system({ opener, obsidian_url })
    end)

    if not success then
        vim.notify("Failed to open Obsidian: " .. tostring(err), vim.log.levels.ERROR)
    end
end

--- Update note content by replacing text.
---
--- Performs search and replace operations on note content.
--- Can target specific line numbers or update all occurrences.
---
--- Parameters: ~
---   • {search_string} Text to find
---   • {replace_string} Replacement text
---   • {lnums} (optional) Specific line numbers to update
---
--- Examples: >lua
---   -- Replace all occurrences
---   note:update_content("old text", "new text")
---
---   -- Replace at specific lines
---   note:update_content("old", "new", {
---     { lnum = 1, col = 1, end_col = 4 },
---     { lnum = 5, col = 2, end_col = 5 }
---   })
--- <
---
--- @param search_string string Text to find
--- @param replace_string string Replacement text
--- @param lnums? vault.source.lnums Line numbers to update
function Note:update_content(search_string, replace_string, lnums)
    if type(search_string) ~= "string" then
        return
    end
    if type(replace_string) ~= "string" then
        return
    end
    local lines = vim.split(self.data.content or "", "\n")
    if next(lines) == nil then
        return
    end

    -- TODO: handle multiple matches in whole file
    if lnums then
        for _, occurence in pairs(lnums) do
            -- support different lnum indexing (0-based or 1-based)
            local lnum = occurence.lnum
            if not lnum then
                goto continue_occ
            end
            if not lines[lnum] and lines[lnum + 1] then
                lnum = lnum + 1
            end
            local line = lines[lnum]
            if not line then
                goto continue_occ
            end

            if utils.match(line, search_string, "contains", false) == true then
                local start_col = occurence.col or occurence.start_col or occurence.start
                local end_col = occurence.end_col or occurence.finish or occurence["end"]

                -- If we don't have precise column info, fall back to replacing all occurrences on the line
                if not start_col or not end_col then
                    local escaped_search_string = vim.pesc(search_string)
                    lines[lnum] = line:gsub(escaped_search_string, replace_string)
                    goto continue_occ
                end

                start_col = tonumber(start_col)
                end_col = tonumber(end_col)
                if not start_col or not end_col then
                    goto continue_occ
                end

                local original_sub = line:sub(start_col, end_col)

                -- try to extract captures from the original substring using the search pattern
                local found_start, found_end, captures = original_sub:find(search_string)

                local replacement_processed = replace_string

                if found_start then
                    -- expand %1..%9 in replacement_processed using captures
                    replacement_processed = replacement_processed:gsub("%%(%d)", function(d)
                        return tostring(captures[tonumber(d)] or "")
                    end)
                end

                local new_line = line:sub(1, start_col - 1)
                    .. replacement_processed
                    .. line:sub(end_col + 1)
                lines[lnum] = new_line
            end

            ::continue_occ::
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
    local new_content = table.concat(lines, "\n")
    self:overwrite(new_content)

    -- refresh buffer if open so changes show up immediately
    if refresh_buffers then
        pcall(refresh_buffers, { self.data.path })
    end

    return self
end

--- Overwrite entire note content.
---
--- Replaces the entire content of the note with new text.
--- Handles file operations safely using libuv.
---
--- Parameters: ~
---   • {content} New content for the note
---
--- Examples: >lua
---   -- Replace note content
---   note:overwrite("# New Title\n\nNew content here")
---
---   -- Clear note content
---   note:overwrite("")
--- <
---
--- Note: This operation cannot be undone!
---
--- @param content string New note content
function Note:overwrite(content)
    utils.safe_write(self.data.path, content)
end

--- Get list of available note methods.
--- @return string[]
function Note:get_methods()
    local methods = {}
    for k, v in pairs(Note) do
        if type(v) == "function" then
            table.insert(methods, k)
        end
    end
    return methods
end


--- Move/rename note to a new path and update all wikilink references.
---
--- This performs the filesystem rename, patches all [[wikilinks]] across the vault
--- that pointed to the old slug, updates the frontmatter if configured, and renames
--- any open Neovim buffers that pointed to the old path.
---
--- @param new_path string New absolute path for the note
--- @param force? boolean Force move even if target exists (default: false)
--- @param verbose? boolean Show detailed notifications (default: true)
--- Move/rename a note to a new path.
--- @param new_path string Absolute path for the new location.
--- @param force? boolean Overwrite target if it exists (default false).
--- @param verbose? boolean Show notification (default true).
--- @param opts? { update_links?: boolean } Extra options.
---   update_links: whether to patch wikilinks across the vault.
---     Defaults to `config.options.watcher.auto_update_links` (true).
function Note:move(new_path, force, verbose, opts)
    local uv = vim.uv or vim.loop
    opts = opts or {}

    if type(new_path) ~= "string" or new_path == "" then
        error("Note:move() requires a non-empty string path, got " .. type(new_path))
    end

    local old_path = self.data.path
    if old_path == new_path then
        return
    end

    -- Check source exists
    if vim.fn.filereadable(old_path) == 0 then
        error("Note:move() source does not exist: " .. old_path)
    end

    -- Check target does not already exist (unless force)
    if not force and vim.fn.filereadable(new_path) == 1 then
        error("Note:move() target already exists: " .. new_path .. " (use force=true to overwrite)")
    end

    -- Ensure target directory exists
    local target_dir = vim.fn.fnamemodify(new_path, ":p:h")
    if vim.fn.isdirectory(target_dir) == 0 then
        vim.fn.mkdir(target_dir, "p")
    end

    -- Perform the filesystem rename
    local ok, err = uv.fs_rename(old_path, new_path)
    if not ok then
        error("Note:move() fs_rename failed: " .. tostring(err))
    end

    -- Determine whether to update wikilinks.
    -- Explicit opts.update_links overrides; otherwise fall back to config.
    local update_links = opts.update_links
    if update_links == nil then
        local watcher_conf = (config.options and config.options.watcher) or {}
        update_links = watcher_conf.auto_update_links
        if update_links == nil then update_links = true end
    end

    local patched = 0
    if update_links then
        local Watcher = require("vault.watcher")
        local watcher = Watcher()
        -- Disable prompts for programmatic moves and skip oil guard
        watcher:disable_oil_guard()
        patched = watcher:handle_rename(old_path, new_path, opts.silent) or 0
    end

    -- Update internal data to reflect the new path
    self.data.path = new_path
    self.data.slug = utils.path_to_slug(new_path)
    self.data.relpath = utils.path_to_relpath(new_path)

    if verbose ~= false then
        local msg = update_links
            and string.format("[vault] Moved note: %s -> %s (%d files patched)",
                utils.path_to_slug(old_path), self.data.slug, patched)
            or string.format("[vault] Moved note: %s -> %s (wikilink update skipped)",
                utils.path_to_slug(old_path), self.data.slug)
        vim.notify(msg, vim.log.levels.INFO)
    end
end

--- Delete a note by moving it to the vault's .trash/ directory (Obsidian-compatible).
--- If `permanent` is true, the file is removed from disk entirely.
--- Closes the buffer if it is currently open.
--- @param permanent? boolean  If true, permanently delete instead of trashing (default: false)
--- @param verbose? boolean    Show notifications (default: true)
function Note:delete(permanent, verbose)
    local uv = vim.uv or vim.loop
    local old_path = self.data.path

    if vim.fn.filereadable(old_path) == 0 then
        error("Note:delete() file does not exist: " .. old_path)
    end

    -- Close any buffer visiting this file
    local bufnr = vim.fn.bufnr(old_path)
    if bufnr ~= -1 then
        pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
    end

    if permanent then
        local ok, err = os.remove(old_path)
        if not ok then
            error("Note:delete() os.remove failed: " .. tostring(err))
        end
    else
        -- Move to .trash/ (Obsidian-compatible soft delete)
        local config = require("vault.config")
        local trash_dir = config.options.root .. "/.trash"
        if vim.fn.isdirectory(trash_dir) == 0 then
            vim.fn.mkdir(trash_dir, "p")
        end
        local basename = vim.fn.fnamemodify(old_path, ":t")
        local trash_path = trash_dir .. "/" .. basename
        -- Handle name collision in trash
        if vim.fn.filereadable(trash_path) == 1 then
            local stem = vim.fn.fnamemodify(basename, ":r")
            local ext = vim.fn.fnamemodify(basename, ":e")
            trash_path = string.format("%s/%s_%s.%s", trash_dir, stem, os.time(), ext)
        end
        local ok, err = uv.fs_rename(old_path, trash_path)
        if not ok then
            error("Note:delete() fs_rename to trash failed: " .. tostring(err))
        end
    end

    if verbose ~= false then
        local action = permanent and "Permanently deleted" or "Trashed"
        vim.notify(
            string.format("[vault] %s: %s", action, self.data.slug),
            vim.log.levels.INFO
        )
    end
end

--- Rename a note by slug or path. Delegates to Note:move().
--- @param new_name string A slug (e.g. "foo/bar") or absolute path.
--- @param force? boolean Overwrite target if exists (default false).
--- @param verbose? boolean Show notification (default true).
function Note:rename(new_name, force, verbose)
    local new_path
    if new_name:sub(1, 1) == "/" then
        -- Already an absolute path
        new_path = new_name
    else
        -- Treat as slug, convert to path
        new_path = utils.slug_to_path(new_name)
    end
    return self:move(new_path, force, verbose)
end

--- @type vault.Note|vault.Note.constructor
local VaultNote = Note
VaultNote.Title = Title
VaultNote.Basename = NoteBasename
VaultNote.metadata = metadata

state.set_global_key("class.vault.Note", VaultNote)
return VaultNote
