local log = require("vault.log").scope("cmd")

local M = {}

local function get_vault_api()
    local api = require("vault.api")
    if api.open_picker_promote_tag ~= nil and api.open_picker_merge_note ~= nil and api.open_picker_retarget_note ~= nil then
        return api
    end

    package.loaded["vault.api"] = nil
    return require("vault.api")
end

M.get_vault_api = get_vault_api

function M.spec()
    return {
        lines = {
            run = function()
                get_vault_api().open_picker_lines_starting_with_dash()
            end,
        },
        api = {
            run = function(args)
                local func_name = args[1]
                if not func_name then
                    log.info("Usage: :Vault api <function> [args...]")
                    return
                end
                local api_func = get_vault_api()[func_name]
                if not api_func then
                    log.warn("Unknown API function: %s", func_name)
                    return
                end
                api_func(table.unpack(args, 2))
            end,
            complete = function()
                return vim.tbl_keys(get_vault_api())
            end,
        },
    }
end

return M
