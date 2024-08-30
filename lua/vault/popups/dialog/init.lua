local Object = require("vault.core.object")
local Popup = require("nui.popup")
local event = require("nui.utils.autocmd").event
local Button = require("vault.popups.button.init")
--- --@param border? nui_popup_border_options

--- @class vault.Dialog.options
--- @field border table<string, string> Border characters
--- @field gap table<string, integer> Gap between buttons
--- @field choices table<string, function> Choices and their callbacks
--- @field callback function Callback function for the dialog
--- @field pos table<integer, integer> Position of the button (row and column)
--- @field width number Width of the dialog
--- @field height number Height of the dialog
--- @field centered_line string Centered line in the dialog
--- @field lines string[] Lines of the dialog

--- @return vault.Dialog.options
local function default_options()
    return {
        border = {
            top_left = "╭",
            top_right = "╮",
            vertical = "│",
            horizontal = "─",
            bottom_left = "╰",
            bottom_right = "╯",
            gap = {
                char = " ",
                count = 0,
            },
            padding = {
                top = {
                    char = " ",
                    count = 0,
                },
                bottom = {
                    char = " ",
                    count = 0,
                },
                left = {
                    char = " ",
                    count = 1,
                },
                right = {
                    char = " ",
                    count = 1,
                },
            },
        },
        gap = {
            char = " ",
            count = 0,
        },
        layout = "row",
        choices = {
            {
                "Try",
                function()
                    vim.notify("Button clicked!")
                end,
            },
        },
        callback = nil,
        width = 0,
        height = 0,
    }
end

--- @class vault.Dialog: vault.Object
--- @field view table
--- @field options vault.Dialog.options
--- @field buttons vault.Button[]
local Dialog = Object("VaultDialog")

--- @param choices? table
--- @param opts? vault.Dialog.options - The options for the dialog.
function Dialog:init(choices, opts)
    self.view = {
        padding = {},
    }
    self.options = vim.tbl_deep_extend("force", opts or {}, default_options())
    self.buttons = {}
    self.choices = {}
    if vim.tbl_islist(choices) == false then
        for k, v in pairs(choices) do
            table.insert(self.choices, {
                k,
                v,
            })
        end
    end

    --- @type string
    self.view.gap = string.rep(self.options.border.gap.char, self.options.border.gap.count)
    self.view.padding.left =
        string.rep(self.options.border.padding.left.char, self.options.border.padding.left.count)
    self.view.padding.right =
        string.rep(self.options.border.padding.right.char, self.options.border.padding.right.count)

    --- @param button vault.Button
    --- @param align string
    --- @return vault.Button
    local function add_vertical_padding(button, align)
        local j = 0
        if self.options.border.padding[align].count > 0 then
            while j <= self.options.border.padding[align].count do
                table.insert(
                    button.lines,
                    self.options.border.vertical
                    -- .. string.rep(opts.border.padding.left.char, opts.border.padding.left.count)
                    .. self.view.padding.left
                    .. string.rep(
                        self.options.border.padding[align].char,
                        vim.api.nvim_strwidth(button.label)
                    )
                    .. self.view.padding.right
                    .. self.options.border.vertical
                )
                j = j + 1
            end
        end
        return button
    end

    local prev_width = vim.api.nvim_strwidth(self.options.border.vertical)
    -- choices = vim.tbl_flatten(choices)
    for i, choice in ipairs(self.choices) do
        local button = Button({
            label = choice[1],
            callback = choice[2] or function()
                vim.notify(choice.label .. " clicked")
            end,
        })

        button.view.padding.left = string.rep(
            self.options.border.padding.left.char,
            self.options.border.padding.left.count
        )
        button.view.padding.right = string.rep(
            self.options.border.padding.right.char,
            self.options.border.padding.right.count
        )
        --- put first letter of the choice in the "[""]" to highlight it
        button.view.width = vim.api.nvim_strwidth(button.display)
            + self.options.border.padding.left.count
            + self.options.border.padding.right.count

        if self.options.border.vertical ~= "" then
            button.view.width = button.view.width
                + vim.api.nvim_strwidth(self.options.border.vertical)
                + vim.api.nvim_strwidth(self.options.border.vertical)
        end

        local horizontal_line = string.rep(
            self.options.border.horizontal,
            button.view.width
            - vim.api.nvim_strwidth(self.options.border.horizontal)
            - vim.api.nvim_strwidth(self.options.border.horizontal)
        )

        --- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- -
        table.insert(
            button.lines,
            1,
            self.options.border.top_left .. horizontal_line .. self.options.border.top_right
        )
        --- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- -
        button = add_vertical_padding(button, "top")
        --- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- -
        table.insert(
            button.lines,
            self.options.border.vertical
            .. self.view.padding.left
            .. button.display
            .. self.view.padding.right
            .. self.options.border.vertical
        )
        --- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- -
        button = add_vertical_padding(button, "bottom")
        --- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- ---- -
        table.insert(
            button.lines,
            self.options.border.bottom_left .. horizontal_line .. self.options.border.bottom_right
        )

        button.view.height = #button.lines

        local from = prev_width + vim.api.nvim_strwidth(self.view.gap)
        local to = prev_width + vim.api.nvim_strwidth(self.view.gap) + button.view.width
        for j = 1, button.view.height do
            button.pos[j] = {
                line = j,
                col_start = from,
                col_end = to,
            }
            prev_width = button.pos[j].col_end
        end

        self.buttons[i] = button
    end
    -- P(self.buttons)
    -- error("stop")
    return self
end

--- @param col? integer - The column to get the button from.
function Dialog:get_button(col)
    -- col = col or vim.api.nvim_win_get_cursor(0)[2]
    col = vim.fn.getcurpos()[5] + 1
    for _, button in ipairs(self.buttons) do
        for _, pos in ipairs(button.pos) do
            if col >= pos.col_start and col <= pos.col_end then
                return button
            end
        end
    end

    return nil
end

--- Add a column to the row of lines.
--- @param line string - The row of lines.
--- @param v string - The value to add to the line.
--- @return string - The updated row of buttons.
local function append_column(line, v, width)
    if v == nil then
        return line
    end
    if line == nil then
        line = v
        return line
    end

    return line .. width .. v
end

--- Render the dialog.
--- @param opts? nui_popup_options
function Dialog:render()
    local width = 80

    --- render buttons as a row
    --- @param button vault.Button
    --- @return string[]
    local function render_as_row(button)
        local lines = {}
        while #lines < self.buttons[1].view.height do
            local i = #lines + 1
            --- @type string|nil
            local line
            for j = 1, #self.buttons do
                line = append_column(line, self.buttons[j].lines[i], self.view.gap)
            end
            lines[i] = line
        end
        width = 0
        width = math.max(width, vim.api.nvim_strwidth(lines[2]))
        return lines
    end

    --- Render buttons as a column
    --- @return string[]
    local function render_as_column()
        local lines = {}
        local line = ""
        for _, btn in ipairs(self.buttons) do
            if btn.view.width > width then
                width = btn.view.width - 2
            end
            for i = 1, self.buttons[1].view.height do
                line = btn.lines[i]
                table.insert(lines, line)
            end
        end
        --
        width = 0
        width = vim.api.nvim_strwidth(self.buttons[1].lines[2])

        return lines
    end

    local lines = {}

    if self.options.layout == "column" then
        lines = render_as_column(self.buttons[1])
        for i, l in pairs(lines) do
            lines[i] = l .. string.rep(" ", width - vim.api.nvim_strwidth(l))
        end
    else
        lines = render_as_row(self.buttons[1])
    end

    local popup = Popup({
        enter = true,     -- Enable the default behavior of the cursor, motions, and text objects
        focusable = true, -- Enable the default behavior of the cursor, motions, and text objects
        -- border = {
        --     style = "single",
        --     text = {
        --         top = string.format(" %-" .. width .. "s ", "Save Changes to"),
        --         top_align = "center",
        --     },
        --     highlight = "FloatBorder",
        --     highlight_top = "FloatBorder",
        -- },
        position = "50%",
        size = {
            width = width,
            height = #lines,
        },
        --- Disable the default behavior of the cursor, motions, and text objects
        --- hide the cursor and show the cursor when the popup is closed
        buf_options = {
            swapfile = false,
            bufhidden = "wipe",
        },
        win_options = {
            winhighlight = "Normal:Normal,FloatBorder:FloatBorder,NormalFloat:Normal",
        },
    })

    popup:mount()

    local function close_popup()
        popup:unmount()
    end

    local function hover()
        local button = self:get_button()
        if button and button.callback then
            button:on_hover()
        end
    end

    local function enter()
        local button = self:get_button()
        if button and button.callback then
            button.callback()
        end
    end

    --- @type vim.api.keyset.keymap
    local map_opts = {
        noremap = true,
        silent = true,
    }

    self._mapped_keys = {}
    for _, button in ipairs(self.buttons) do
        local key = string.lower(button.label:sub(1, 1))
        if self._mapped_keys[key] then
            local new_key = string.lower(button.label:sub(2, 2))
            popup:map("n", new_key, function()
                button:on_click()
            end, map_opts)
            button.display = button.display:gsub("%[" .. key .. "%]", "[" .. key .. new_key .. "]")
        else
            popup:map("n", key, function()
                button:on_click()
            end, map_opts)
            self._mapped_keys[key] = true
        end
    end

    popup:map("n", "q", close_popup, map_opts)
    popup:map("n", "<Esc>", close_popup, map_opts)
    popup:map("n", "<CR>", enter, map_opts)
    popup:map("n", "<C-c>", close_popup, map_opts)

    popup:on(event.BufLeave, close_popup)
    popup:on(event.CursorMoved, hover)

    vim.api.nvim_buf_set_lines(popup.bufnr, 0, -1, false, lines)
end

--- @alias vault.Dialog.constructor fun(choices: string[], opts: vault.Dialog.options?): vault.Dialog
--- @type vault.Dialog.constructor|VaultDialog
local M = Dialog

return M
