local actions = require("telescope.actions")
local highlights = require("vault.highlights")
local utils = require("telescope._extensions.vault.utils")
local common = require("telescope._extensions.vault.actions.common")
local log = require("vault.log").scope("telescope")

--- @type table<string, fun(bufnr?: number, selections?: table<vault.TelescopeEntry>): nil>
local note_actions = {}

--- Edit the selected note.
---@param bufnr? number
function note_actions.edit(bufnr)
    local _, selection, _ = utils.get_picker_selection(bufnr)
    --- @type vault.Note
    local note = selection.value
    common.close(bufnr)
    note:edit()
end

--- Preview note with config.options.popups.preview.
---@param bufnr? number
function note_actions.preview(bufnr)
    local _, selection, _ = utils.get_picker_selection(bufnr)
    local note = selection.value
    common.close(bufnr)
    note:preview()
end

--- Merge selected note into another canonical target chosen from notes/wikilinks.
---@param bufnr? number
function note_actions.merge(bufnr)
    local _, selection, _ = utils.get_picker_selection(bufnr)
    local note = selection.value
    common.close(bufnr)
    require("vault.notes.workflows").open_merge_picker(note.data.path, {})
end

--- Rename notes.
---@param bufnr? number
function note_actions.rename(bufnr)
    local _, _, selections = utils.get_picker_selection(bufnr)
    if selections and #selections == 1 then
        local note = selections[1].value
        common.close(bufnr)
        require("vault.notes.workflows").open_retarget_picker(note.data.path, {})
        return
    end
    common.batch_rename(bufnr, selections)
end

--- Delete selected notes (moves to .trash by default).
---@param bufnr? number
function note_actions.delete(bufnr)
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

return note_actions
