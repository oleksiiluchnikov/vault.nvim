local MODULE = "telescope._extensions.vault.pickers.inbox"

describe("vault inbox picker", function()
    local originals

    before_each(function()
        originals = {
            module = package.loaded[MODULE],
            config = package.loaded["vault.config"],
            link_index = package.loaded["vault.notes.link_index"],
            notes = package.loaded["vault.notes"],
            notes_picker = package.loaded["telescope._extensions.vault.pickers.notes"],
            isdirectory = vim.fn.isdirectory,
        }
        package.loaded[MODULE] = nil
    end)

    after_each(function()
        package.loaded[MODULE] = originals.module
        package.loaded["vault.config"] = originals.config
        package.loaded["vault.notes.link_index"] = originals.link_index
        package.loaded["vault.notes"] = originals.notes
        package.loaded["telescope._extensions.vault.pickers.notes"] = originals.notes_picker
        vim.fn.isdirectory = originals.isdirectory
    end)

    it("builds inbox notes from scanner paths instead of loading the whole vault", function()
        local captured = nil

        package.loaded["vault.config"] = {
            options = {
                root = "/vault",
                dirs = {
                    inbox = "/vault/Inbox",
                },
            },
        }
        vim.fn.isdirectory = function(path)
            if path == "/vault/Inbox" then
                return 1
            end
            return originals.isdirectory(path)
        end
        package.loaded["vault.notes.link_index"] = {
            paths = function()
                return {
                    ["Inbox/alpha"] = {
                        path = "/vault/Inbox/alpha.md",
                        slug = "Inbox/alpha",
                    },
                    ["Inbox/nested/beta"] = {
                        path = "/vault/Inbox/nested/beta.md",
                        slug = "Inbox/nested/beta",
                    },
                    ["Project/gamma"] = {
                        path = "/vault/Project/gamma.md",
                        slug = "Project/gamma",
                    },
                }
            end,
            wikilinks = function()
                return { sentinel = true }
            end,
        }
        package.loaded["vault.notes"] = setmetatable({
            from_paths = function(paths)
                return {
                    list = function()
                        return vim.tbl_values(paths)
                    end,
                }
            end,
        }, {
            __call = function()
                error("inbox picker should not load the full notes collection")
            end,
        })
        package.loaded["telescope._extensions.vault.pickers.notes"] = function(opts)
            captured = opts
            return { find = function() end }
        end

        local picker = require(MODULE)
        picker({})

        assert.is_not_nil(captured)
        assert.are.same({ sentinel = true }, captured._wikilinks_map)
        assert.are.equal(2, #captured.notes:list())
    end)
end)
