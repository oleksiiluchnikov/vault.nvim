local config = require("vault.config")
local utils = require("vault.utils")

local Notes = require("vault.notes")
local Note = require("vault.notes.note")
local NoteTitle = require("vault.notes.note.title")

local TelescopeLayout = require("telescope.pickers.layout")
local Popup = require("nui.popup")
local Object = require("nui.object")
local event = require("nui.utils.autocmd").event

---Popup for creating fleeting notes.
---@class VaultPopupFleetingNote
local PopupFleetingNote = Object("VaultPopupFleetingNote")

function PopupFleetingNote:init(content, opts)
	content = content or ""

  if not opts or next(opts) == nil then
    opts = config.popups.fleeting_note
  end

	opts.title = opts.title or { text = "Fleeting Note", preview = "border" }

	if opts.title.preview then
		if opts.title.preview == "border" then
			opts.editor.border.style = { "╭", "─", "╮", "│", "┤", "─", "├", "│" }
		elseif opts.title.preview == "prompt" then
			opts.editor.border.style = { "├", "─", "┤", "│", "┤", "─", "├", "│" }
		end
	end

	---@type TelescopeLayout
	local telescope_layout = nil

  local notes = Notes()
	local notes_list = vim.tbl_values(notes.map)
	local new_note_path = config.dirs.inbox .. "/" .. opts.title.text .. config.ext
  local is_note_exist = false


	---@type number
	local prompt_bufnr = nil

	---@type NuiPopup
	local editor_popup = Popup(opts.editor)

  ---Create Telescope layout.
  ---@see TelescopeLayout
	---@param picker Picker
	---@return TelescopeLayout
	local create_layout = function(picker)
		---@param width number - The width of the window.
		---@param height number - The height of the window.
		---@param row number - The row position of the window.
		---@param col number - The column position of the window.
		---@param win_type string - The type of window.
		local function get_configs(width, height, row, col, win_type)
			local win_config = {
				relative = "editor",
				width = width,
				height = height,
				row = row,
				col = col,
				border = opts.editor.border.style,
				style = "minimal",
			}

      local border_hl_group_name = "TelescopeBorder"

			if win_type == "title" then
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
			end

			if win_type == "results" then
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

		local function open_window(enter, width, height, row, col, win_type)
			local bufnr = vim.api.nvim_create_buf(false, true)
			if win_type == "title" then
        if type(bufnr) == "number" then
				   prompt_bufnr = bufnr
        end
      end

			local win_config = get_configs(width, height, row, col, win_type)
			local winid = vim.api.nvim_open_win(bufnr, enter, win_config)

			vim.wo[winid].winhighlight = "NormalFloat:TelescopeNormal"

			return TelescopeLayout.Window({
				bufnr = bufnr,
				winid = winid,
			})
		end

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

		local function update_window(window, win_opts)
			if window then
				if vim.api.nvim_win_is_valid(window.winid) then
					vim.api.nvim_win_set_config(
						window.winid,
						vim.tbl_deep_extend("force", vim.api.nvim_win_get_config(window.winid), win_opts)
					)
				end
			end
		end

		local results_row = opts.editor.position.row + opts.editor.size.height
		local results_col = opts.editor.position.col - 1
		local results_height = opts.results.size.height
		local results_width = opts.results.size.width

		local prompt_row = opts.editor.position.row - 1
		local prompt_col = opts.editor.position.col - 1

		telescope_layout = TelescopeLayout({
			picker = picker,
			mount = function(s)
				s.prompt = open_window(false, results_width, 1, prompt_row, prompt_col, "title")
				s.results = open_window(false, results_width, results_height, results_row, results_col, "results")
			end,
			unmount = function(s)
				destroy_window(s.prompt)
				destroy_window(s.results)
			end,
			update = function(s, height)
				results_row = opts.editor.position.row + height
				update_window(s.results, {
					row = results_row,
					col = results_col,
				})
			end,
		})

		return telescope_layout
	end


	local function create_picker()
		local pickers = require("telescope.pickers")
		local sorters = require("telescope.sorters")
		local finders = require("telescope.finders")

		local entries = {}
		for _, note in ipairs(notes_list) do
			table.insert(entries, "/" .. note.data.relpath)
		end

		if next(entries) == nil then
			return
		end

		if not entries then
			error("No notes found in vault")
		end

		local finder = finders.new_table({
			results = entries,
		})

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

	---Update the title of the note popup.
	local function update_buffers()
		---@type string[] -- The input lines of the note popup.
		local editor_popup_lines = vim.api.nvim_buf_get_lines(editor_popup.bufnr, 0, 1, false)
    if not editor_popup_lines then
      return
    end

		-- Update the title
		opts.title.text = tostring(os.date("%Y-%m-%d %A - %H-%M"))

		if editor_popup_lines[1]:find("%w") then
			opts.title.text = NoteTitle(editor_popup_lines[1]).text
		end

		if opts.title_preview then
			if opts.title_preview == "on_border" then
				editor_popup.border:set_text("top", " " .. opts.title.text .. " ", "center")
			elseif opts.title_preview == "on_prompt" then
				editor_popup.border:set_text("top", " " .. opts.title.text .. " ", "center")
			end
		end

    ---@type string[] -- The basenames of the notes in the vault.
    local notes_basenames = notes:values_by_key("basename")
    if vim.tbl_contains(notes_basenames, opts.title.text .. config.ext) then
      editor_popup.border:set_highlight("Error")
      editor_popup.border:set_text("bottom", utils.to_relpath(new_note_path), "left")
      is_note_exist = true
    else
      new_note_path = config.dirs.inbox .. "/" .. opts.title.text .. ".md"
      editor_popup.border:set_text("bottom", utils.to_relpath(new_note_path), "left")
      editor_popup.border:set_highlight("String")
      is_note_exist = false
    end


    ---TODO: Implement this. For now, just use the default height.
    ---Dynamicly update the height of the note_popup, and shift the results window down, if needed.
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

	---@param str string - The title of the note.
	local function update_prompt(bufnr, str)
		vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { str or "" })
	end

	local results_picker = create_picker()
	if results_picker == nil then
		error("No notes found in vault")
	end
	-- telescope_layout = results_picker.layout
	results_picker:find()

	editor_popup:map("n", "<Esc>", function()
    local is_note_really_exist = notes:has_note("basename", opts.title.text .. config.ext)

		if is_note_exist == false and is_note_really_exist == false then
      if type(content) == "table" then
        content = table.concat(content, "\n")
      end
      if content == "" then
        content = "# " .. opts.title.text .. "\n"
      end
      if content:find("%w") then
        content = "# " .. opts.title.text .. "\n" .. content
      end

      ---@type VaultNote
      Note({
        path = new_note_path,
        content = content
      }):write()
    end

		editor_popup:unmount()
		results_picker.layout:unmount()
	end)

	editor_popup:on({ event.InsertEnter, event.InsertLeave, event.TextChanged, event.TextChangedI }, function()
		update_buffers()
		update_prompt(prompt_bufnr, opts.title.text)
	end)

	editor_popup:on({ event.BufLeave, event.FocusLost }, function()
		editor_popup:unmount()
		results_picker.layout:unmount()
	end)

	editor_popup:mount()
end

---@alias VaultPopupFleetingNote.constructor fun(content: string?, opts: table?): VaultPopupFleetingNote
---@type VaultPopupFleetingNote.constructor|VaultPopupFleetingNote
local VaultPopupFleetingNote = PopupFleetingNote

return VaultPopupFleetingNote
