local completions = require("vault.commands.completions")

local M = {}

local function dirs_with_all(prefix)
    prefix = prefix or ""
    local dirs = completions.dirs(prefix, "Vault classify " .. prefix, nil) or {}
    table.insert(dirs, 1, "all")
    return vim.tbl_filter(function(item)
        return item:find(prefix, 1, true) == 1
    end, dirs)
end

function M.spec()
    return {
        classify = {
            run = function(args)
                if args[1] == "all" then
                    require("vault.taxonomy").open_classify({
                        dirs = false,
                        filter_desc = "classify:all",
                    })
                    return
                end
                if args[1] and args[1] ~= "" then
                    require("vault.taxonomy").open_classify({
                        dirs = { args[1] },
                        filter_desc = "classify:" .. args[1],
                    })
                    return
                end
                require("vault.taxonomy").open_classify()
            end,
            complete = dirs_with_all,
        },
        taxonomy = {
            run = function()
                local registry = require("vault.commands.registry")
                local children = registry.children_of({ "taxonomy" })
                local names = vim.tbl_keys(children)
                table.sort(names)
                require("vault.log").scope("cmd").info("Subcommands: %s", table.concat(names, ", "))
            end,
            audit = {
                run = function()
                    require("vault.taxonomy").open_audit()
                end,
            },
            preview = {
                run = function()
                    require("vault.taxonomy").preview()
                end,
            },
            apply = {
                run = function()
                    require("vault.taxonomy").apply()
                end,
            },
            ["undo-last"] = {
                run = function()
                    require("vault.taxonomy").undo_last()
                end,
            },
        },
    }
end

return M
