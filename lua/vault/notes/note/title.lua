local Title = {}
local Note = require("vault.notes.note")

---Sync title with filename and update {inlinks}.
---@class Title
---@field new string
---@field sync fun(path: string)

---@return Title
-- function Title:new(basename)
--   -- return basename
-- end


---@param path string
function Title:sync(path)
	if path == nil then
		local bufpath = vim.fn.expand("%:p")
		if type(bufpath) ~= "string" then
			return
		end
    path = bufpath
	end

  local note = Note:new({
    path = path,
  })

	local title = note.title(path)
	if title == nil then
		return
	end

	local new_path = vim.fn.fnamemodify(path, ":h") .. "/" .. title .. ".md"
	if vim.fn.filereadable(new_path) == 1 then
		vim.notify("File already exists: " .. new_path, vim.log.levels.ERROR, {
			title = "Knowledge",
			timeout = 200,
		})
		return
	end

	---@type integer
	local rename_success = vim.fn.rename(path, new_path)
	if rename_success == 0 then
		vim.notify("Renamed: " .. path .. " -> " .. new_path, vim.log.levels.INFO, {
			title = "Knowledge",
			timeout = 200,
		})

		local inlinks = note.inlinks(path)
		if #inlinks > 0 then
			note.update_inlinks(path)
		end
	else
		vim.notify("Failed to rename: " .. path .. " -> " .. new_path, vim.log.levels.ERROR, {
			title = "Knowledge",
			timeout = 200,
		})
		return
	end

	-- Open the renamed file.
	vim.cmd("e " .. new_path)
end

return Title
