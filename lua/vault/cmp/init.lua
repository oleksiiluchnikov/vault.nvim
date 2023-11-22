local M = {}

local has_cmp, cmp = pcall(require, "cmp")
if not has_cmp then
  error("nvim-cmp is not installed")
	return
end

local has_dates, Dates = pcall(require, "dates")
if not has_dates then
  error("dates.nvim is not installed")
  return
end


local function register_date_source()
	local source = {}
	source.new = function()
		return setmetatable({}, { __index = source })
	end

	source.is_available = function()
		if vim.bo.filetype == "markdown" then
			return true
		end
	end

	source.get_trigger_characters = function()
		return { "0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "-", " " }
	end

	source.get_keyword_pattern = function() -- keyword_pattern is used to match the keyword before the cursor
    return [=[\[\d\-\s\]+$]=]
	end

	source.complete = function(_, request, callback)
		local input = request.context.cursor_before_line:sub(request.offset - 1)
		local typed_date = string.sub(request.context.cursor_before_line, request.offset - 11, request.offset - 1)
		local typed_string = string.match(request.context.cursor_before_line, "[%d%-]+$")

		if string.match(typed_date, "%d%d%d%d%-%d%d%-%d%d") or string.match(typed_date, "%d%d%d%d%-%d%d%-%d%d ") then
			local items = {}
			local weekday = os.date(
				"%A",
				os.time({
					year = string.sub(typed_date, 1, 4),
					month = string.sub(typed_date, 6, 7),
					day = string.sub(typed_date, 9, 10),
				})
			)
			local new_text = weekday
			if #typed_date == 10 then
				new_text = " " .. weekday
			end

			table.insert(items, {
				label = weekday,
				kind = 12,
				textEdit = {
					newText = new_text,
					range = {
						start = {
							line = request.context.cursor.row - 1,
							character = request.context.cursor.col - #input,
						},
						["end"] = {
							line = request.context.cursor.row - 1,
							character = request.context.cursor.col,
						},
					},
				},
			})
			callback({
				items = items,
				isIncomplete = true,
			})
		elseif typed_string and string.match(typed_string, "%d+") and #typed_string > 2 then
			local dates = {}
			dates = Dates.get(typed_string)
			local items = {}
			local config = require("vault.config")
			local journal_dir = config.dirs.journal.daily
			for _, date in ipairs(dates) do
        local weekday = Dates.get_weekday(date)
				local path = journal_dir .. "/" .. date .. " " .. weekday .. ".md"
				local content = ""
				local file = io.open(path, "r")
				if file then
					content = file:read("*a")
					file:close()
				end
				local kind = 12
				if content == "" then
					kind = 13
				end
				table.insert(items, {
					label = date,
					kind = kind,
					textEdit = {
						newText = date,
						range = {
							start = {
								line = request.context.cursor.row - 1,
								character = request.context.cursor.col - #typed_string - 1,
							},
							["end"] = {
								line = request.context.cursor.row - 1,
								character = request.context.cursor.col,
							},
						},
					},
					documentation = {
						kind = "markdown",
						value = content,
					},
				})
			end

			callback({
				items = items,
				isIncomplete = true,
			})
		else
			callback({ isIncomplete = true })
		end
	end
	cmp.register_source("vault_date", source.new())
end

local function register_tag_source()
	local Tags = require("vault.tags")
  local tags = Tags()
	local source = {}

	source.new = function()
		return setmetatable({}, { __index = source })
	end

	source.is_available = function()
		if vim.bo.filetype == "markdown" then
			return true
		end
	end

	source.get_trigger_characters = function()
		return { "#" }
	end

	source.get_keyword_pattern = function()
    return [=[\%(#\%(\w\|\-\|_\|\/\)\+\)]=]
	end

	source.complete = function(_, request, callback)
		local input = string.sub(request.context.cursor_before_line, request.offset - 1)
		local prefix = string.sub(request.context.cursor_before_line, 1, request.offset - 1)

		if string.match(prefix, "#") then
			local items = {}
			for _, tag in pairs(tags) do
				table.insert(items, {
					label = tag.data.name,
					kind = 12,
					textEdit = {
						newText = tag.data.name,
						range = {
							start = {
								line = request.context.cursor.row - 1,
								character = request.context.cursor.col - #input,
							},
							["end"] = {
								line = request.context.cursor.row - 1,
								character = request.context.cursor.col,
							},
						},
					},
					documentation = {
						kind = "markdown",
						value = tag.data.documentation:content(tag.data.name),
					},
				})
			end
			callback({
				items = items,
				isIncomplete = true,
			})
		else
			callback({ isIncomplete = true })
		end
	end

	cmp.register_source("vault_tag", source.new())
end

function M.setup()
	register_tag_source()
	register_date_source()
end

return M
