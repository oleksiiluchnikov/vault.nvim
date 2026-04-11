local layouts = require("telescope._extensions.vault.layouts")
local utils = require("telescope._extensions.vault.utils")
local common = require("telescope._extensions.vault.actions.common")
local log = require("vault.log").scope("telescope")
local Popup = require("nui.popup")
local event = require("nui.utils.autocmd").event
--- @type table<string, fun(bufnr?: number, selections?: table<vault.TelescopeEntry>): nil>
local property_actions = {}
--- @type table<string, fun(bufnr?: number, selections?: table<vault.TelescopeEntry>): nil>
local property_value_actions = {}
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

---@param property_name string
---@param selections vault.TelescopeEntry[]
---@param lines string[]
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
    require("vault.scanner").invalidate_notes_cache()
    log.info("Renamed %d value(s) for property %s", #lines, tostring(property_name or "<unknown>"))
end

--- Open Telescope picker for notes with a specific property.
---@param bufnr? number
function property_actions.enter(bufnr)
    local _, selection, _ = utils.get_picker_selection(bufnr)
    common.close(bufnr)
    --- @type vault.Property
    local property = selection.value
    require("vault.properties.actions").open_picker_values(property.data.name)
end

--- Rename properties.
---@param bufnr? number
function property_actions.rename(bufnr)
    local _, _, selections = utils.get_picker_selection(bufnr)
    common.batch_rename(bufnr, selections)
end

---@param bufnr? number
function property_value_actions.enter(bufnr)
    ---@type Picker
    local picker, selection, _ = utils.get_picker_selection(bufnr)
    common.close(bufnr)
    --- @type vault.Property.Value
    local value = selection.value
    local prompt_title = picker.prompt_title
    require("vault.properties.actions").open_picker_notes_with_value(prompt_title, value.data.name)
end

---@param bufnr? number
function property_value_actions.rename(bufnr)
    local picker, _, selections = utils.get_picker_selection(bufnr)
    if not selections or #selections == 0 then
        return
    end
    local property_name = picker.prompt_title
    local strings_to_rename = {}
    for _, sel in ipairs(selections) do
        strings_to_rename[#strings_to_rename + 1] = sel.value.data.name
    end
    local ui_height, _ = layouts.ui_size()
    local height = math.min(ui_height - 2, math.max(1, #strings_to_rename))
    local position = math.floor((ui_height - height) / 2)
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
            log.warn("Nothing to rename - buffer is empty")
            return
        end
        if #lines ~= #strings_to_rename then
            log.warn("Line count changed - keep lines unchanged if you don't want to rename them")
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
        common.refresh()
    end)
end
return {
    property = property_actions,
    property_value = property_value_actions,
    _rename_property_values = rename_property_values,
    _normalize_occurrences = normalize_occurrences,
    _find_property_value_occurrences = find_property_value_occurrences,
}
