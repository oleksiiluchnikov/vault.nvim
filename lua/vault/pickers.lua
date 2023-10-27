local M = {}

local Log = require("plenary.log")
local Job = require("plenary.job")

local pickers = require("telescope.pickers")
local finders = require("telescope.finders")
local sorters = require("telescope.sorters")
local previewers = require("telescope.previewers")
local actions = require("telescope.actions")
local actions_state = require("telescope.actions.state")

local config = require("vault.config")
local Note = require("vault.note")
local Tag = require("vault.tag")
local utils = require("vault.utils")

local layout_mini = {
	layout_strategy = "vertical",
	layout_config = {
		height = 0.9,
		width = 0.3,
		prompt_position = "top",
	},
	sorting_strategy = "ascending",
	scroll_strategy = "cycle",
}

---Open notes picker
---@param notes Note[]|nil
function M.notes(notes)
	notes = notes or require("vault").notes()

	local entry_maker = function(entry)
		local bufwidth = 95
		local relpath_length = entry.relpath:len()
		local basename_length = entry.basename:len()
		local space = bufwidth - relpath_length - basename_length
		local spaces = string.rep(" ", space)
		local display = entry.relpath .. spaces .. entry.basename

		return {
			value = entry.path,
			ordinal = entry.relpath,
			display = display,
		}
	end

	local function enter(bufnr)
		local selection = actions_state.get_selected_entry()
		local path = selection.value
		actions.close(bufnr)
		vim.cmd("edit " .. path)
	end

	local bufwidth = vim.api.nvim_get_option("columns")
	local bufheight = vim.api.nvim_get_option("lines")

	pickers
		.new({}, {
			prompt_title = "Notes",
			finder = finders.new_table({
				results = notes,
				entry_maker = entry_maker,
			}),
			sorter = sorters.get_generic_fuzzy_sorter(),
			previewer = previewers.vim_buffer_cat.new({}),
			sorting_strategy = "ascending",
			layout_config = {
				height = bufheight,
				width = bufwidth,
				preview_width = 0.4,
			},
			attach_mappings = function()
				actions.select_default:replace(enter)
				return true
			end,
		})
		:find()
end

---Open tags picker
function M.tags()
	local tags = require("vault").get_tags()
		local root_dir = config.dirs.root
		local docs_dir = config.dirs.docs

	if not tags then
		return
	end

	local bufwidth = vim.api.nvim_get_option("columns")
	local bufheight = vim.api.nvim_get_option("lines")
  local preview_width = 0.7

	local layout_config = {
		height = bufheight,
		width = bufwidth,
    preview_width = preview_width,
	}

  local entry_display = require("telescope.pickers.entry_display")


	---@param tag Tag
	local function entry_maker(tag)
    local entry_width = 29
    local notes_length = #tag.notes_paths
    local count_length = tostring(notes_length):len()

    local displayer = entry_display.create({
      separator = " ",
      items = {
        { width = entry_width },
        { remaining = true },
        { width = count_length },
        { remaining = true },
      },
    })

    local make_display = function(entry)
      local tag_value = tag.value
      local display_count = tostring(#tag.notes_paths)

      ---@type table
      local display_value = {}
      if notes_length > 100 then
        display_value = {
          tag_value,
          "TelescopeResultsIdentifier",
        }
      elseif notes_length > 20 then
        display_value = {
          tag_value,
          "TelescopeResultsSelection",
        }
      else
        display_value = {
          tag_value,
          "TelescopeResultsComment",
        }
      end
      return displayer({
        display_value,
        { display_count, "TelescopeResultsNumber" },
      })
    end

		return {
			value = tag,
			ordinal = tag.value,
      display = make_display,
		}
	end

	local function enter(bufnr)
		local selection = actions_state.get_selected_entry()
		local notes_paths = selection.value.notes_paths
		local notes = {}
		for _, note_path in ipairs(notes_paths) do
			local note = Note:new({
        path = note_path,
      })
			table.insert(notes, note)
		end
		actions.close(bufnr)
		M.notes(notes)
	end

	local function edit_documentation(bufnr)
		local selection = actions_state.get_selected_entry()
		actions.close(bufnr)
		local tag = selection.value
    if tag.documentation == nil then
      return
    end
    tag.documentation:open()
	end


	pickers
		.new({}, {
			prompt_title = "Tags",
			finder = finders.new_table({
				results = vim.tbl_values(tags),
				entry_maker = entry_maker,
			}),
			sorter = sorters.get_generic_fuzzy_sorter(),
			previewer = previewers.new_buffer_previewer({
				define_preview = function(self, entry)
          print(vim.inspect(entry))
					local notes_paths = entry.value.notes_paths
					if #notes_paths == 0 then
						return
					end
					local lines = {}

					local documentation = entry.value.documentation:content(entry.value.value)
					if documentation ~= nil then
						local doc_lines = vim.split(documentation, "\n")
						for _, doc_line in ipairs(doc_lines) do
							table.insert(lines, doc_line)
						end
						local separator = string.rep("-", 80)
						table.insert(lines, separator)
					end

					local seen_notes_paths = {}
					for _, note_path in ipairs(notes_paths) do
						local note = Note:new({path = note_path})
						if not seen_notes_paths[note.relpath] then
							seen_notes_paths[note.relpath] = true
							table.insert(lines, note.relpath)
						end
					end
					local bufnr = self.state.bufnr
					vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
					vim.api.nvim_buf_set_option(bufnr, "filetype", "markdown")
					return vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
				end,
			}),
			layout_config = layout_config,
			attach_mappings = function(bufnr, map)
				actions.select_default:replace(enter)

				map("i", "<C-e>", edit_documentation)
				return true
			end,
		})
		:find()
end

---Open notes picker with specified tags
---@param tag_values string[]
function M.notes_with_tags(tag_values)
	local tags = require("vault").get_tags()
	local notes_with_tags = {}
	for _, tag_value in ipairs(tag_values) do
		for _, tag in ipairs(tags) do
			if tag.value == tag_value then
				for _, note_path in ipairs(tag.notes_paths) do
					local note = Note:new({
            path = note_path,
          })
					-- Should contain all tags!
					local note_tags = note:tags()
					local contains_all_tags = true
					for _, v in ipairs(tag_values) do
						local contains_tag = false
						for _, note_tag in ipairs(note_tags) do
							if note_tag.value == v then
								contains_tag = true
								break
							end
						end
						if not contains_tag then
							contains_all_tags = false
							break
						end
					end
					if contains_all_tags then
						table.insert(notes_with_tags, note)
					end
				end
				break
			end
		end
	end

	if #notes_with_tags == 0 then
		return
	end

	M.notes(notes_with_tags)
end

M.test = function()
	M.notes_with_tags({ "#status/TODO", "#class/Action" })
end

M.todos = function()
	M.notes_with_tags({ "#status/TODO" })
end

M.in_progress = function()
	M.notes_with_tags({ "#status/IN-PROGRESS" })
end

M.done = function()
	M.notes_with_tags({ "#status/DONE" })
end

M._cache = {
	parent_tag = "",
}

--- I want to browse tag until it has no more nesting,
--- and then return to full tag value like: status/TODO/later
--- and then pick with tags { status/TODO/later} for example
--- For example we have tag: software/Blender/extensions
function M.notes_by(tag_prefix) -- software or software/Blender(if we selected software)
	if tag_prefix == nil then
		return
	end
	local root_dir = config.dirs.root
	local tags = require("vault"):tags(tag_prefix) -- get all tags with prefix
	if #tags == 0 then
		-- if we selected software/Blender and there is no tags with prefix software/Blender
		-- then we have no more nesting and we need to return to full tag value
		-- our pick._cache.parent_tag will be software/Blender/software/Blender/extensions
		local parent_tag = M._cache.parent_tag
		if parent_tag == "" then
			return
		end
		local tag_value = parent_tag:gsub(tag_prefix .. "/", "") -- now we have software/Blender/extensions
		vim.notify(tag_value)
		M._cache.parent_tag = "" -- reset parent_tag
		M.notes_with_tags({ tag_value }) -- now we have { software/Blender/extensions }
		return
	end

	local entries = {}
	for _, tag in ipairs(tags) do
		local entry = tag.value -- now we have software/Blender/extensions if we selected software
		-- if we selected software/Blender we need to remove software/Blender from entry
		if tag_prefix ~= "" then
			entry = entry:gsub(tag_prefix .. "/", "") -- now we have extensions
		end
		if entry ~= "" then
			table.insert(entries, entry)
		end
	end

	if #entries == 0 then
		Log.error("No notes found in vault: " .. root_dir)
		return
	end

	local function enter(bufnr)
		local selection = actions_state.get_selected_entry()
		local tag = selection[1]
		actions.close(bufnr)

		--- if we selected software/Blender we need to save it to cache and remove software/Blender from tag value to left only extensions
		--- our pick._cache.parent_tag should be updated and conain software/Blender/extensions
		--- and then we can pick with tags { software/Blender/extensions }
		print(tag_prefix .. "/" .. tag)
		if M._cache.parent_tag ~= tag_prefix .. "/" .. tag then
			M._cache.parent_tag = tag_prefix .. "/" .. tag
			M.notes_by(tag_prefix .. "/" .. tag)
			return
		end
	end

	pickers
		.new(layout_mini, {
			prompt_title = "Status",
			finder = finders.new_table(entries),
			sorter = sorters.get_generic_fuzzy_sorter(),
			attach_mappings = function(_, _)
				actions.select_default:replace(enter)
				return true
			end,
		})
		:find()
end

function M.root_tags()
	local root_dir = config.dirs.root
	if type(root_dir) ~= "string" then
		return
	end

	local tags = require("vault").get_tags()
	local seen_root_tags = {}
	local entries = {}
	for _, tag in ipairs(tags) do
		if tag.value:find("/") ~= nil then
			local root_tag = tag.value:match("^[^/]+")
			if not seen_root_tags[root_tag] then
				seen_root_tags[root_tag] = true
				table.insert(entries, root_tag)
			end
		end
	end

	if #entries == 0 then
		Log.info("No root tags found in vault: " .. root_dir)
		return
	end

	local function enter(bufnr)
		local selection = actions_state.get_selected_entry()
		local root_tag = selection[1]
		vim.notify(root_tag)
		actions.close(bufnr)
		M.notes_by(root_tag)
	end

	pickers
		.new(layout_mini, {
			prompt_title = "Status",
			finder = finders.new_table(entries),
			sorter = sorters.get_generic_fuzzy_sorter(),
			attach_mappings = function(_, _)
				actions.select_default:replace(enter)
				return true
			end,
		})
		:find()
end

return M
