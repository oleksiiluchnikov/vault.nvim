---@class VaultConfig
---@field dirs table - The directories for various elements in the note.
---@field ignore string[] - List of ignore patterns in glob format (e.g., ".obdidian/*, .git/*").
---@field ext string - The extension of the note files. Default: ".md"
---@field tags table - The tag configuration.
---@field search_pattern table - The search pattern for various elements in the note.
---@field popups table - The popup configuration.
---@field notify table - The notification configuration.
local Config = {}

---Expand the directories in the config recursively.
---@param dirs table? - The directories to expand.
---@return table? - The expanded directories.
local function process_dirs(dirs)
	if dirs == nil then
		return
	end
	---if dirs.root is nil, then the user has not set the root directory.
	if dirs.root == nil then
		error("Vault: root directory is not set.")
		return
	end

	local root_dir = vim.fn.expand(dirs.root)

	if type(root_dir) ~= "string" then
		error("Vault: root directory is not a string.")
		return
	end

	dirs.root = root_dir

	-- Return full pathes of the directories.
	for k, v in pairs(dirs) do
		-- Skip the dirs.root.
		if k ~= "root" then
			if type(v) == "string" then
				dirs[k] = root_dir .. "/" .. v
			elseif type(v) == "table" then
				process_dirs(v)
			end
		end
	end

	return dirs
end

---@type VaultConfig
local default_options = {
	dirs = {
		root = "~/knowledge",
		inbox = "inbox",
		docs = "_docs",
		templates = "_templates",
		journal = {
			root = "Journal",
			daily = "Journal/Daily",
			weekly = "Journal/Weekly",
			monthly = "Journal/Monthly",
			yearly = "Journal/Yearly",
		},
	},
	ignore = {
		".git/*",
		".obsidian/*",
		"_docs/*",
		"_templates/*",
	},
	ext = ".md",
	tags = {
		valid = {
			hex = true, -- Hex is a valid tag.
		},
	},
	search_pattern = {
		tag = "#([A-Za-z0-9/_-]+)[\r|%s|\n|$]",
		wikilink = "%[%[([A-Za-z0-9/_-]+)%]%]",
		note = {
      type = "class::%s#class/([A-Za-z0-9_-]+)",
    },
	},
  notify = {
    on_write = true,
  },
	popups = {
		fleeting_note = {
			title = {
				text = "Fleeting Note",
				preview = "border", -- "border" | "prompt" | "none"
			},
			editor = { -- @see :h nui.popup
				position = {
					row = math.floor(vim.o.lines / 2) - 9,
					col = math.floor(vim.o.columns / 2) - 40,
				},
				size = {
					height = 6,
					width = 80,
				},
				enter = true,
				focusable = true,
				zindex = 60,
				relative = "editor",
				border = {
					padding = {
						top = 0,
						bottom = 0,
						left = 0,
						right = 0,
					},
					-- T shape side border: ├
					style = "rounded",
				},
				buf_options = {
					modifiable = true,
					readonly = false,
					filetype = "markdown",
					buftype = "nofile",
					swapfile = false,
					bufhidden = "wipe",
				},
				win_options = {
					winhighlight = "Normal:Normal,FloatBorder:FloatBorder",
				},
			},
			prompt = {
				hidden = true,
				size = {
					height = 0.8,
					width = 0.8,
				},
			},
			results = {
				size = {
					height = 10,
					width = 80,
				},
			},
		},
	},
}

---@param options table? - The options to set.
function Config.setup(options)
	options = options or default_options
	if options.dirs == nil then
		options.dirs = default_options.dirs
	end
	--Expand the directories recursively.
	options.dirs = process_dirs(options.dirs) or default_options.dirs

	Config = options
end

Config.setup()

return Config
