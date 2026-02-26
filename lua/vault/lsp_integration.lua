--- LSP-based rename handler
--- Integrates with Neovim's LSP rename functionality
--- @module vault.lsp_integration

local M = {}

--- Setup LSP rename handler
--- Hooks into will_rename and did_rename LSP events
--- @return nil
function M.setup()
    -- Hook into LSP rename events. Use `didRenameFiles` (post-rename) so
    -- other LSP workspace edits have already been applied. Preserve any
    -- existing handler so we don't accidentally drop default behavior from
    -- other plugins / Neovim.
    local prev_handler = vim.lsp.handlers["workspace/didRenameFiles"]

    vim.lsp.handlers["workspace/didRenameFiles"] = function(err, result, ctx)
        -- First, delegate to previous handler to keep default behavior intact.
        if prev_handler then
            -- protect against errors in previous handler
            pcall(function()
                prev_handler(err, result, ctx)
            end)
        end

        if err or not result then
            return
        end

        -- Post-process rename: notify the watcher about completed renames.
        for _, change in ipairs(result.changes or {}) do
            local old_uri = change.oldUri
            local new_uri = change.newUri
            if old_uri and new_uri then
                local old_path = vim.uri_to_fname(old_uri)
                local new_path = vim.uri_to_fname(new_uri)

                -- Trigger vault watcher logic safely inside a scheduled callback.
                local watcher = require("vault.core.state").get_global_key("watcher")
                if watcher then
                    -- Use pcall to ensure any errors here don't crash other handlers
                    pcall(function()
                        vim.schedule(function()
                            pcall(function()
                                watcher:handle_rename(old_path, new_path)
                            end)
                        end)
                    end)
                end
            end
        end
    end
end



return M
