local state = require("vault.core.state")

local function scanner()
    return require("vault.scanner")
end

local Collection = require("vault.core.collection")

-- Aliases
--- @alias vault.Tasks.map table<string, vault.Task> - Map of tasks.
--- @alias vault.Tasks.list table<integer, vault.Task> - Map of tasks.

--- @alias VaultMap.tasks.sources vault.Sources.map - Map of sources.

--- @alias VaultTasksGroup vault.Tasks - Tasks that have children.

--- VaultTasks class represents a collection of tasks loaded from vault.
--- @class vault.Tasks: vault.Object - Retrieve tasks from vault.
--- @field map vault.Tasks.map - Map of tasks.
--- @field nested VaultTasksGroup -- Tasks that have children.
--- @field sources fun(self: vault.Tasks): VaultMap.tasks.sources - Get all sources from tasks.
--- @field list fun(self: vault.Tasks): vault.Tasks.list - Return `VaultTasks` as a `VaultArray`.
local Tasks = Collection:extend("VaultTasks")

--- Initializes the VaultTasks object by scanning all tasks from the vault.
--- Sets the tasks map and registers the tasks globally.
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
