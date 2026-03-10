local Job = require("plenary.job")
--- @type vault.Config|vault.Config.options
local config = require("vault.config")
--- @type vault.Note.constructor|vault.Note
local ok, Note = pcall(require, "vault.notes.note")
if not ok or type(Note) ~= "table" then
    --- @class vault.Tag.Documentation.NoteShim
    --- @field extend fun(self: vault.Tag.Documentation.NoteShim, name: string): vault.Tag.Documentation.NoteShim
    -- Fallback shim: make the Note dependency optional so this module doesn't error
    -- when `vault.notes.note` fails to return a module (some setups may `return true`).
    -- The shim provides a minimal `extend` method so TagDocumentation = Note:extend(...) works.
    require("vault.log").scope("tag").debug("'vault.notes.note' did not return a module; using fallback Note shim")
    --- @type vault.Tag.Documentation.NoteShim
    Note = {
        extend = function(_, _name)
            --- @type vault.Tag.Documentation.NoteShim
            local cls = {}
            cls.__index = cls
            -- keep extend available for further subclassing
            cls.extend = function(_, _subname)
                local sub = {}
                sub.__index = sub
                sub.extend = function(_) return sub end
                return sub
            end
            return cls
        end,
    }
end


--- Tag documentation.
--- A tag documentation is an object that represents a documentation file for a tag.
--- @class vault.Tag.Documentation: vault.Note
--- @field description vault.Note.body
--- @field name vault.Tag.Data.name
--- @field path vault.path
--- @field exists boolean
--- @field content string|function
local TagDocumentation = Note:extend("VaultTagDocumentation")

--- @param name vault.Tag.Data.name
function TagDocumentation:init(name)
    if not name then
        error("Tag documentation name is required")
    end
    self.name = name
    --- @type vault.path
    local docs_dir = config.dir("docs") or (config.options.root .. "/_docs")
    --- @type vault.path
    local doc_path = docs_dir .. "/" .. name .. config.options.ext
    self.description = ""
    self.path = doc_path
    self.exists = vim.fn.filereadable(doc_path) == 1
    -- setmetatable(tag_documentation, self)
    self.__index = self
end

--- @return nil
function TagDocumentation:open()
    if self.exists then
        vim.cmd("edit " .. vim.fn.fnameescape(self.path))
    else
        self:write(self.path)
    end
end

--- @param self vault.Tag.Documentation
--- @param path vault.path
--- @return nil
function TagDocumentation.write(_self, path)
    --- @type vault.path
    local root_dir = config.options.root
    --- @type vault.path
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
    --- @type string
    local title = vim.fn.fnamemodify(path, ":t:r")
    --- @type string
    local content = "# " .. title .. "\n\n"
    content = content .. "class:: #class/Meta/Tag\n"
    --- @type vault.relpath
    local relpath = parent_dir:gsub(root_dir .. "/", "") -- e.g. docs/software/Blender or docs/software
    content = content .. "parent:: [[" .. relpath .. "]]\n"
    vim.api.nvim_buf_set_lines(current_bufnr, 0, -1, false, vim.split(content, "\n"))
    vim.cmd("write")
    vim.cmd("normal! Go")
end

--- Scann content of tag documentation.
--- @return string
function TagDocumentation:content()
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

--- @alias VaultTag.documentation.constructor fun(name: string): vault.Tag.Documentation
--- @type VaultTag.documentation.constructor|vault.Tag.Documentation
local VaultTagDocumentation = TagDocumentation

return VaultTagDocumentation
