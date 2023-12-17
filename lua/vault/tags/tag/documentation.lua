local Object = require("vault.core.object")
local Job = require("plenary.job")
---@type VaultConfig|VaultConfig.options
local config = require("vault.config")
local state = require("vault.core.state")
---@type VaultNote.constructor|VaultNote
local Note = state.get_global_key("_class.VaultNote") or require("vault.notes.note")

--- Tag documentation.
--- A tag documentation is an object that represents a documentation file for a tag.
---@class VaultTag.documentation: VaultNote
---@field description string
---@field path string
---@field exists boolean
---@field content string|function
local TagDocumentation = Note:extend("VaultTagDocumentation")

---@param name string
function TagDocumentation:init(name)
    local doc_path = config.dirs.docs .. "/" .. name .. config.ext
    self.description = ""
    self.path = doc_path
    self.exists = vim.fn.filereadable(doc_path) == 1
    -- setmetatable(tag_documentation, self)
    self.__index = self
end

function TagDocumentation:open()
    if self.exists then
        vim.cmd("edit " .. self.path)
    else
        self:write(self.path)
    end
end

function TagDocumentation:write(path)
    local root_dir = config.root
    local parent_dir = vim.fn.fnamemodify(path, ":h")
    if not parent_dir then
        error("Invalid path: " .. path)
    end
    Job:new({
        command = "mkdir",
        args = { "-p", parent_dir },
    }):sync()
    vim.cmd("edit " .. vim.fn.fnameescape(path))
    local current_bufnr = vim.api.nvim_get_current_buf()
    local is_empty = vim.api.nvim_buf_get_lines(current_bufnr, 0, -1, false)[1] == ""
    if not is_empty then
        return
    end
    ---title should be last part of path without extension
    local title = vim.fn.fnamemodify(path, ":t:r")
    local content = "# " .. title .. "\n\n"
    content = content .. "class:: #class/Meta/Tag\n"
    local relpath = parent_dir:gsub(root_dir .. "/", "") -- e.g. docs/software/Blender or docs/software
    content = content .. "parent:: [[" .. relpath .. "]]\n"
    vim.api.nvim_buf_set_lines(current_bufnr, 0, -1, false, vim.split(content, "\n"))
    vim.cmd("write")
    vim.cmd("normal! Go")
end

--- Fetch content of tag documentation.
---@param name string
---@return string
function TagDocumentation:content(name)
    local docs_dir = config.dirs.docs
    local path = docs_dir .. "/" .. name .. ".md"
    local f = io.open(path, "r")
    if f == nil then
        return ""
    end
    local content = f:read("*all")
    f:close()
    return content
end

---@alias VaultTag.documentation.constructor fun(name: string): VaultTag.documentation
---@type VaultTag.documentation.constructor|VaultTag.documentation
local VaultTagDocumentation = TagDocumentation

return VaultTagDocumentation
