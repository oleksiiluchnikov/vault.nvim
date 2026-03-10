--- @class telescope_popup_options.vault.move_note_to: telescope_popup_options
--- @field note? vault.Note

--- @param opts table
--- @return Picker
return function(opts)
    local vault_state = require("vault.core.state")
    local entry_display = require("telescope.pickers.entry_display")
    local finders = require("telescope.finders")
    local pickers = require("telescope.pickers")
    local sorters = require("telescope.sorters")
    local log = require("vault.log").scope("telescope")
    local config = require("vault.config")
    local utils = require("vault.utils")
    local actions = require("telescope.actions")
    local actions_state = require("telescope.actions.state")
    local Note = require("vault.notes.note")

    opts = opts or {}
    opts.note = opts.note

    if opts.note == nil then
        -- get current buffer path
        local bufnr = vim.api.nvim_get_current_buf()
        local path = vim.api.nvim_buf_get_name(bufnr)
        if not utils.match(path, config.options.root, "startswith", false) then
            log.error("Current buffer is not in vault")
        end
        opts.note = Note(path)
    end

    local root_dir = config.options.root
    -- Simple picker to show all relative dirs where we can move note
    -- on enter we move note to selected dir
    local function enter(bufnr)
        local selection = actions_state.get_selected_entry()
        --- @type vault.path
        local path = selection.value
        local basename = vim.fn.fnamemodify(opts.note.data.path, ":t")
        local new_path = string.format("%s%s", path, basename)
        actions.close(bufnr)
        -- vim.fn.rename(note.data.path, new_path)
        opts.note:rename(new_path)
        -- Update current buffer.
        -- How does vim manage this?
        -- If we rename current buffer, it will be closed and new buffer will be opened
        local bufnr_of_note = vim.fn.bufnr(opts.note.data.path)
        -- vim.cmd("write") -- write changes to disk
        -- we couldnd write becaust the picker is still open
        vim.api.nvim_buf_delete(bufnr_of_note, { force = true })
        vim.cmd("edit " .. vim.fn.fnameescape(new_path))
    end

    --- @param entry vault.TelescopeEntry
    local make_display = function(entry)
        local entry_width = entry.value:len()
        local displayer = entry_display.create({
            separator = " ",
            items = {
                { width = entry_width },
                { remaining = true },
            },
        })
        local display_value = {
            -- entry.value,
            utils.path_to_relpath(entry.value),
            "TelescopeResultsNormal",
        }
        return displayer({
            display_value,
        })
    end

    local entry_maker = function(entry)
        return {
            value = entry,
            ordinal = entry,
            display = make_display,
        }
    end

    local attach_mappings = function()
        actions.select_default:replace(enter)
        return true
    end

    local results = {}
    if not root_dir or vim.fn.isdirectory(root_dir) == 0 then
        error("Root directory does not exist")
    end
    for _, dir in ipairs(utils.safe_globpath(root_dir, "**/", true, true)) do
        table.insert(results, dir)
    end

    local picker = pickers.new({}, {
        prompt_title = "Move note to",
        finder = finders.new_table({
            results = results,
            entry_maker = entry_maker,
        }),
        sorter = sorters.get_generic_fuzzy_sorter(),
        attach_mappings = attach_mappings,
    })
    vault_state.set_global_key("picker", picker)
    return picker
end
