local actions_state = require("telescope.actions.state")
local actions = require("telescope.actions")
local vault_state = require("vault.core.state")
local highlights = require("vault.highlights")

local Popup = require("nui.popup")
local event = require("nui.utils.autocmd").event

--- @class vault.Picker.actions.note

--- @class vault.Picker.actions
--- @field get_picker_selection fun(prompt_bufnr: integer): Picker, vault.TelescopeEntry, vault.TelescopeEntry[]
local vault_actions = {}

--- @param prompt_bufnr integer
--- @return Picker
--- @return vault.TelescopeEntry
--- @return vault.TelescopeEntry[]
local function get_picker_selection(prompt_bufnr)
    --- @type Picker
    local current_picker = vault_state.get_global_key("picker")
        or actions_state.get_current_picker(prompt_bufnr)
    --- @type vault.TelescopeEntry
    local selection = actions_state.get_selected_entry()
    --- @type vault.TelescopeEntry[]
    local selections = current_picker:get_multi_selection()
    if next(selections) == nil then
        selections = { selection }
    end
    return current_picker, selection, selections
end

function vault_actions.refresh()
    local current_picker = vault_state.get_global_key("picker")
    current_picker:refresh()
end

function vault_actions.resort()
    local current_picker = vault_state.get_global_key("picker")
    P(current_picker)
end

--- Close the picker
--- @param bufnr integer
function vault_actions.close(bufnr)
    actions.close(bufnr)
    highlights.detach()
    vault_actions.refresh()
end

vault_actions.note = {}

--- Edit the selected note
--- @param bufnr integer
function vault_actions.note.edit(bufnr)
    local _, selection, _ = get_picker_selection(bufnr)
    --- @type vault.Note
    local note = selection.value
    vault_actions.close(bufnr)
    note:edit()
end

--- Preview note with config.options.popups.preview
--- @param bufnr integer
function vault_actions.note.preview(bufnr)
    local _, selection, _ = get_picker_selection(bufnr)
    local note = selection.value
    vault_actions.close(bufnr)
    note:preview()
end

--- Rename notes
--- @param selections vault.TelescopeEntry[]
--- @param lines string[]
local function rename_notes(selections, lines)
    for i, slug in ipairs(lines) do
        --- @type vault.Note
        local note = selections[i].value
        note:rename(slug)
    end
end

-- Rename tags
--- @param selections table<vault.TelescopeEntry>
--- @param lines string[]
local function rename_tags(selections, lines)
    for i, name in ipairs(lines) do
        --- @type vault.Tag
        local tag = selections[i].value
        tag:rename(name)
    end
end

--- Provides functionality for batch renaming of Vault notes or tags
--- @param selections table<vault.TelescopeEntry> A table of selected entries from Telescope
--- @type fun(bufnr: number, selections: table<vault.TelescopeEntry>): nil
local batch_rename = function(_, selections)
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

    local height = math.min(vim.api.nvim_list_uis()[1].height - 2, math.max(1, #strings_to_rename))
    local position = math.floor((vim.api.nvim_list_uis()[1].height - height) / 2)

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
            filetype = "markdown",
            modeline = true,
        },
        win_options = {
            winhighlight = "Normal:Normal,FloatBorder:FloatBorder",
            number = true,
        },
    }
    local popup = Popup(win_config)
    popup:mount()
    local filename = "vault://rename"
    vim.api.nvim_buf_set_name(popup.bufnr, filename)
    vim.api.nvim_buf_set_lines(popup.bufnr, 0, 1, false, strings_to_rename)

    local function on_enter()
        local lines = vim.api.nvim_buf_get_lines(popup.bufnr, 0, -1, false)
        if next(lines) == nil then
            error("No lines to rename")
            return
        end
        assert(#lines == #strings_to_rename, "Keep a line unchanged if you do not want to rename")
        local class_name = selections[1].value.class.name
        if not class_name then
            error("Invalid object name: " .. vim.inspect(selections[1].value))
        end
        if class_name == "VaultNote" then
            rename_notes(selections, lines)
        elseif class_name == "VaultTag" then
            rename_tags(selections, lines)
        end
    end

    --- @type vim.api.keyset.cmd_opts
    -- local opts = { noremap = true, silent = true }
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
        vault_actions.refresh()
    end)
end

--- Rename notes
--- @param bufnr integer
function vault_actions.note.rename(bufnr)
    local picker, _, selections = get_picker_selection(bufnr)
    batch_rename(bufnr, selections)
end

--[[ --- Delete notes
--- TODO: Implement this
--- @param bufnr integer
function vault_actions.note.delete(bufnr)
    local _, _, selections = get_picker_selection(bufnr)
    --- @type vault.Note
    local note = selection.value
    actions.close(bufnr)
    vim.notify("vault_actions.note.delete is not implemented yet")
    -- note:delete()
end ]]

vault_actions.tag = {}

-- --- @param vault.FilterOpts
-- function vault_actions.filter_notes(opts)
--     local selection = actions_state.get_selected_entry()
--     --- @type vault.Tag
--     local tag = selection.value
--     vault_actions.close(bufnr)
--     vault_pickers.notes(
--         nil,
--         require("vault.notes")():filter({
--             search_term = "tags",
--             include = { tag.data.name },
--             exclude = {},
--             match_opt = "exact",
--             mode = "all",
--             case_sensitive = false,
--         })
--     )
-- end

--- Merge selected tags in to one tag
--- @param selections table
--- @param new_name string
local function merge(_, selections, new_name)
    --- @type vault.Tag[]
    local tags_to_merge = {}
    for _, selection in ipairs(selections) do
        local tag = selection.value
        tags_to_merge[tag.data.name] = tag
    end

    for _, tag in pairs(tags_to_merge) do
        tag:rename(new_name)
    end
    vault_state.get_global_key("picker"):find()
end

--- Merge selected tags in to one tag
--- @param bufnr integer
function vault_actions.tag.merge(bufnr)
    local _, _, selections = get_picker_selection(bufnr)
    if next(selections) == nil then
        return
    end
    --- @type vault.Tag
    local tag = selections[1].value
    --- @type vault.Tag.data.name
    local new_tag_name = vim.fn.input("Merge to: ", tag.data.name)
    merge(bufnr, selections, new_tag_name)
end

--- Rename tags
--- @param bufnr integer
function vault_actions.tag.rename(bufnr)
    local _, _, selections = get_picker_selection(bufnr)
    batch_rename(bufnr, selections)
end

--- Edit tag documentation
--- @param bufnr integer
function vault_actions.tag.edit_documentation(bufnr)
    local _, selection, _ = get_picker_selection(bufnr)
    vault_actions.close(bufnr)
    local tag = selection.value
    require("vault.api").edit_tag_documentation(tag.data.name)
end

--- Open Telescope picker for notes with a specific tag
--- @param bufnr integer
function vault_actions.tag.enter(bufnr)
    local _, selection, _ = get_picker_selection(bufnr)
    vault_actions.close(bufnr)
    --- @type vault.Tag
    local tag = selection.value
    require("vault.api").open_picker_notes_with_tag(tag.data.name)
end

--[[
-- TODO: Idea is to ivert telescope picker like following logic:
--  I we have picker that recent filtor was with notes with tag "foo" and we want to invert it to achive notes without tag "foo"
--  we can do it by creating new picker with same filter but with inverted logic
--  We have stored last filter inited in the global state of vault
--  So we can use it to create new picker with inverted logic
vault_actions.invert = function()
    local picker, selection, selections = get_picker_selection(bufnr)
    --- @type vault.Filter
    local filter = vault_state.get_global_key("filter")
    if not filter then
        Log.warn("No recent filter found")
        return
    end
    local notes = require("vault.notes")():filter(filter:invert())
    require("vault.pickers").notes(nil, notes)
end ]]

return vault_actions
