local Job = require("plenary.job")
--- @type vault.Config|vault.Config.options
local config = require("vault.config")
--- @type vault.Note.constructor|vault.Note
local Note = require("vault.notes.note")

--- Task documentation.
--- A task documentation is an object that represents a documentation file for a task.
--- @class vault.Task.Documentation: vault.Note
--- @field name string Display name of this documentation item.
--- @field description vault.Note.body Content description of the documentation.
--- @field path vault.path Absolute filesystem path to the documentation file.
--- @field exists boolean Whether the documentation file currently exists on disk.
--- @field content string|function Raw content string or a callable that returns it.
local TaskDocumentation = Note:extend("VaultTaskDocumentation")

--- Initialise a TaskDocumentation for the given task name.
--- @param name string Name of the task (used to derive the doc file path).
--- @return nil
function TaskDocumentation:init(name)
    if not name then
        error("Tag documentation name is required")
    end
    self.name = name
    local docs_dir = config.dir("docs") or (config.options.root .. "/_docs")
    local doc_path = docs_dir .. "/" .. name .. config.options.ext
    self.description = ""
    self.path = doc_path
    self.exists = vim.fn.filereadable(doc_path) == 1
    -- setmetatable(tag_documentation, self)
    self.__index = self
end

--- Open the documentation file in the current Neovim window.
--- Creates the file with boilerplate if it does not yet exist.
--- @return nil
function TaskDocumentation:open()
    if self.exists then
        vim.cmd("edit " .. vim.fn.fnameescape(self.path))
    else
        self:write(self.path)
    end
end

--- Write the documentation file at the given path, creating parent directories
--- as needed and populating an empty buffer with a title and class/parent fields.
--- @param path vault.path Absolute path at which to create the documentation file.
--- @return nil
function TaskDocumentation:write(path) -- luacheck: ignore 212
    local root_dir = config.options.root
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
    --- title should be last part of path without extension
    local title = vim.fn.fnamemodify(path, ":t:r")
    local content = "# " .. title .. "\n\n"
    content = content .. "class:: #class/Meta/Tag\n"
    local relpath = parent_dir:gsub(root_dir .. "/", "") -- e.g. docs/software/Blender or docs/software
    content = content .. "parent:: [[" .. relpath .. "]]\n"
    vim.api.nvim_buf_set_lines(current_bufnr, 0, -1, false, vim.split(content, "\n"))
    vim.cmd("write")
    vim.cmd("normal! Go")
end

--- Read and return the full content of the documentation file.
--- Returns an empty string if the file does not exist.
--- @return string content Raw file content, or `""` when the file is missing.
function TaskDocumentation:content()
    local docs_dir = config.options.dirs.docs
    local path = docs_dir .. "/" .. self.name .. ".md"
    local f = io.open(path, "r")
    if f == nil then
        return ""
    end
    local content = f:read("*all")
    f:close()
    return content
end

--- @alias VaultTask.documentation.constructor fun(name: string): vault.Task.Documentation
--- @type VaultTask.documentation.constructor|vault.Task.Documentation
local VaultTaskDocumentation = TaskDocumentation

return VaultTaskDocumentation
