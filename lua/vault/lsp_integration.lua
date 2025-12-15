--- LSP-based rename handler
--- Integrates with Neovim's LSP rename functionality
--- @module vault.lsp_integration

local M = {}

--- Setup LSP rename handler
--- Hooks into will_rename and did_rename LSP events
--- @return nil
function M.setup()
    -- Hook into LSP rename events
    vim.lsp.handlers["workspace/willRenameFiles"] = function(err, result, ctx)
        if err then
            return
        end

        -- Pre-process rename
        for _, change in ipairs(result.changes or {}) do
            local old_uri = change.oldUri
            local new_uri = change.newUri

            local old_path = vim.uri_to_fname(old_uri)
            local new_path = vim.uri_to_fname(new_uri)

            -- Trigger vault watcher logic
            local watcher = require("vault.core.state").get_global_key("watcher")
            if watcher then
                vim.schedule(function()
                    watcher:handle_rename(old_path, new_path)
                end)
            end
        end
    end
end

return M
