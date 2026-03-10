local actions = require("telescope.actions")
local vault_state = require("vault.core.state")
local highlights = require("vault.highlights")
local utils = require("telescope._extensions.vault.utils")
local log = require("vault.log").scope("telescope")

local Popup = require("nui.popup")
local event = require("nui.utils.autocmd").event

local function get_vault_api()
    local api = require("vault.api")
    if
        api.open_picker_promote_tag ~= nil
        and api.open_picker_merge_note ~= nil
        and api.open_picker_retarget_note ~= nil
    then
        return api
    end

    package.loaded["vault.api"] = nil
    api = require("vault.api")
    return api
end

--- @class vault.Picker.actions.note

--- @alias vault.Picker.action fun(bufnr?: number, selections?: table<vault.TelescopeEntry>): nil

--- @alias vault.Picker.actions vault.Picker.action|table<string, vault.Picker.action>

--- @type table<string, vault.Picker.actions>
local vault_actions = {}

--- Refresh the picker
function vault_actions.refresh()
    local current_picker = vault_state.get_global_key("picker")
    current_picker:refresh()
end

--- Resort the picker
function vault_actions.resort()
    local current_picker = vault_state.get_global_key("picker")
    current_picker:resort()
end

--- Close the picker
function vault_actions.close(bufnr)
    actions.close(bufnr)
    highlights.detach()
    vault_actions.refresh(bufnr)
end

--- @type table<string, fun(bufnr?: number, selections?: table<vault.TelescopeEntry>): nil>
vault_actions.note = {}

--- Edit the selected note
function vault_actions.note.edit(bufnr)
    local _, selection, _ = utils.get_picker_selection(bufnr)
    --- @type vault.Note
    local note = selection.value
    vault_actions.close(bufnr)
    note:edit()
end

--- Preview note with config.options.popups.preview
function vault_actions.note.preview(bufnr)
    local _, selection, _ = utils.get_picker_selection(bufnr)
    local note = selection.value
    vault_actions.close(bufnr)
    note:preview()
end

--- Merge selected note into another canonical target chosen from notes/wikilinks.
function vault_actions.note.merge(bufnr)
    local _, selection, _ = utils.get_picker_selection(bufnr)
    local note = selection.value
    vault_actions.close(bufnr)
    get_vault_api().open_picker_merge_note(note.data.path, {})
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

local function rename_properties(selections, lines)
    for i, name in ipairs(lines) do
        --- @type vault.Property
        local property = selections[i].value
        property:rename(name)
    end
end

---@param path string
---@param property_name string
---@param old_name string
---@return table
local function find_property_value_occurrences(path, property_name, old_name)
    local lines = vim.fn.readfile(path)
    local occurrences = {}
    local prop = vim.pesc(property_name)
    local prefixes = {
        "^%s*" .. prop .. "%s*:%s*",
        "^%s*" .. prop .. "%s*::%s*",
    }

    for lnum, line in ipairs(lines) do
        for _, prefix in ipairs(prefixes) do
            local _, prefix_end = line:find(prefix)
            if prefix_end then
                local value_start, value_end = line:find(vim.pesc(old_name), prefix_end + 1)
                if value_start and value_end then
                    occurrences[#occurrences + 1] = {
                        lnum = lnum,
                        start_col = value_start,
                        end_col = value_end,
                    }
                    break
                end
            end
        end
    end

    return occurrences
end

---@param raw table|nil
---@return table
local function normalize_occurrences(raw)
    if type(raw) ~= "table" then
        return {}
    end

    local occurrences = {}
    for key, value in pairs(raw) do
        if type(value) == "table" then
            if value.lnum ~= nil or value.col ~= nil or value.start_col ~= nil then
                occurrences[#occurrences + 1] = value
            elseif type(key) == "number" then
                local copy = vim.deepcopy(value)
                copy.lnum = copy.lnum or key
                occurrences[#occurrences + 1] = copy
            end
        elseif value == true and type(key) == "number" then
            occurrences[#occurrences + 1] = { lnum = key }
        end
    end

    table.sort(occurrences, function(a, b)
        return (a.lnum or 0) < (b.lnum or 0)
    end)
    return occurrences
end

local function rename_property_values(property_name, selections, lines)
    local state = require("vault.core.state")
    local Note = require("vault.notes.note")
    local vault_utils = require("vault.utils")

    for i, name in ipairs(lines) do
        --- @type vault.Property.Value
        local property_value = selections[i].value
        local old_name = property_value.data.name
        for slug, lnums in pairs(property_value.data.sources or {}) do
            local path = vault_utils.slug_to_path(slug)
            local occurrences = find_property_value_occurrences(path, property_name, old_name)
            if vim.tbl_isempty(occurrences) then
                occurrences = normalize_occurrences(lnums)
            end
            Note(path):update_content(old_name, name, occurrences)
        end
    end

    state.set_global_key("properties", nil)
    state.set_global_key("notes", nil)
    state.set_global_key("wikilinks", nil)
    state.set_global_key("cache.notes.paths", nil)
    state.set_global_key("cache.notes.slugs", nil)
    state.set_global_key("cache.notes.basename_index", nil)

    log.info("Renamed %d value(s) for property %s", #lines, tostring(property_name or "<unknown>"))
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
            log.warn("Nothing to rename — buffer is empty")
            return
        end
        if #lines ~= #strings_to_rename then
            log.warn("Line count changed — keep lines unchanged if you don't want to rename them")
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
function vault_actions.note.rename(bufnr)
    local _, _, selections = utils.get_picker_selection(bufnr)
    if selections and #selections == 1 then
        local note = selections[1].value
        vault_actions.close(bufnr)
        get_vault_api().open_picker_retarget_note(note.data.path, {})
        return
    end
    batch_rename(bufnr, selections)
end

--- Delete selected notes (moves to .trash by default)
function vault_actions.note.delete(bufnr)
    local _, _, selections = utils.get_picker_selection(bufnr)
    if not selections or #selections == 0 then
        return
    end
    local slugs = {}
    for _, sel in ipairs(selections) do
        table.insert(slugs, sel.value.data.slug)
    end
    actions.close(bufnr)
    highlights.detach()

    local function do_delete(permanent)
        for _, sel in ipairs(selections) do
            local ok, err = pcall(function()
                sel.value:delete(permanent, true)
            end)
            if not ok then
                log.error("Failed to delete %s: %s", sel.value.data.slug, tostring(err))
            end
        end
    end

    require("vault.ui.confirm").select({
        message = string.format("Delete %d note(s)?\n%s", #slugs, table.concat(slugs, "\n")),
        title = "Vault",
        choices = {
            {
                key = "t",
                label = "Trash",
                action = function()
                    do_delete(false)
                end,
            },
            {
                key = "p",
                label = "Permanent",
                action = function()
                    do_delete(true)
                end,
                danger = true,
            },
            {
                key = "c",
                label = "Cancel",
                action = function()
                    log.info("Delete cancelled")
                end,
            },
        },
        on_cancel = function()
            log.info("Delete cancelled")
        end,
    })
end

--- @type table<string, fun(bufnr?: number, selections?: table<vault.TelescopeEntry>): nil>
vault_actions.tag = {}

-- --- @param vault.FilterOpts
-- function vault_actions.filter_notes(opts)
--     local selection = actions_state.get_selected_entry()
--     --- @type vault.Tag
--     local tag = selection.value
--     vault_actions.close(bufnr)
--     telescope._extensions.vault.pickers.notes(
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
function vault_actions.tag.merge(bufnr)
    local _, _, selections = utils.get_picker_selection(bufnr)
    if next(selections) == nil then
        return
    end
    --- @type vault.Tag
    local tag = selections[1].value
    --- @type vault.Tag.Data.name
    local new_tag_name = vim.fn.input("Merge to: ", tag.data.name)
    merge(bufnr, selections, new_tag_name)
end

--- Rename tags
function vault_actions.tag.rename(bufnr)
    local _, _, selections = utils.get_picker_selection(bufnr)
    batch_rename(bufnr, selections)
end

--- Edit tag documentation
function vault_actions.tag.edit_documentation(bufnr)
    local _, selection, _ = utils.get_picker_selection(bufnr)
    vault_actions.close(bufnr)
    local tag = selection.value
    require("vault.api").edit_tag_documentation(tag.data.name)
end

--- Promote selected tag into a canonical wikilink target.
function vault_actions.tag.promote(bufnr)
    local _, selection, _ = utils.get_picker_selection(bufnr)
    vault_actions.close(bufnr)
    local tag = selection.value
    get_vault_api().open_picker_promote_tag(tag.data.name, {
        keep_frontmatter_tags = true,
    })
end

--- Open Telescope picker for notes with a specific tag
function vault_actions.tag.enter(bufnr)
    local _, selection, _ = utils.get_picker_selection(bufnr)
    vault_actions.close(bufnr)
    --- @type vault.Tag
    local tag = selection.value
    require("vault.api").open_picker_notes_with_tag(tag.data.name)
end

vault_actions.property = {}

--- Open Telescope picker for notes with a specific property
function vault_actions.property.enter(bufnr)
    local _, selection, _ = utils.get_picker_selection(bufnr)
    vault_actions.close(bufnr)
    --- @type vault.Property
    local property = selection.value
    require("vault.api").open_picker_property_values(property.data.name)
end

--- Rename properties
function vault_actions.property.rename(bufnr)
    local _, _, selections = utils.get_picker_selection(bufnr)
    batch_rename(bufnr, selections)
end

vault_actions.property_value = {}

function vault_actions.property_value.enter(bufnr)
    ---@type Picker
    local picker, selection, _ = utils.get_picker_selection(bufnr)
    vault_actions.close(bufnr)
    --- @type vault.Property.Value
    local value = selection.value
    local prompt_title = picker.prompt_title
    require("vault.api").open_picker_notes_with_property_value(prompt_title, value.data.name)
end

function vault_actions.property_value.rename(bufnr)
    local picker, _, selections = utils.get_picker_selection(bufnr)
    if not selections or #selections == 0 then
        return
    end

    local property_name = picker.prompt_title
    local strings_to_rename = {}
    for _, sel in ipairs(selections) do
        strings_to_rename[#strings_to_rename + 1] = sel.value.data.name
    end

    local height = math.min(vim.api.nvim_list_uis()[1].height - 2, math.max(1, #strings_to_rename))
    local position = math.floor((vim.api.nvim_list_uis()[1].height - height) / 2)
    local popup = Popup({
        enter = true,
        focusable = true,
        relative = "editor",
        border = { style = "double" },
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
    })
    popup:mount()
    vim.api.nvim_buf_set_name(
        popup.bufnr,
        string.format("Rename property values for %s", tostring(property_name or "property"))
    )
    vim.api.nvim_buf_set_lines(popup.bufnr, 0, 1, false, strings_to_rename)

    local function on_enter()
        local lines = vim.api.nvim_buf_get_lines(popup.bufnr, 0, -1, false)
        if next(lines) == nil then
            log.warn("Nothing to rename — buffer is empty")
            return
        end
        if #lines ~= #strings_to_rename then
            log.warn("Line count changed — keep lines unchanged if you don't want to rename them")
            return
        end
        rename_property_values(property_name, selections, lines)
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
        vault_actions.refresh()
    end)
end

vault_actions._rename_property_values = rename_property_values
vault_actions._normalize_occurrences = normalize_occurrences
vault_actions._find_property_value_occurrences = find_property_value_occurrences

vault_actions.directory = {}

function vault_actions.directory.enter(bufnr)
    local _, selection, _ = utils.get_picker_selection(bufnr)
    vault_actions.close(bufnr)
    --- @type vault.Dir
    local dir = selection.value
    require("vault.api").open_picker_notes_in_directory(dir)
end

vault_actions.directory.rename = function(bufnr)
    local _, selection, _ = utils.get_picker_selection(bufnr)
    --- @type vault.Dir
    local dir = selection.value
    local new_name = vim.fn.input("Rename directory: ", dir.data.relpath)
    if not new_name or new_name == "" or new_name == dir.data.relpath then
        return
    end
    vault_actions.close(bufnr)
    dir:rename(new_name)
end

--- @type table<string, fun(bufnr?: number, selections?: table<vault.TelescopeEntry>): nil>
vault_actions.base = {}

--- Open the bases editor for the selected base
function vault_actions.base.enter(bufnr)
    local _, selection, _ = utils.get_picker_selection(bufnr)
    vault_actions.close(bufnr)
    --- @type vault.Base
    local base = selection.value
    require("vault.views.grid").open({ base = base })
end

--- Open Telescope notes picker for notes matched by a specific base
function vault_actions.base.notes(bufnr)
    local _, selection, _ = utils.get_picker_selection(bufnr)
    vault_actions.close(bufnr)
    --- @type vault.Base
    local base = selection.value
    require("vault.api").open_picker_base_notes(base.data.name)
end

--- Open the .base file for editing
function vault_actions.base.edit(bufnr)
    local _, selection, _ = utils.get_picker_selection(bufnr)
    vault_actions.close(bufnr)
    --- @type vault.Base
    local base = selection.value
    if base.data.path and base.data.path ~= "" then
        vim.cmd("edit " .. vim.fn.fnameescape(base.data.path))
    end
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
        log.warn("No recent filter found")
        return
    end
    local notes = require("vault.notes")():filter(filter:invert())
    require("telescope._extensions.vault.pickers").notes({ notes = notes }):find()
end ]]

return vault_actions
