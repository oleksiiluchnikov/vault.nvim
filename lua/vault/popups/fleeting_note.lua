if not pcall(require, "nui.popup") then
    vim.notify("nui.nvim is required to run vault.nvim", vim.log.levels.ERROR)
    return
end

local TelescopeLayout = require("telescope.pickers.layout")
local Popup = require("nui.popup")
local event = require("nui.utils.autocmd").event

local Object = require("vault.core.object")
---@type VaultConfig|VaultConfig.options
local config = require("vault.config")
local utils = require("vault.utils")

local Notes = require("vault.notes")
local Note = require("vault.notes.note")
local NoteTitle = require("vault.notes.note.title")

--- Popup for creating fleeting notes.
---@class VaultPopup.fleeting_note: VaultObject
local PopupFleetingNote = Object("VaultPopup.fleeting_note")

---@class VaultPopup.fleeting_note.options: nui_popup_options
---@field title VaultPopup.fleeting_note.title
---@field editor VaultPopup.fleeting_note.options.editor
---@field results VaultPopup.fleeting_note.options.results

---@class VaultPopup.fleeting_note.options.editor: nui_popup_options

---@class VaultPopup.fleeting_note.options.results: nui_popup_options

---@class VaultPopup.fleeting_note.title: { text: string, preview: string }

--- Create a new `VaultPopupFleetingNote` instance.
---
---@param s string? - The content for the note (optional).
---@param opts VaultPopup.fleeting_note.options? - The options for the popup (optional).
---@return nil
function PopupFleetingNote:init(s, opts)
    s = s or ""
    if not opts or next(opts) == nil then
        opts = config.popups.fleeting_note
    end
    opts.title = opts.title or { text = "Fleeting Note", preview = "border" }
    if opts.title.preview then
        if opts.title.preview == "border" then
            ---@type _nui_popup_border_style_list
            opts.editor.border.style = { "╭", "─", "╮", "│", "┤", "─", "├", "│" }
        elseif opts.title.preview == "prompt" then
            ---@type _nui_popup_border_style_list
            opts.editor.border.style = { "├", "─", "┤", "│", "┤", "─", "├", "│" }
        end
    end

    ---@type TelescopeLayout
    local telescope_layout
    ---@type VaultNotes
    local notes = Notes()
    ---@type VaultArray.notes
    local notes_list = notes:list()
    ---@type VaultNote.data.path
    local new_note_path = config.dirs.inbox .. "/" .. opts.title.text .. config.ext
    ---@type NuiPopup
    local editor_popup = Popup(opts.editor)
    local is_note_exist = false
    ---@type number
    local prompt_bufnr

    --- Create Telescope layout.
    ---
    ---@see TelescopeLayout
    ---@param picker Picker
    ---@return TelescopeLayout
    local create_layout = function(picker)
        --- Get the window configurations for the Popup windows.
        ---
        ---@param win_opts vim.api.keyset.float_config @see `nvim_open_win` for opts
        ---@param win_type string - The type of window.
        ---@return vim.api.keyset.float_config
        local function get_configs(win_opts, win_type)
            ---@type nui_popup_win_config
            local win_config = {
                relative = "editor",
                width = win_opts.width,
                height = win_opts.height,
                row = win_opts.row,
                col = win_opts.col,
                border = opts.editor.border.style,
                style = "minimal",
            }
            local border_hl_group_name = "TelescopeBorder"

            if win_type == "title" then
                ---@type _nui_popup_border_style_list
                win_config.border = {
                    { "╭", border_hl_group_name },
                    { "─", border_hl_group_name },
                    { "╮", border_hl_group_name },
                    { "│", border_hl_group_name },
                    { "│", border_hl_group_name },
                    { " ", border_hl_group_name },
                    { "│", border_hl_group_name },
                    { "│", border_hl_group_name },
                }
            elseif win_type == "results" then
                ---@type _nui_popup_border_style_list
                win_config.border = {
                    { " ", border_hl_group_name },
                    { " ", border_hl_group_name },
                    { " ", border_hl_group_name },
                    { "│", border_hl_group_name },
                    { "╯", border_hl_group_name },
                    { "─", border_hl_group_name },
                    { "╰", border_hl_group_name },
                    { "│", border_hl_group_name },
                }
            end

            return win_config
        end

        --- Open a window.
        ---
        ---@param enter boolean - Whether to enter the window.
        ---@param win_opts vim.api.keyset.float_config - The options for the window.
        ---@param win_type string - The type of window.
        ---@return TelescopeWindow
        local function open_window(enter, win_opts, win_type)
            local bufnr = vim.api.nvim_create_buf(false, true)
            if type(bufnr) ~= "number" then
                error("Unable to create buffer")
            end
            if win_type == "title" then
                prompt_bufnr = bufnr
            end

            ---@type vim.api.keyset.float_config
            local win_config = get_configs(win_opts, win_type)
            local winid = vim.api.nvim_open_win(bufnr, enter, win_config)
            if type(winid) ~= "number" then
                error("Failed to open window: " .. vim.inspect(bufnr, vim.inspect(win_config)))
            end
            vim.wo[winid].winhighlight = "NormalFloat:TelescopeNormal"
            ---@type TelescopeWindow.config
            local telescope_layout_win_config = {
                bufnr = bufnr,
                winid = winid,
            }

            return TelescopeLayout.Window(telescope_layout_win_config)
        end

        --- Destroy a window.
        ---
        ---@param window TelescopeWindow - The window to destroy.
        ---@return nil
        local function destroy_window(window)
            if window then
                if vim.api.nvim_win_is_valid(window.winid) then
                    vim.api.nvim_win_close(window.winid, true)
                end
                if vim.api.nvim_buf_is_valid(window.bufnr) then
                    vim.api.nvim_buf_delete(window.bufnr, { force = true })
                end
            end
        end

        --- Update a window.
        ---
        ---@param window TelescopeWindow - The window to update.
        ---@param win_opts vim.api.keyset.float_config - The options for the window.
        ---@return nil
        local function update_window(window, win_opts)
            if not window then
                error("Unable to update window: " .. vim.inspect(win_opts))
            end
            if not win_opts then
                error("Unable to update window: " .. vim.inspect(win_opts))
            end
            if vim.api.nvim_buf_is_valid(window.winid) == false then
                error("Unable to update window: " .. vim.inspect(win_opts))
            end

            local prev_win_config = vim.api.nvim_win_get_config(window.winid)

            vim.api.nvim_win_set_config(
                window.winid,
                vim.tbl_deep_extend("force", prev_win_config, win_opts)
            )
        end

        local results_row = opts.editor.position.row + opts.editor.size.height
        local results_col = opts.editor.position.col - 1
        ---@type integer?
        local results_width = tonumber(opts.editor.size.width)
        ---@type integer?
        local results_height = tonumber(opts.results.size.height)

        ---@type vim.api.keyset.float_config
        local results_win_opts = {
            row = results_row,
            col = results_col,
            height = results_height,
            width = results_width,
        }

        -- We should hide the prompt window, because we don't need it.
        -- But we need to keep it, because we need to update the prompt buffer.
        local prompt_row = opts.editor.position.row - 1
        local prompt_col = opts.editor.position.col - 1
        ---@type integer?
        local prompt_width = results_width
        ---@type integer?
        local prompt_height = 1

        ---@type vim.api.keyset.float_config
        local prompt_win_opts = {
            row = prompt_row,
            col = prompt_col,
            height = prompt_height,
            width = prompt_width,
        }

        ---@param this TelescopeLayout
        ---@return nil
        local mount = function(this)
            -- s.prompt = open_window(false, results_width, 1, prompt_row, prompt_col, "title")
            this.results = open_window(false, results_win_opts, "results")
            this.prompt = open_window(false, prompt_win_opts, "title")
        end

        ---@param this TelescopeLayout
        ---@return nil
        local unmount = function(this)
            destroy_window(this.prompt)
            destroy_window(this.results)
        end

        ---@param this TelescopeLayout
        ---@param height number
        ---@return nil
        local update = function(this, height)
            results_win_opts.row = opts.editor.position.row + height
            update_window(this.results, {
                row = results_win_opts.row,
                col = results_win_opts.col,
            })
        end

        ---@type TelescopeLayout.config
        local telecsope_layout_config = {
            picker = picker,
            mount = mount,
            unmount = unmount,
            update = update,
        }

        ---@type TelescopeLayout
        telescope_layout = TelescopeLayout(telecsope_layout_config)

        return telescope_layout
    end

    --- Create a picker for the note popup.
    --- It will display dynamicly the notes in the vault similar title to the title of the note popup.
    ---
    ---@return Picker
    local function create_picker()
        local pickers = require("telescope.pickers")
        local sorters = require("telescope.sorters")
        local finders = require("telescope.finders")

        ---@type VaultNote.data.relpath[]
        local entries = {}
        for _, note in ipairs(notes_list) do
            table.insert(entries, "/" .. note.data.relpath)
        end

        ---@type table
        local finder = finders.new_table({
            results = entries,

            -- TODO: Implement this
            -- It would be nice to make fancy UI for the results.
            -- entry_maker = function(entry)
            -- end
        })

        ---@type Picker
        return pickers.new({}, {
            finder = finder,
            sorter = sorters.get_fzy_sorter(),
            create_layout = create_layout,
            get_status_text = function()
                return ""
            end,
            default_text = "",
            prompt_title = "Title: ",
            results_title = false,
        })
    end

    --- Update the title, and the bottom border of the note popup.
    ---
    ---@return nil
    local function update_buffers()
        ---@type string[] -- The input lines of the note popup.
        local editor_popup_lines = vim.api.nvim_buf_get_lines(editor_popup.bufnr, 0, 1, false)
        if not editor_popup_lines then
            return
        end
        -- Update the title of the note popup. Default is the current date.
        opts.title.text = tostring(os.date("%Y-%m-%d %A - %H-%M")) -- TODO: Make this configurable.

        if editor_popup_lines[1]:find("%w") then
            opts.title.text = NoteTitle(editor_popup_lines[1]).text
        end

        if opts.title.preview then
            editor_popup.border:set_text("top", " " .. opts.title.text .. " ", "center")
        end

        ---@type table<VaultNote.data.stem, boolean>
        local notes_stems = notes:value_map_with_key("stem", true)
        local query = opts.title.text:lower()

        -- Set the border color to `Error` if the note already exists. So we can warn the user.
        -- else
        -- Set the border color to `String` if the note does not exist. So we can inform the user.
        --- TODO: Implement this. For now, just use the default path.
        if notes_stems[query] then
            editor_popup.border:set_highlight("Error")
            is_note_exist = true
        else
            editor_popup.border:set_highlight("String")
            ---@type VaultNote.data.path
            new_note_path = config.dirs.inbox .. "/" .. opts.title.text .. config.ext
            is_note_exist = false
        end

        local relpath = utils.path_to_relpath(new_note_path)
        editor_popup.border:set_text("bottom", relpath, "left")

        --- TODO: Implement this. For now, just use the default height.
        --- Dynamicly update the height of the note_popup, and shift the results window down, if needed.
        --   local new_height = #vim.api.nvim_buf_get_lines(editor_popup.bufnr, 0, -1, false)
        --
        -- if new_height > opts.editor.size.height then
        --     if pcall(require, "stay-centered") then
        --     package.loaded["stay-centered"] = nil
        --     end
        -- 	local height = new_height + 1
        -- 	editor_popup:update_layout({
        -- 		position = {
        -- 			row = opts.editor.position.row,
        -- 			col = opts.editor.position.col,
        -- 		},
        -- 		size = {
        -- 			height = height,
        -- 			width = opts.editor.size.width,
        -- 		},
        -- 	})
        --
        -- 	if telescope_layout then
        -- 		telescope_layout:update(height)
        -- 	end
        --   else
        --     if pcall(require, "stay-centered") then
        --     require("stay-centered")
        --     end
        -- end
    end

    --- Update the prompt buffer.
    ---
    ---@param bufnr number - The buffer number of the prompt buffer.
    ---@param new_title_text string? - The new title text.
    ---@return nil
    local function update_prompt(bufnr, new_title_text)
        new_title_text = new_title_text or ""
        local replacement = { new_title_text }
        vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, replacement)
    end

    --- Create the picker
    ---@type Picker
    local results_picker = create_picker()
    -- Open the picker
    results_picker:find()

    --- Map the keys for the note popup.
    editor_popup:map("n", "<Esc>", function()
        if not is_note_exist then
            if type(s) == "table" then
                s = table.concat(s, "\n")
            end
            if s == "" then
                -- s = "# " .. opts.title.text .. "\n"
                -- dismiss
                editor_popup.border:set_highlight("Error")
                return
            end
            if s:find("%w") then
                s = "# " .. opts.title.text .. "\n" .. s
            end

            ---@type VaultNote
            local new_note = Note({
                path = new_note_path,
                content = s,
            })

            new_note:write()
            editor_popup:unmount()
            results_picker.layout:unmount()
        end
        -- What should we do if the note already exists?
        -- Ask for a new title
    end)

    editor_popup:on(
        { event.InsertEnter, event.InsertLeave, event.TextChanged, event.TextChangedI },
        function()
            update_buffers()
            update_prompt(prompt_bufnr, opts.title.text)
        end
    )
    editor_popup:on({ event.BufLeave, event.FocusLost }, function()
        editor_popup:unmount()
        results_picker.layout:unmount()
    end)
    editor_popup.border:set_highlight("TelescopeBorder")
    editor_popup:mount()
end

---@alias VaultPopup.fleeting_note.constructor fun(s: string?, opts: VaultPopup.fleeting_note.options?): VaultPopup.fleeting_note
---@type VaultPopup.fleeting_note.constructor|VaultPopup.fleeting_note
local VaultPopupFleetingNote = PopupFleetingNote

return VaultPopupFleetingNote
