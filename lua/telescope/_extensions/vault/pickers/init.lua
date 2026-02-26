-- TODO: Add support for custom pickers from config
return setmetatable(
    vim.tbl_deep_extend("force", require("vault.config").options.telescope.pickers or {}, {
        orphans = require("telescope._extensions.vault.pickers.orphans"),
        leaves = function(opts)
            return require("telescope._extensions.vault.pickers.notes")(
                vim.tbl_deep_extend("force", opts or {}, {
                    notes = require("vault.notes")():leaves(),
                })
            )
        end,
        internals = function(opts)
            return require("telescope._extensions.vault.pickers.notes")(
                vim.tbl_deep_extend("force", opts or {}, {
                    notes = require("vault.notes")():internals(),
                })
            )
        end,
        with_outlinks_resolved_only = function(opts)
            return require("telescope._extensions.vault.pickers.notes")(
                vim.tbl_deep_extend("force", opts or {}, {
                    notes = require("vault.notes")():with_outlinks_resolved_only(),
                })
            )
        end,
        with_outlinks_unresolved = function(opts)
            return require("telescope._extensions.vault.pickers.notes")(
                vim.tbl_deep_extend("force", opts or {}, {
                    notes = require("vault.notes")():with_outlinks_unresolved(),
                })
            )
        end,
    }),
    {
        __index = function(_, key)
            return function(opts)
                local ok, picker =
                    pcall(require, string.format("telescope._extensions.vault.pickers.%s", key))
                if not ok then
                    -- Fallback to vault picker if module not found
                    local vault_picker = require("telescope._extensions.vault.pickers.vault")
                    if vault_picker == nil then
                        error("Failed to load default vault picker")
                        return
                    end
                    return vault_picker(opts):find()
                end
                return picker(opts)
            end
        end,
    }
)
