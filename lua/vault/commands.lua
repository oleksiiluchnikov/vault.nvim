local Pickers = require("vault.pickers")
local Notes = require("vault.notes")
local Tags = require("vault.tags")

vim.api.nvim_create_user_command("VaultNotes", function(args)
	local query = args.args
	if query == "" then
		Pickers.notes()
		return
	end
	local notes_map = Notes().map
	for _, note in pairs(notes_map) do
		if note.data.basename:lower() == query:lower() then
			vim.cmd("e " .. note.data.path)
		end
	end
end, {
	nargs = "*",
	complete = function()
		local basenames = Notes():values_by_key("basename")
    return basenames
	end,
})

  --TODO: Implement
vim.api.nvim_create_user_command("VaultTags", function(args)
	local fargs = args.fargs
	if next(fargs) == nil then
		Pickers.tags()
		return
	end
	local tags = Tags()
	local tags_names = {}
	for k, tag in pairs(tags.map) do
		for _, farg in ipairs(fargs) do
			if tag.data.name:match(farg) then
				table.insert(tags_names, tag.data.name)
			end
		end
	end


  --FIXME: Now it is not working. It is not filtering the tags
  Pickers.notes({}, {"tags",{}, tags_names, "exact", "any"})
end, {
	nargs = "*",
	complete = function()
		local tags = Tags()
    local tag_names = {}
    for _, tag in pairs(tags.map) do
      table.insert(tag_names, tag.data.name)
    end
    return tag_names
	end,
})

---Vault Dates
vim.api.nvim_create_user_command("VaultDates", function(args)
  local fargs = args.fargs
  if #fargs == 0 then
    Pickers.dates()
    return
  end
  local today = os.date("%Y-%m-%d")
  local year_ago = os.date("%Y-%m-%d", os.time() - 60 * 60 * 24 * 365)
  Pickers.dates(tostring(today), tostring(year_ago))
end, {
  nargs = "*",
  complete = function()
    local dates = require("dates").from_to(os.date("%Y-%m-%d"), os.date("%Y-%m-%d", os.time() - 60 * 60 * 24 * 365))
    local date_values = {}
    for _, date in ipairs(dates) do
      table.insert(date_values, date.value)
    end
    return date_values
  end,
})

---Vault Today
vim.api.nvim_create_user_command("VaultToday", function()
  local config = require("vault.config")
  local today = os.date("%Y-%m-%d %A")
  local path = config.dirs.root .. "/Journal/Daily/" .. today .. ".md"
  vim.cmd("e " .. path)
end, {
  nargs = 0,
})

vim.api.nvim_create_user_command("VaultNotesStatus", function(args)
  local fargs = args.fargs
  if #fargs == 0 then
    Pickers.root_tags()
    return
  end
  local tags = Tags()
  local statuses = {}
  for _, tag in pairs(tags.map) do
    for _, farg in ipairs(fargs) do
      if tag.data.name == farg then
        table.insert(statuses, tag.data.name)
      end
    end
  end
  Pickers.notes({}, {"tags", {statuses},{}, "startswith", "all"})
end, {
  nargs = "*",
  complete = function()
    local tags = Tags()
    local statuses = {}
      for _, tag in pairs(tags.map) do
        if tag.data.name:match("^status") and #tag.data.children > 0 then
          local status = tag.data.children[1]
          table.insert(statuses, status.value)
        end
      end
    return statuses
  end,
})

vim.api.nvim_create_user_command("VaultFleetingNote", function(args)
  local VaultPopupFleetingNote = require("vault.popups.fleeting_note")
  VaultPopupFleetingNote(args.fargs, {})
end, {
  nargs = "*",
})
