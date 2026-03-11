local M = {}

function M.spec()
    return {
        tags = {
            rename = {
                run = function(args)
                    if #args < 2 then
                        require("vault.log").scope("cmd").warn("Usage: :Vault tags rename <old> <new>")
                        return
                    end
                    require("vault.tags.actions").rename(args[1], args[2])
                end,
            },
            merge = {
                run = function(args)
                    if #args < 2 then
                        require("vault.log").scope("cmd").warn("Usage: :Vault tags merge <target> <source1> [source2 ...]")
                        return
                    end
                    local target = args[1]
                    for i = 2, #args do
                        require("vault.tags.actions").rename(args[i], target)
                    end
                    require("vault.log").scope("cmd").info("Merged %d tags into '%s'", #args - 1, target)
                end,
            },
            doc = {
                run = function(args)
                    if #args == 0 then
                        require("vault.log").scope("cmd").warn("Usage: :Vault tags doc <tag_name>")
                        return
                    end
                    require("vault.tags.actions").edit_documentation(args[1])
                end,
            },
        },
    }
end

return M
