--- ```lua
--- assert('foo/bar' == vault.Task.data.name)
--- ```

--- Unique identifier string for a task (its raw line text).
--- @alias vault.Task.Data.name string

--- Status character extracted from a task checkbox, e.g. " ", "x", "-".
--- @alias vault.Task.Data.status string

--- Raw task line as it appears in a note, e.g. "- [ ] Do something [due:: 2024-01-01]".
--- @alias vault.Task.Data.line string

--- Parsed structural elements of a task line (metadata key/value pairs).
--- @alias vault.Task.Data.elements table<string, string>

--- @alias vault.Task.Data.uid string - The unique identifier of the task.
--- @alias vault.Task.Data.root string - The root task of the task. e.g., "foo" from "foo/bar".
--- @alias vault.Task.Data.children vault.Task.children - The children of the task

--- Mapping of note slugs to the set of line-number occurrences where an item appears.
--- @alias vault.source.lnums table<vault.lnum, boolean>

--- Mapping of note slugs to their occurrence sets.
--- @alias vault.Sources.map table<vault.slug, vault.source.lnums|boolean>

--- @alias vault.Task.Data.sources vault.Notes.Data.slugs - The notes slugs of notes with the task.
--- @alias vault.Task.Data.count number - The number of notes with the task.

--- Recursive children of a task (nested sub-tasks).
--- @alias vault.Task.children table<string, vault.Task.Data>

--- @class vault.Task.Data
--- @field uid string - The unique identifier of the task.
--- @field root vault.Task.Data.root - The root task of the task. e.g., "foo" from "foo/bar".
--- @field status vault.Task.Data.status - The status of the task.
--- @field line vault.Task.Data.line - The line of the task.
--- @field elements vault.Task.Data.elements - The elements of the task.
--- @field is_nested boolean - Whether the task is nested. e.g., "foo/bar" is nested, "foo" is not.
--- @field children vault.Task.children[]
--- @field sources vault.Sources.map - The notes slugs of notes with the task.
----- @field checklist -- TODO: Guide, checklist hoq to do it.
--- @field count number - The number of notes with the task.

--- @class vault.Task.Data.parser
--- @field sources fun(task_data: vault.Task.Data): vault.Notes.Data.slugs - The notes slugs of notes with the task.
--- @field children fun(task_Data: vault.Task.Data): vault.Task.children - The children of the task.
local data = {}
--
-- data.uid = function(task_data)
--     return task_data.name
-- end
--
-- data.sources = function(task_data)
--     return task_data.sources
-- end
--
-- --- Scann the children of a task.
-- --- @param task_Data vault.Task.Data
-- --- @return vault.Task.children
-- data.children = function(task_data)
--     local task_name = task_data.name
--     if not task_name then
--         error("scann_children(task_name) - task_name is nil", 2)
--     end
--
--     if task_name:find("/") == nil then
--         return {}
--     end
--
--     local task_name_parts = {}
--     for part in task_name:gmatch("[^/]+") do
--         table.insert(task_name_parts, part)
--     end
--
--     local root = task_name_parts[1]
--
--     table.remove(task_name_parts, 1)
--     local depth = #task_name_parts
--
--     local children = {}
--     local current_node = children
--
--     for i, child_name in ipairs(task_name_parts) do
--         local raw = task_name:gsub("/[A-Za-z0-9_-]+$", "")
--         if i == depth then
--             raw = task_name
--         end
--
--         current_node[child_name] = {
--             raw = raw,
--             name = child_name,
--             root_name = root,
--             parent_name = i > 1 and task_name_parts[i - 1] or nil,
--         }
--
--         if i < depth then
--             current_node = current_node[child_name]
--         else
--             current_node[child_name].children = {}
--         end
--     end
--     return children
-- end

return data
