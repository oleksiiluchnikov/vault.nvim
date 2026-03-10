local Object = require("vault.core.object")
local error_formatter = require("vault.utils.error")
local utils = require("vault.utils")
local state = require("vault.core.state")
local log = require("vault.log").scope("task")

-- local config = require("vault.config")
-- local data = require("vault.tasks.task.data")

--- Metadata fields that can be embedded in a task line using the `[field:: value]` syntax.
--- @alias vault.Task.MetadataField "id"|"created"|"due"|"start"|"schedule"|"completed"|"priority"|"repeat"

--- @class vault.Task.Data: vault.Object
--- @field line string Raw task line as it appears in a note.
--- @field tags string[]|fun(): string[] Tags extracted from the task line (e.g. `#tag`).
--- @field sources vault.Sources.map Map of note slugs to their occurrence sets.
--- @field is_nested boolean Whether this task is a sub-task of another.
--- @field wikilinks string[] Wikilink targets referenced in the task line.
--- @field status string Status character from the checkbox, e.g. `" "`, `"x"`, `"-"`.
--- @field content string Task description with status marker and metadata stripped.
--- @field count integer Number of distinct notes that contain this task.
--- @field occurences integer Total number of line-level occurrences across all notes.
--- @field id string Task plugin identifier (empty string when absent).
--- @field created string Creation date metadata field value (empty string when absent).
--- @field due string Due date metadata field value (empty string when absent).
--- @field start string Start date metadata field value (empty string when absent).
--- @field schedule string Schedule metadata field value (empty string when absent).
--- @field completed string Completion date metadata field value (empty string when absent).
--- @field priority string|number Priority metadata field value (empty string when absent).
--- @field repeat string Recurrence rule metadata field value (empty string when absent).
local TaskData = Object("VaultTaskData")

--- @alias vault.Task.Data.partial { line?: string, tags?: string[]|fun(): string[], sources?: table<string, table|boolean>, is_nested?: boolean, wikilinks?: string[], id?: string, created?: string, due?: string, start?: string, schedule?: string, completed?: string, priority?: string|number, repeat?: string }

--- @param this vault.Task.Data.partial
function TaskData:init(this)
    if not this then
        error(error_formatter.MISSING_PARAMETER("this"), 2)
    end

    self.line = this.line or ""
    self.tags = this.tags or (self.line ~= "" and self.line:gmatch("%s*#(.-)%s*")) or {}
    self.sources = this.sources or {}
    self.is_nested = self.is_nested or false
    self.wikilinks = self.wikilinks or {}
    --- TODO: Implement subtasks

    -- Extract status and description
    self.status = (self.line ~= "" and self.line:match("- %[(.)%]")) or " "

    -- Parse wikilinks
    if type(self.line) == "string" and self.line ~= "" then
        for wikilink in self.line:gmatch("%[%[(.-)%]%]") do
            table.insert(self.wikilinks, wikilink)
        end
    end


    -- Parse metadata fields
    --- @type vault.Task.MetadataField[]
    local metadata_fields = {
        "id",
        "created",
        "due",
        "start",
        "schedule",
        "completed",
        "priority",
        "repeat",
    }

    for _, field in ipairs(metadata_fields) do
        self[field] = this[field]
            or (self.line ~= "" and self.line:match("%[" .. field .. "::%s*(.-)%s*%]"))
            or ""
    end

    -- self.description = this.line:gsub("^%s*-%s*%[.%]%s*", ""):match("^(.-)%s*%[%a+::") or this.line
    -- description is the line without the status, tags, and metadata
    -- self.description = this.line:gsub("^%s*-%s*%[.%]%s*", ""):match("^(.-)%s*%[%a+::") or this.line
    if type(this.line) == "string" and this.line ~= "" then
        local stripped = this.line:gsub("- %[%.-%]", "")
        local content = stripped:match("^(.-)%[%a+::") or stripped
        self.content = content:gsub("\n", "")
    else
        self.content = ""
    end


    -- Calculate source statistics
    self.count = 0
    self.occurences = 0
    for _, occurences in pairs(self.sources) do
        self.count = self.count + 1
        if type(occurences) == "table" then
            for _ in pairs(occurences) do
                self.occurences = self.occurences + 1
            end
        end
    end
end


--- @class vault.Task: vault.Object
--- @field data vault.Task.Data - The Data of the task.
--- @field init fun(self: vault.Task, this: vault.Task.Data.name|vault.Task.Data.partial): vault.Task
--- @field add_slug fun(self: vault.Task, slug: string): vault.Task - Add a slug to the `self.Data.sources` table.
--- @field rename fun(self: vault.Task, name: vault.Task.Data.name, verbose?: boolean): vault.Task
local Task = Object("VaultTask")

--- Create a new |vault.Task| instance.
--- @param this vault.Task.Data.name|vault.Task.Data.partial
function Task:init(this)
    if not this then
        error(error_formatter.MISSING_PARAMETER("this"), 2)
    end
    if type(this) == "string" then
        this = { line = this }
    end

    if not this.line then
        error(error_formatter.MISSING_PARAMETER("name"), 2)
    end

    self.data = TaskData(this)
end

--- Rename the task. and update all occurences of the task in the notes.
--- @param name vault.Task.Data.name
--- @param verbose? boolean
--- @return vault.Task
function Task:rename(name, verbose)
    if name == nil or name == "" then
        error("Invalid name: " .. vim.inspect(name))
    end
    if name == self.data.line then
        return self
    end
    verbose = verbose or true
    --- @type vault.Note.constructor
    local Note = state.get_global_key("class.vault.Note") or require("vault.notes.note")

    --- @type table<vault.path, vault.source.lnums> - A table of paths to update.
    local paths_to_update = {} ---@type table<string, vault.source.lnums>
    for slug, lnums in pairs(self.data.sources) do
        local path = utils.slug_to_path(slug)
        paths_to_update[path] = lnums
    end

    local old_name = self.data.line ---@type string
    local new_name = name ---@type string

    local message = "" ---@type string
    if verbose == true then
        message = self.data.line .. " -> " .. name
    end

    -- Update connected notes
    for path, lnums in pairs(paths_to_update) do
        --- @type vault.Note
        local note = Note(path)
        note:update_content(old_name, new_name, lnums)

        if verbose == true then
            message = message
                .. "\n"
                .. self.data.line
                .. " -> "
                .. name
                .. " in "
                .. note.data.slug
        end
    end
    self.data.line = name
    if verbose == false then
        return self
    end

    log.info(message)
    -- require("vault.tasks").reset()
    return self
end

--- Add a slug to the |vault.Task.Data.sources|
---
--- @param slug vault.slug
--- @return vault.Task
function Task:add_slug(slug)
    if not self.data.sources then
        self.data.sources = {}
    end
    if not self.data.sources[slug] then
        -- Initialize an empty table of occurrences for this slug.
        self.data.sources[slug] = {}
        self.data.count = (self.data.count or 0) + 1
    end
    return self
end


--- @alias vault.Task.constructor fun(this: vault.Task|table|string): vault.Task
--- @type vault.Task.constructor|vault.Task
local VaultTask = Task

state.set_global_key("class.vault.Task", VaultTask)
return VaultTask
