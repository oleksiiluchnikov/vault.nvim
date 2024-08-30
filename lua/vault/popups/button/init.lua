local Object = require("vault.core.object")

--- @class vault.Button: vault.Object
--- @field label string The label of the button.
--- @field lines string[]
--- @field callback function
--- @field pos table<integer, { col_start: integer, col_end: integer }> The row and columns that fill the button. We need this to callback on the <CR>
local Button = Object("Vault.ui.button")
local ns_id = vim.api.nvim_create_namespace("vault_button")

--- @param this table
--- @return vault.Button
function Button:init(this)
    self.label = this.label or "Button"
    self.display = ("[" .. string.sub(self.label, 1, 1) .. "]" .. self.label:sub(2))
    self.lines = this.lines or {}
    self.view = this.view
        or {
            width = 0,
            height = 0,
            padding = {
                left = "",
                right = "",
                top = "",
                bottom = "",
            },
        }
    self.color = this.color or "String"
    self.callback = this.callback
        or function()
            self:blink()
            vim.notify(vim.inspect(self.label))
        end
    self.pos = this.pos or {}
    self.ns_id = ns_id
    return self
end

function Button:highlight(bufnr)
    bufnr = bufnr or vim.api.nvim_get_current_buf()
    vim.api.nvim_set_hl(ns_id, "DialogBorderHighlight", { fg = "#ffffff", bg = "#000000" })
    for i = 1, #self.pos do
        local line = self.pos[i].line
        local col_start = self.pos[i].col_start
        local col_end = self.pos[i].col_end
        vim.api.nvim_buf_add_highlight(
            bufnr,
            ns_id,
            "DialogBorderHighlight",
            line,
            col_start,
            col_end
        )
    end
end

function Button:dehighlight(bufnr)
    bufnr = bufnr or vim.api.nvim_get_current_buf()
    for i = 1, #self.pos do
        local line = self.pos[i].line
        local col_start = self.pos[i].col_start
        local col_end = self.pos[i].col_end
        vim.api.nvim_buf_clear_namespace(bufnr, ns_id, col_start, col_end)
    end
end

--- Add space to the top of the button
--- @param orientation string
--- | '"top"'
--- | '"bottom"'
--- | '"left"'
--- | '"right"'
function Button:add_padding(orientation)
    vim.notify("Not implemented")
    -- self.view = self.view or {}
    -- if orientation == "top" then
    --     table.insert(self.view, 1, self.options.padding.top.char)
end

function Button:blink()
    local bufnr = vim.api.nvim_get_current_buf()
    self:highlight(bufnr)
    vim.defer_fn(function()
        self:dehighlight(bufnr)
    end, 100)
end

function Button:on_click()
    self.callback()
end

function Button:on_hover()
    self:highlight()
    print(self.label)
end

function Button:on_leave()
    self:dehighlight()
end

--- @alias vault.Button.constructor fun(this: table): vault.Button -- [[@as vault.Button.constructor]]
--- @type vault.Button.constructor|VaultButton
local M = Button

return M
