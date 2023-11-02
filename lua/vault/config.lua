local M = {}

---@class VaultConfig
---@field dirs table - The directories for various elements in the note.
---@field ignore string[] - List of ignore patterns in glob format (e.g., ".obdidian/*, .git/*").
---@field ext string - The extension of the note files. Default: ".md"
---@field search_pattern table - The search pattern for various elements in the note.
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
  tag = {
    valid = {
      hex = true, -- Hex is a valid tag.
    }
  },
  search_pattern = {
    tag = "#([A-Za-z0-9/_-]+)[\r|%s|\n|$]",
    wikilink = "%[%[([A-Za-z0-9/_-]+)%]%]",
  }
}

---Expand the directories in the config recursively.
---@param dirs table|nil
  local function process_dirs(dirs)
    if dirs == nil then
      return
    end
    --- if dirs.root is nil, then the user has not set the root directory.
    if dirs.root == nil then
      vim.notify("Vault: root directory is not set.", vim.log.levels.ERROR)
      return
    end

    local root_dir = vim.fn.expand(dirs.root)

    if type(root_dir) ~= "string" then
      vim.notify("Vault: root directory is not a string.", vim.log.levels.ERROR)
      return
    end

    dirs.root = root_dir

    --- Return full pathes of the directories.
    for k, v in pairs(dirs) do
      --- Skip the dirs.root.
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

---@param options table|nil
function M.setup(options)
  options = options or default_options
  --- Expand the directories recursively.
  if options.dirs == nil then
    options.dirs = default_options.dirs
  end
  options.dirs = process_dirs(options.dirs) or default_options.dirs
  M = vim.tbl_deep_extend("force", M, options)
end

M.setup()

return M
