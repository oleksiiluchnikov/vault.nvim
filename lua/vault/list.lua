local list = {}

local Log = require("plenary.log")

local config = require("vault.config")

--- Fetch list of {note_paths} from vault.
--- @param root_path string? - Root path to search from. If nil, use the vault root directory.
--- @param ignore string[]? - List of ignore patterns in glob format (e.g., ".obdidian/*, .git/*").
--- @return string[] - List of markdown files.
function list.notes_paths(root_path, ignore)
  root_path = root_path or config.dirs.root
  ignore = ignore or config.ignore
  local ext = config.ext

  ---@type string[]
	local notes_paths = {}

  local paths = vim.fn.globpath(root_path, "**/*" .. ext, true, true)

	for _, path in ipairs(paths) do
		local is_ignored = false

		for _, pattern in ipairs(ignore) do
			if vim.fn.match(path, pattern) ~= -1 then
				is_ignored = true
				break
			end
		end

		if not is_ignored then
      local note_path = path
      table.insert(notes_paths, note_path)
		end
	end

	return notes_paths
end

function list.notes_paths_with_same_filename()
  local with_same_filename = {}
  local notes_paths = list.notes_paths()
  local seen_filenames = {}
  -- Filter out notes with same filename
  for _, note_path in ipairs(notes_paths) do
    local filename = vim.fn.fnamemodify(note_path, ":t")
    if seen_filenames[filename] then
      table.insert(with_same_filename, note_path)
    else
      seen_filenames[filename] = true
    end
  end
  return with_same_filename
end


---List all roots of nested tags. e.g., #foo/bar/baz -> #foo, #foo/bar
---@return string[]?
function list.root_tags()
  local root_dir = config.dirs.root

  local notes_paths = list.notes_paths(root_dir, config.ignore)
  if #notes_paths == 0 then
    Log.error("No notes found in vault: " .. root_dir)
    return
  end

  local unique_entries = {}
  local seen_entries = {}

  for _, note_path in ipairs(notes_paths) do
    local f = io.open(note_path, "r")
    if f then
      local content = f:read("*all")
      f:close()

      for tag_root in content:gmatch(config.search_pattern.tag .. "/") do
        if not seen_entries[tag_root] then
          seen_entries[tag_root] = true
          table.insert(unique_entries, tag_root)
        end
      end
    end
  end
  return unique_entries
end




---@param tags Tag[]
---@return Tag[]
function list.unique_tags(tags)
	-- Remove duplicate tags
	local unique_tags = {}
	local seen_tags = {} -- To track seen tags
	for _, tag in ipairs(tags) do
		if not seen_tags[tag.value] then
			seen_tags[tag.value] = true
			table.insert(unique_tags, tag)
		else
			for _, unique_tag in ipairs(unique_tags) do
				if unique_tag.value == tag.value then
					if not vim.tbl_contains(unique_tag.notes_paths, tag.notes_paths[1]) then
						table.insert(unique_tag.paths, tag.notes_paths[1])
					end
				end
			end
		end
	end
	return unique_tags
end

function list.test()
	vim.cmd("lua package.loaded['vault.list'] = nil")
	vim.cmd("lua package['vault.list'] = nil")

  local root_tags = list.root_tags()
  print(vim.inspect(root_tags))
end


return list
