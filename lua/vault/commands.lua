local Pickers = require("vault.pickers")

vim.api.nvim_create_user_command("VaultList", "lua P(require('vault').list(<f-args>))", {
	nargs = "*",
	complete = function()
		local list = require("vault").list()
		return list
	end,
})

vim.api.nvim_create_user_command("VaultNotes", function(args)
	local query = args.args
	if query == "" then
		Pickers.notes()
		return
	end
	local notes = require("vault").notes()
	for _, note in ipairs(notes) do
		if note.basename:lower() == query:lower() then
			vim.cmd("e " .. note.path)
		end
	end
end, {
	nargs = "*",
	complete = function()
		local notes = require("vault").notes()
		local note_names = {}
		for _, note in ipairs(notes) do
			table.insert(note_names, note.basename)
		end
		return note_names
	end,
})

vim.api.nvim_create_user_command("VaultTags", function(args)
	local fargs = args.fargs
	if #fargs == 0 then
		Pickers.tags()
		return
	end
	local tags = require("vault").get_tags()
	local tag_values = {}
	for _, tag in ipairs(tags) do
		for _, farg in ipairs(fargs) do
			if tag.value == farg then
				table.insert(tag_values, tag.value)
			end
		end
	end
	Pickers.notes_with_tags(tag_values)
end, {
	nargs = "*",
	complete = function()
		local tags = require("vault").get_tags()
		local tag_values = {}
		for _, tag in ipairs(tags) do
			table.insert(tag_values, tag.value)
		end
		return tag_values
	end,
})

vim.api.nvim_create_user_command("VaultNotesStatus", function(args)
  local fargs = args.fargs
  if #fargs == 0 then
    Pickers.root_tags()
    return
  end
  local tags = require("vault").get_tags()
  local statuses = {}
  for _, tag in ipairs(tags) do
    for _, farg in ipairs(fargs) do
      if tag.value == farg then
        table.insert(statuses, tag.value)
      end
    end
  end
  Pickers.notes_with_tags(statuses)
end, {
  nargs = "*",
  complete = function()
    local notes = require("vault").notes()
    local statuses = {}
    for _, note in ipairs(notes) do
      local tags = note.get_tags()
      for _, tag in ipairs(tags) do
        if tag.value:match("^status") and #tag.children > 0 then
          local status = tag.children[1]
          table.insert(statuses, status.value)
        end
      end
    end
    return statuses
  end,
})
