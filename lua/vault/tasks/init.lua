local state = require("vault.core.state")

local function scanner()
    return require("vault.scanner")
end

local Collection = require("vault.core.collection")

-- Aliases

--- Keyed map of task line text → Task object.
--- @alias vault.Tasks.map table<string, vault.Task>

--- Ordered list of Task objects.
--- @alias vault.Tasks.list table<integer, vault.Task>

--- @alias VaultMap.tasks.sources vault.Sources.map - Map of sources.

--- Tasks collection that has been filtered to only include nested (child) tasks.
--- @alias VaultTasksGroup vault.Tasks

--- VaultTasks class represents a collection of tasks loaded from vault.
--- @class vault.Tasks: vault.Collection
--- @field map vault.Tasks.map Keyed map of all tasks indexed by their line text.
--- @field nested VaultTasksGroup Tasks that have child sub-tasks.
--- @field sources fun(self: vault.Tasks): VaultMap.tasks.sources Return the source-note map for all tasks.
--- @field list fun(self: vault.Tasks): vault.Tasks.list Return the tasks collection as an ordered array.
local Tasks = Collection:extend("VaultTasks")

--- Initialise the VaultTasks object by scanning all tasks from the vault.
--- Populates `self.map` and registers this instance in global plugin state.
--- @return nil
function Tasks:init()
    self.map = scanner().tasks()
    state.set_global_key("tasks", self)
end

--- @alias VaultTasks.constructor fun(filter_opts?: table): vault.Tasks
--- @type VaultTasks.constructor|vault.Tasks
local VaultTasks = Tasks

state.set_global_key("class.vault.Tasks", VaultTasks)
return VaultTasks
