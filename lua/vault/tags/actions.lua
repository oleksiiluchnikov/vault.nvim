local M = {}

function M.rename(from_tag_name, to_tag_name)
    if not from_tag_name then error("No from tag name provided") end
    if not to_tag_name then error("No to tag name provided") end
    local tag = require("vault.tags")():filter("name", from_tag_name, "exact"):get_random()
    if not tag then error("Tag not found") end
    tag:rename(to_tag_name)
end

function M.edit_documentation(tag_name)
    if not tag_name then error("No tag name provided") end
    local tag = require("vault.tags")():filter("name", tag_name, "exact"):get_random()
    if not tag then error("Tag not found") end
    if tag.data.documentation then
        tag.data.documentation:open()
    end
end

return M
