local actions = require("telescope.actions")
local vault_state = require("vault.core.state")
local highlights = require("vault.highlights")
local layouts = require("telescope._extensions.vault.layouts")
local log = require("vault.log").scope("telescope")

local Popup = require("nui.popup")
local event = require("nui.utils.autocmd").event

--- Safely call :find() on a picker, logging a message if the picker is nil.
---@param picker table|nil
---@param empty_msg string|nil
local function safe_find(picker, empty_msg)
    if picker then
        picker:find()
    else
        log.info(empty_msg or "No results found")
    end
end

--- Refresh the picker.
local function refresh()
    local current_picker = vault_state.get_global_key("picker")
    current_picker:refresh()
end

--- Resort the picker.
local function resort()
    local current_picker = vault_state.get_global_key("picker")
    current_picker:resort()
end

--- Close the picker.
---@param bufnr? number
local function close(bufnr)
    actions.close(bufnr)
    highlights.detach()
    refresh()
end

--- Rename notes.
---@param selections vault.TelescopeEntry[]
---@param lines string[]
local function rename_notes(selections, lines)
    for i, slug in ipairs(lines) do
        --- @type vault.Note
        local note = selections[i].value
        note:rename(slug)
    end
end

--- Rename tags.
---@param selections table<vault.TelescopeEntry>
---@param lines string[]
local function rename_tags(selections, lines)
    for i, name in ipairs(lines) do
        --- @type vault.Tag
        local tag = selections[i].value
        tag:rename(name)
    end
end

--- Rename properties.
---@param selections vault.TelescopeEntry[]
---@param lines string[]
local function rename_properties(selections, lines)
    for i, name in ipairs(lines) do
        --- @type vault.Property
        local property = selections[i].value
        property:rename(name)
    end
end

--- Provides functionality for batch renaming of Vault notes, tags, or properties.
---@param _ number|nil
---@param selections table<vault.TelescopeEntry>
local function batch_rename(_, selections)
    --- @type string[]
    local strings_to_rename = {}
    --- @type string
    local line = ""
    for _, sel in ipairs(selections) do
        --- @type vault.Object
        local obj = sel.value
        if obj.class.name == "VaultNote" then
            --- @cast obj vault.Note
            local note = obj
            line = note.data.slug
        elseif obj.class.name == "VaultTag" then
            --- @cast obj vault.Tag
            local tag = obj
            line = tag.data.name
        elseif obj.class.name == "VaultProperty" then
            --- @cast obj vault.Property
            local property = obj
            line = property.data.name
        end
        table.insert(strings_to_rename, line)
    end

    local ui_height, _ = layouts.ui_size()
    local height = math.min(ui_height - 2, math.max(1, #strings_to_rename))
    local position = math.floor((ui_height - height) / 2)

    --- @type nui_popup_options
    local win_config = {
        enter = true,
        focusable = true,
        relative = "editor",
        border = {
            style = "double",
        },
        position = position,
        size = {
            width = 100,
            height = height,
        },
        buf_options = {
            filetype = "text",
            modeline = true,
        },
        win_options = {
            winhighlight = "Normal:Normal,FloatBorder:FloatBorder",
            number = true,
        },
    }
    local popup = Popup(win_config)
    popup:mount()
    local filename = "Batch rename "
        .. string.lower(selections[1].value.class.name:gsub("^Vault", ""))
        .. "s across Vault"
    vim.api.nvim_buf_set_name(popup.bufnr, filename)
    vim.api.nvim_buf_set_lines(popup.bufnr, 0, 1, false, strings_to_rename)

    local function on_enter()
        local lines = vim.api.nvim_buf_get_lines(popup.bufnr, 0, -1, false)
        if next(lines) == nil then
            log.warn("Nothing to rename - buffer is empty")
            return
        end
        if #lines ~= #strings_to_rename then
            log.warn("Line count changed - keep lines unchanged if you don't want to rename them")
            return
        end
        local class_name = selections[1].value.class and selections[1].value.class.name
        if not class_name then
            log.error("Cannot determine type of selected items")
            return
        end
        if class_name == "VaultNote" then
            rename_notes(selections, lines)
        elseif class_name == "VaultTag" then
            rename_tags(selections, lines)
        elseif class_name == "VaultProperty" then
            rename_properties(selections, lines)
        end
    end

    local opts = { silent = true }
    popup:map("i", "<C-c>", function()
        popup:unmount()
    end, opts)
    popup:map("n", "<C-c>", function()
        popup:unmount()
    end, opts)
    popup:map("n", "<CR>", function()
        on_enter()
        popup:unmount()
    end, opts)
    popup:on(event.BufLeave, function()
        popup:unmount()
        refresh()
    end)
end

return {
    refresh = refresh,
    resort = resort,
    close = close,
    batch_rename = batch_rename,
    safe_find = safe_find,
}
