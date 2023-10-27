local M = {}

---@class VaultConfig
---@field dirs table - The directories for various elements in the note.
---@field ignore string[] - List of ignore patterns in glob format (e.g., ".obdidian/*, .git/*").
---@field ext string - The extension of the note files. Default: ".md"
---@field search_pattern table - The search pattern for various elements in the note.
local default_options = {
  dirs = {
    root = "~/knowledge",
    inbox = "~/knowledge/inbox",
    docs = "~/knowledge/_docs",
    templates = "~/knowledge/_templates",
    journal = {
      root = "~/knowledge/Journal",
      daily = "~/knowledge/Journal/Daily",
      weekly = "~/knowledge/Journal/Weekly",
      monthly = "~/knowledge/Journal/Monthly",
      yearly = "~/knowledge/Journal/Yearly",
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
---@param dirs table
  local function expand_dirs(dirs)
    if dirs == nil then
      return
    end
    for k, v in pairs(dirs) do
      if type(v) == "string" and v:sub(1, 1) == "~" then
        dirs[k] = vim.fn.expand(v)
      elseif type(v) == "table" then
        expand_dirs(v)
      end
    end
end

---@param options table|nil
function M.setup(options)
  options = options or default_options
  expand_dirs(options.dirs)
  M = vim.tbl_deep_extend("force", M, options)
end

M.setup()

return M
