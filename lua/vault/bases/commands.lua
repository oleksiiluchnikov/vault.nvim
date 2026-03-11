local M = {}

function M.spec()
    return {
        bases = {
            run = function(args)
                if #args == 0 then
                    local pickers = require("telescope._extensions.vault.pickers")
                    local picker = pickers.bases()
                    if picker then picker:find() end
                else
                    require("vault.bases.actions").open_picker_base_notes(table.concat(args, " "))
                end
            end,
            complete = function()
                local ok, bases = pcall(function()
                    return require("vault.bases")()
                end)
                return (ok and bases) and bases:names() or {}
            end,
        },
    }
end

return M
