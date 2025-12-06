--- @class vault.Config
--- @field options vault.Config.options The plugin configuration options
--- @field setup fun(options?: vault.Config.options): nil Setup the plugin configuration
--- @field reset fun(): nil Reset configuration to default state
--- @field get_defaults fun(): vault.Config.options Get a fresh copy of default configuration
--- @field check_dirs fun(): nil Validate and check directory structure

--- @class vault.Config.options
--- @field root? string Root directory path of the vault where notes are stored. Example: "~/vault" or "/Users/user/Documents/vault"
--- @field dirs? table Directory configuration for organizing different note types
---   Example structure:
---   ```lua
---   {
---     inbox = "inbox",           -- Quick capture/inbox notes
---     docs = "_docs",           -- Documentation
---     templates = "_templates", -- Note templates
---     journal = {              -- Journal structure
---       root = "Journal",
---       daily = "Journal/Daily",
---       weekly = "Journal/Weekly",
---       monthly = "Journal/Monthly",
---       yearly = "Journal/Yearly"
---     }
---   }
---   ```
--- @field ignore? string[] Glob patterns for files/directories to ignore during searches. Example: {".git/*", ".obsidian/*", "_templates/*"}
--- @field ext? string File extension for notes. Example: ".md"
--- @field tags? table Tag configuration and validation settings. Example: { valid = { hex = true } }
--- @field search_pattern? table Regular expression patterns for parsing note elements. Example:
---   ```lua
---   {
---     task = { pcre2 = [[^\s*-\s+\[.\]\s+\S+]] },
---     date = { pcre2 = [[\d{4}-\d{2}-\d{2}]] },
---     tag = "#([A-Za-z0-9/_-]+)[\r|%s|\n|$]",
---     wikilink = "%[%[([^\\]]*)%]%]",
---     note = { type = "class::%s#class/([A-Za-z0-9_-]+)" }
---   }
---   ```
--- @field search_tool? string Tool used for searching vault. Example: "rg" or "fd"
--- @field ui? { popups: table, notify: table} UI configuration settings
--- @field notify? table Notification settings and preferences. Example: { on_write = true }
--- @field features? { cmp: boolean, commands: boolean, blink: boolean } Feature toggles for plugin components. Example: { cmp = true, commands = true, blink = true }
--- @field frontmatter? table YAML frontmatter configuration. Example: { keys = { tags = "tags" } }
--- @field check_duplicate_basename? boolean Enable duplicate filename detection. Example: true
---
--- @field telescope? table Telescope configuration. Example:
---   ```lua
---   {
---     pickers = {
---       notes = function(opts)
---         require("telescope._extensions.vault.pickers.notes")(opts)
---       end,
---     },
---   }
---   ```
--- @field telescope.pickers? table Telescope pickers configuration. Example:
---   ```lua
---   {
---     notes = function(opts)
---       require("telescope._extensions.vault.pickers.notes")(opts)
---     end,
---   }
---   ```

--- The configuration for the vault plugin.
--- @type vault.Config
--- @diagnostic disable-next-line: missing-fields
local Config = {
    --- @diagnostic disable-next-line: missing-fields
    options = {},
    --- @type boolean
    is_initialized = false,
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

    local demo_vault_root = plugin_root .. "/tests/fixtures/demo-vault"
    if vim.fn.isdirectory(demo_vault_root) == 0 then
        return nil
    end

    return demo_vault_root
end

--- Default configuration options
--- @type vault.Config.options
local DEFAULT_OPTIONS = {
    root = nil,
    dirs = nil,
    ignore = {
        ".git/*",
        ".obsidian/*",
        ".trash/*",
    },
    ext = ".md",
    frontmatter = {
        keys = {
            tags = "tags",
        },
    },
    tags = {
        valid = {
            hex = true, -- Hex is a valid tag.
        },
        completion = {
            strategy = "fuzzy", -- The strategy to use for tag completion. Default: "fuzzy"
        },
    },
    properties = {
        completion = {
            strategy = "fuzzy", -- The strategy to use for property completion. Default: "fuzzy"
        },
    },
    search_pattern = {
        task = {
            pcre2 = [[^\s*-\s+\[.\]\s+\S+]],
        },
        date = {
            pcre2 = [[\d{4}-\d{2}-\d{2}]],
            lua = "[%d%d%d%d]-[%d%d]-[%d%d]",
        },
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
    ui = {

        popups = {
            fleeting_note = {
                title = {
                    text = "Fleeting Note",
                    preview = "border", -- "border" | "prompt" | "none"
                },
                editor = { -- @see :h nui.popup
                    -- position = {
                    --     row = math.floor(vim.api.nvim_list_uis()[1].height / 2) - 9 or 0,
                    --     col = math.floor(vim.api.nvim_list_uis()[1].width / 2) - 40 or 0,
                    -- },
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
    },
    previewer = "glow", -- The previewer to use. Default: "glow"
    -- Features to enable
    features = {
        cmp = true, -- Enable cmp
        commands = true, -- Enable commands
        blink = true, -- blink.cmp inegration
    },
    telescope = {
        pickers = {
            -- custom = function(opts)
            --     require("telescope._extensions.vault.pickers.notes")(
            --         vim.tbl_deep_extend("force", opts or {}, {
            --             notes = require("vault.notes")():with_outlinks_resolved_only(),
            --         })
            --     )
            -- end,
        },
    },
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
        return nil
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

--- Validate configuration options
--- @param options vault.Config.options
--- @return boolean, string? error message if validation fails
local function validate_config(options)
    -- If root is not specified, try to use demo vault
    if not options.root then
        vim.notify("No root directory specified. Attempting to use demo vault", vim.log.levels.INFO)
        local demo_vault_root = get_demo_vault_root()
        error("TODO: implement get_demo_vault_root()")
    end

    if type(options.root) ~= "string" then
        return false, "root directory must be a string"
    end

    -- Add more specific validations
    return true
end

--- Setup the vault plugin configuration.
---
--- @param options? vault.Config.options
function Config.setup(options)
    -- Allow re-initialization with a warning
    if Config.is_initialized then
        vim.notify("Reinitializing vault.nvim configuration", vim.log.levels.INFO)
    end

    options = vim.tbl_deep_extend("force", Config.get_defaults(), options or {})

    local is_valid, err = validate_config(options)
    if not is_valid then
        error("Invalid configuration: " .. err)
    end

    options.root = expand_root(options.root)
    options.dirs = expand_dirs(options.root, options.dirs)

    --- @cast options vault.Config.options
    Config.options = options
    Config.is_initialized = true
end

--- Reset the configuration to empty state
--- This is useful for testing
function Config.reset()
    --- @diagnostic disable-next-line: missing-fields
    Config.options = {}
end

--- Get a fresh copy of default options
--- @return vault.Config.options
function Config.get_defaults()
    local defaults = vim.deepcopy(DEFAULT_OPTIONS)
    return defaults
end

--- @type vault.Config
return Config
