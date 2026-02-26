--- @class vault.TasksData
local data = {}

--- @param tasks vault.Tasks
--- @return vault.Tasks
data.nested = function(tasks)
    for slug, task in pairs(tasks.map) do
        if next(task.data.children) == nil then
            tasks.map[slug] = nil
        end
    end
    return tasks
end

return data
