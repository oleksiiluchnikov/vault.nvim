--- The configuration for the vault plugin.
--- @class vault.Config
--- @field options vault.Config.options
--- @field setup fun(options: vault.Config.options): nil
local Config = {
    --- @diagnostic disable-next-line: missing-fields
    options = {},
}

--- Get the root directory for the demo vault
---
--- Finds the runtime path of the current plugin, then checks for the
--- existence of the demo vault folder under it.
--- @return vault.Config.options.root|nil - The root directory of the demo vault.
local function get_demo_vault_root()
    --- Get the runtime path for this plugin
    --- @type string[]
    local init_lua = vim.api.nvim_get_runtime_file("", true)

    --- The detected root path of the plugin
    --- @type string|nil
    local plugin_root = nil

    --- Check each returned path to find the plugin root
    for _, path in ipairs(init_lua) do
        if path:find("vault.nvim") then
            plugin_root = path
            break
        end
    end
    if plugin_root == nil then
        return nil
    end

    local demo_vault_root = plugin_root .. "/demo_vault"
    if vim.fn.isdirectory(demo_vault_root) == 0 then
        return nil
    end

    return demo_vault_root
end

-- --- @type VaultConfig.options.root|nil
-- local demo_vault_root = get_demo_vault_root()
-- if demo_vault_root == nil then
--     error("Unable to find demo vault root")
-- end

--- @class vault.Config.options
--- @field root string - The root directory of the vault.
--- @field dirs? table - The directories for various elements in the note.
--- @field ignore string[] - List of ignore patterns in glob format (e.g., ".obdidian/*, .git/*").
--- @field ext string - The extension of the note files. Default: ".md"
--- @field tags table - The tag configuration.
--- @field search_pattern table - The search pattern for various elements in the note.
--- @field search_tool string - The search tool to use. Default: "rg"
--- @field popups table - The popup configuration.
--- @field notify table - The notification configuration.
--- @field commands boolean - Whether to setup the commands. Default: true
--- @field cmp boolean - Whether to setup the cmp completion. Default: true
Config.defaults = {
    root = "~/knowledge",
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
    check_duplicate_basename = true,
    popups = {
        fleeting_note = {
            title = {
                text = "Fleeting Note",
                preview = "border", -- "border" | "prompt" | "none"
            },
            editor = {              -- @see :h nui.popup
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
    cmp = true,
    commands = true,
}

--- Expand the root directory path.
---
--- @param root vault.Config.options.root - The root directory.
--- @return vault.Config.options.root - The expanded root directory.
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
--- @param dirs? table - The directories to expand.
--- @return table? - The expanded directories.
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

--- Check each dir for existence and replace with root if not found.
function Config.check_dirs()
    local root = Config.options.root
    local dirs = Config.options.dirs
    for key, dir in pairs(dirs) do
        if type(dir) == "string" then
            if vim.fn.isdirectory(dir) == 0 then
                dirs[key] = root .. "/" .. dir
            end
        elseif type(dir) == "table" then
            dirs[key] = expand_dirs(root, dir)
        end
    end
    Config.options.dirs = dirs
end

--- Setup the vault plugin configuration.
---
--- @param options? vault.Config.options
function Config.setup(options)
    options = vim.tbl_deep_extend("force", Config.options, options)
    if not options then
        error("Failed to load `vault.nvim` configuration.")
    end
    --- @type vault.Config.options.root
    options.root = expand_root(options.root)
    options.dirs = expand_dirs(options.root, options.dirs)

    -- Validate the options.
    vim.validate({
        root = { options.root, "string" },
        dirs = { options.dirs, "table" },
        ignore = { options.ignore, "table" },
        ext = { options.ext, "string" },
        tags = { options.tags, "table" },
        search_pattern = { options.search_pattern, "table" },
        search_tool = { options.search_tool, "string" },
        notify = { options.notify, "table" },
        popups = { options.popups, "table" },
    })

    --- @cast options vault.Config.options
    Config.options = options
end

Config.setup(Config.defaults)

--- @type vault.Config.options
return Config
