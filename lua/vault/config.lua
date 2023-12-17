local Object = require("vault.core.object")

---@class VaultConfig
local Config = {}

---@class VaultConfig.options
---@field root string - The root directory of the vault.
---@field dirs table? - The directories for various elements in the note.
---@field ignore string[] - List of ignore patterns in glob format (e.g., ".obdidian/*, .git/*").
---@field ext string - The extension of the note files. Default: ".md"
---@field tags table - The tag configuration.
---@field search_pattern table - The search pattern for various elements in the note.
---@field search_tool string - The search tool to use. Default: "rg"
---@field popups table - The popup configuration.
---@field notify table - The notification configuration.
local default_options = {
    root = "~/knowledge", -- The root directory of the vault.
    dirs = {
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
        ".trash/*",
    },
    ext = ".md",
    tags = {
        valid = {
            hex = true, -- Hex is a valid tag.
        },
    },
    search_pattern = {
        tag = "#([A-Za-z0-9/_-]+)[\r|%s|\n|$]",
        wikilink = "%[%[([^\\]]*)%]%]",
        note = {
            type = "class::%s#class/([A-Za-z0-9_-]+)",
        },
    },
    search_tool = "rg", -- The search tool to use. Default: "rg"
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

--- Expand the root directory path.
---
---@param root VaultPath.root - The root directory.
---@return VaultPath.root - The expanded root directory.
local function expand_root(root)
    -- Expand the root directory. If the root directory is relative, then expand
    if root:sub(1, 1) == "~" then
        local expanded_root = vim.fn.expand(root)
        if type(expanded_root) ~= "string" or expanded_root == "" then
            error(
                "Invalid root directory: "
                    .. vim.inspect(root)
                    .. ". Please set a path to the root directory at the `root` option."
            )
        end
        root = expanded_root
    end

    return root
end

--- Expand the directories in the config recursively.
---
---@param dirs table? - The directories to expand.
---@return table? - The expanded directories.
local function expand_dirs(root, dirs)
    if dirs == nil then
        error("Implement default dirs")
        return
    end
    -- Expand the directories.
    for key, dir in pairs(dirs) do
        if type(dir) == "string" then
            if dir:find(root, 1, true) == 1 then
                dirs[key] = vim.fn.expand(dir)
            else
                dirs[key] = vim.fn.expand(root .. "/" .. dir)
            end
        elseif type(dir) == "table" then
            dirs[key] = expand_dirs(root, dir)
        end
    end
    return dirs
end

--- Setup the vault plugin configuration.
---
---@param options VaultConfig.options? - The configuration options.
function Config.setup(options)
    options = vim.tbl_deep_extend("force", default_options, options or {})
    local root = expand_root(options.root)
    if type(root) ~= "string" or root == "" then
        error(
            "Invalid root directory: "
                .. vim.inspect(options.root)
                .. ". Please set a absolute path to the root directory."
        )
    end
    options.root = root

    local dirs = options.dirs or {}
    options.dirs = expand_dirs(root, dirs)
    Config = vim.tbl_deep_extend("force", Config, options)
end

Config.setup()

---@type VaultConfig.options
return Config
