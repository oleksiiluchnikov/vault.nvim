local M = {}

function M.spec()
    return {
        tasks = {
            run = function()
                require("vault.commands")._callbacks.tasks_list()
            end,
            complete = function(prefix)
                local subs = {
                    "new",
                    "status",
                    "pick-next",
                    "promote",
                    "list",
                    "kanban",
                    "backlog",
                    "doctor",
                    "recur",
                }
                return vim.tbl_filter(function(s)
                    return s:find(prefix, 1, true) == 1
                end, subs)
            end,
            new = {
                run = function(args)
                    require("vault.commands")._callbacks.tasks_new(args)
                end,
            },
            status = {
                run = function(args)
                    require("vault.commands")._callbacks.tasks_status(args)
                end,
                complete = function(prefix)
                    local notes = require("vault.tasks.notes")
                    local path = notes.current_task_path()
                    local candidates = notes.statuses()
                    if path then
                        local task = notes.read_task(path)
                        if task then
                            candidates = notes.next_statuses(task.status)
                        else
                            candidates = {}
                        end
                    end
                    return vim.tbl_filter(function(s)
                        return s:find(prefix, 1, true) == 1
                    end, candidates)
                end,
            },
            ["pick-next"] = {
                run = function()
                    require("vault.commands")._callbacks.tasks_pick_next()
                end,
            },
            promote = {
                run = function(args)
                    require("vault.commands")._callbacks.tasks_promote(args)
                end,
            },
            list = {
                run = function()
                    require("vault.commands")._callbacks.tasks_list()
                end,
            },
            kanban = {
                run = function()
                    require("vault.commands")._callbacks.tasks_kanban()
                end,
            },
            backlog = {
                run = function()
                    require("vault.commands")._callbacks.tasks_backlog()
                end,
            },
            doctor = {
                run = function(args)
                    require("vault.commands")._callbacks.tasks_doctor(args)
                end,
            },
            recur = {
                run = function()
                    require("vault.commands")._callbacks.tasks_recur_preview()
                end,
                complete = function(prefix)
                    local subs = { "preview", "now", "sweep" }
                    return vim.tbl_filter(function(s)
                        return s:find(prefix, 1, true) == 1
                    end, subs)
                end,
                preview = {
                    run = function()
                        require("vault.commands")._callbacks.tasks_recur_preview()
                    end,
                },
                now = {
                    run = function()
                        require("vault.commands")._callbacks.tasks_recur_now()
                    end,
                },
                sweep = {
                    run = function()
                        require("vault.commands")._callbacks.tasks_recur_sweep()
                    end,
                },
            },
        },
    }
end

return M
