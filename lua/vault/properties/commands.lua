local M = {}

function M.spec()
    return {
        properties = {
            run = function(args)
                local pickers = require("telescope._extensions.vault.pickers")
                if #args == 0 then
                    local picker = pickers.properties()
                    if picker then picker:find() end
                elseif #args == 1 then
                    require("vault.properties.actions").open_picker_values(args[1])
                else
                    require("vault.properties.actions").open_picker_notes_with_value(args[1], args[2])
                end
            end,
        },
    }
end

return M
