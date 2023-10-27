local M = {}

local has_cmp, cmp = pcall(require, "cmp")
if not has_cmp then
	return
end

local function register_date_source()

	local year_endings = {}
	for i = 0, 99 do
		local year_ending = string.format("%02d", i)
		table.insert(year_endings, year_ending)
	end

	local months = {}
	for i = 1, 12 do
		local month = string.format("%02d", i)
		table.insert(months, month)
	end

	local days = {}
	for i = 1, 31 do
		local day = string.format("%02d", i)
		table.insert(days, day)
	end

	local year_beginnings = {}
	for i = 10, 21 do
		local year_beginning = tostring(i)
		table.insert(year_beginnings, year_beginning)
	end

	local function is_valid_date(date)
		local year = string.sub(date, 1, 4)
		local month = string.sub(date, 6, 7)
		local day = string.sub(date, 9, 10)
    if tonumber(day) > 29 and tonumber(month) == 2 and (tonumber(year) % 4) == 0 then
      return false
    elseif tonumber(day) > 28 and tonumber(month) == 2 and (tonumber(year) % 4) ~= 0 then
      return false
    elseif tonumber(day) > 30 and (tonumber(month) == 4 or tonumber(month) == 6 or tonumber(month) == 9 or tonumber(month) == 11) then
      return false
    end
    return true
	end

  local function get_dates(year_beginning)
    local date_endings = {}
		for _, year_ending in ipairs(year_endings) do
			for _, month in ipairs(months) do
				for _, day in ipairs(days) do
          local date = year_beginning .. year_ending .. "-" .. month .. "-" .. day
          if is_valid_date(date) then
            table.insert(date_endings, date)
          end
				end
			end
		end
    return date_endings
end

	---Get date suggestions for a given prefix
	---@param prefix_to_filter string -- like 202 or 19 or 20 or 2021-0 or 2021-01 or 2021-01-0 or 2021-01-01
	---@param endings table -- like { "2021-01-01", "2021-01-02", "2021-01-03" }
	---@return table -- like { "2021-01-01", "2021-01-02", "2021-01-03" }
	local function filter_dates(prefix_to_filter)
		local dates = {}
    local endings = get_dates(prefix_to_filter:sub(1, 2))
    -- Notice: escape the "-" in the prefix_to_filter
    local pattern = prefix_to_filter:gsub("-", "%%-")
    for _, ending in ipairs(endings) do
      if string.match(ending, "^" .. pattern) then
        table.insert(dates, ending)
      end
    end
		return dates
	end

	local date_source = {}
	date_source.new = function()
		return setmetatable({}, { __index = date_source })
	end

	date_source.is_available = function()
		if vim.bo.filetype == "markdown" then
			return true
		end
	end

	date_source.get_trigger_characters = function()
		return { "0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "-", " " }
	end

	date_source.get_keyword_pattern = function() -- keyword_pattern is used to match the keyword before the cursor
		return [[\[\d\-\s\]+$]]
	end

	date_source.complete = function(_, request, callback)
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
			dates = filter_dates(typed_string)
			local items = {}
      local config = require("vault.config")
      local journal_dir = config.dirs.journal.daily
			for _, date in ipairs(dates) do
        local weekday = os.date(
          "%A",
          os.time({
            year = string.sub(date, 1, 4),
            month = string.sub(date, 6, 7),
            day = string.sub(date, 9, 10),
          })
        )
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
	cmp.register_source("vault_date", date_source.new())
end

local function register_tag_source()
	local tags = require("vault").get_tags()
	local tag_source = {}

	tag_source.new = function()
		return setmetatable({}, { __index = tag_source })
	end

	tag_source.is_available = function()
		if vim.bo.filetype == "markdown" then
			return true
		end
	end

	tag_source.get_trigger_characters = function()
		return { "#" }
	end

	tag_source.get_keyword_pattern = function()
		return [[\%(#\%(\w\|\-\|_\|\/\)\+\)]]
	end

	tag_source.complete = function(_, request, callback)
		local input = string.sub(request.context.cursor_before_line, request.offset - 1)
		local prefix = string.sub(request.context.cursor_before_line, 1, request.offset - 1)

		if string.match(prefix, "#") then
			local items = {}
			for _, tag in pairs(tags) do
				table.insert(items, {
					label = tag.value,
					kind = 12,
					textEdit = {
						newText = tag.value,
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
						value = tag.documentation:content(tag.value),
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

	cmp.register_source("vault_tag", tag_source.new())
end

function M.setup()
	register_tag_source()
	register_date_source()
end

return M
