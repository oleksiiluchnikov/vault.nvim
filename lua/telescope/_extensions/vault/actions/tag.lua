local vault_state = require("vault.core.state")
local utils = require("telescope._extensions.vault.utils")
local common = require("telescope._extensions.vault.actions.common")

--- @type table<string, fun(bufnr?: number, selections?: table<vault.TelescopeEntry>): nil>
local tag_actions = {}

--- Merge selected tags in to one tag.
---@param _ number|nil
---@param selections table
---@param new_name string
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

--- Open Telescope picker for notes with a specific tag.
---@param bufnr? number
function tag_actions.enter(bufnr)
    local _, selection, _ = utils.get_picker_selection(bufnr)
    common.close(bufnr)
    --- @type vault.Tag
    local tag = selection.value
    common.safe_find(
        require("telescope._extensions.vault.pickers").notes({
            notes = require("vault.notes")():filter({
                search_term = "tags",
                include = { tag.data.name },
                exclude = {},
                match_opt = "exact",
                mode = "all",
                case_sensitive = false,
            }),
        }),
        "No notes found with tag: " .. tag.data.name
    )
end

--- Rename tags.
---@param bufnr? number
function tag_actions.rename(bufnr)
    local _, _, selections = utils.get_picker_selection(bufnr)
    common.batch_rename(bufnr, selections)
end

--- Merge selected tags in to one tag.
---@param bufnr? number
function tag_actions.merge(bufnr)
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

--- Edit tag documentation.
---@param bufnr? number
function tag_actions.edit_documentation(bufnr)
    local _, selection, _ = utils.get_picker_selection(bufnr)
    common.close(bufnr)
    local tag = selection.value
    require("vault.tags.actions").edit_documentation(tag.data.name)
end

--- Promote selected tag into a canonical wikilink target.
---@param bufnr? number
function tag_actions.promote(bufnr)
    local _, selection, _ = utils.get_picker_selection(bufnr)
    common.close(bufnr)
    local tag = selection.value
    require("vault.tags.workflows").open_promote_picker(tag.data.name, {
        keep_frontmatter_tags = true,
    })
end

return tag_actions
