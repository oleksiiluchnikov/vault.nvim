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
--- @field log? vault.LogConfig Centralized logging configuration. Example: { level = "debug", file = true }
--- @field features? { cmp: boolean, commands: boolean, blink: boolean } Feature toggles for plugin components. Example: { cmp = true, commands = true, blink = true }
--- @field frontmatter? table YAML frontmatter configuration. Example: { keys = { tags = "tags" } }
--- @field check_duplicate_basename? boolean Enable duplicate filename detection. Example: true
--- @field wikilinks? { confirm_rewrite?: boolean, confirm_merge?: boolean, confirm_create?: boolean } Wikilink action confirmation settings
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
    root = "~/knowledge",
    dirs = nil,
    ignore = {
        ".git/*",
        ".obsidian/*",
        ".trash/*",
        "node_modules/*",
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
    process = {
        columns = { "slug", "title", "status", "tags" }, -- Default columns for :Vault process
        --- @type vault.RowHlRule[]|fun(record: table, row_idx: integer): string|nil
        --- Row highlight rules applied top-to-bottom; first match wins.
        --- Each rule: { match = { field = value|{} }, hl = "HlGroup" }
        --- Or a function(record, row_idx) -> hl_group|nil for full control.
        row_hl = {
            { match = { status = "done" },     hl = "VaultRowDone" },
            { match = { status = "archived" }, hl = "VaultRowDone" },
            { match = { tags = {} },           hl = "VaultRowUntagged" },
        },
    },
    kanban = {
        group_field = "status",                          -- Frontmatter field, "tags/<prefix>", or "directory"
        display_fields = { "title", "tags" },            -- Fields shown on each card
        group_values = nil,                              --- @type string[]|nil Ordered column values (nil = auto-derive)
        render_mode = "card",                            -- "card" (bordered multi-line) or "table" (single-line rows)
        layout = {
            width_ratio = 0.95,
            height_ratio = 0.90,
            column_gap = 1,
            min_column_width = 25,
        },
    },
    calendar = {
        date_field = "due",                              -- Frontmatter key for date placement (or "file.ctime"/"file.mtime")
        link_date_fields = { "due" },                    -- Fields stored as Daily note wikilinks ([[YYYY-MM-DD Weekday]])
        end_date_field = nil,                            --- @type string|nil  Frontmatter key for range end date (enables date ranges)
        primary_field = "title",                         -- Field displayed on calendar cards
        display_fields = nil,                            --- @type string[]|nil Multi-line card fields (nil = primary_field only)
        first_day = 1,                                   -- First day of week: 0=Sun, 1=Mon
        max_cards_per_cell = 3,                          -- Max records shown per day cell before "+N more"
        hour_start = 8,                                  -- First hour in timetable view (week mode)
        hour_end = 18,                                   -- Last hour in timetable view (week mode)
        empty_cell = nil,                                --- @type string|nil Override empty cell symbol (nil = use bases.empty_cell)
        keymaps = {},                                    --- @type table<string, string|false> Keymap overrides (set key to false to disable)
    },
    task_notes = {
        dir = "Tasks",
        status_field = "status",
        priority_field = "priority",
        blocked_by_field = "blocked_by",
        default_status = "[[Status - Backlog]]",
        default_executor = "[[Executor - Human]]",
        default_category = "[[Category - Green Task]]",
        default_priority = "[[Priority - Medium]]",
        status_order = {
            "Status - Backlog",
            "Status - Todo",
            "Status - In-Progress",
            "Status - In-Review",
            "Status - Done",
            "Status - Failed",
            "Status - Deprecated",
            "Status - Archived",
        },
    },
    notify = {
        on_write = true,
    },
    log = {
        level = "info",    --- @type vault.LogLevel Minimum level for vim.notify display
        file = false,      --- Write all levels to log file (stdpath("cache")/vault.log)
        file_path = nil,   --- Override log file path
        on_message = nil,  --- fun(level, scope, msg) callback for programmatic access
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

    features = {
        cmp = true,
        commands = true,
        blink = true,
        watcher = false, -- NEW: Enable file watcher
    },

    watcher = {
        enabled = false,
        debounce_ms = 500, -- Debounce delay for batch processing
        auto_update_links = true, -- Automatically update wikilinks
        notify_on_rename = true, -- Show notifications for renames
        watch_external = true, -- Watch for external file changes
        async_rename = true, -- Use async background processing for renames
        -- When true, ask the user for confirmation before applying link updates
        prompt_on_rename = false,
        -- Frontmatter key to update on rename (e.g. `slug`). If nil, no frontmatter changes are made.
        frontmatter_key = "slug",
    },

    wikilinks = {
        --- Confirm before rewriting [[old]] -> [[new]] across the vault.
        --- When true, shows how many files will be affected and asks for confirmation.
        confirm_rewrite = true,
        --- Confirm before merging two notes (absorb + trash + rewrite links).
        confirm_merge = true,
        --- Confirm before creating a new note from an unresolved wikilink.
        confirm_create = false,
    },

    bases = {
        ext = ".base", -- File extension for base files
        dirs = nil, -- Specific directories to scan for .base files (nil = scan entire vault)
        empty_cell = "_", --- Symbol displayed for nil/empty cells in process buffer
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
local function split_path(p)
    local parts = {}
    for part in string.gmatch(p or "", "[^/]+") do
        parts[#parts + 1] = part
    end
    return parts
end

local function resolve_case_sensitive_path(base, rel)
    if rel == nil or rel == "" then
        return base
    end
    local current = base
    for _, comp in ipairs(split_path(rel)) do
        local found = nil
        local ok, entries = pcall(vim.fn.readdir, current)
        if ok and type(entries) == "table" then
            for _, entry in ipairs(entries) do
                if entry:lower() == comp:lower() then
                    found = entry
                    break
                end
            end
        end
        if found then
            current = current .. "/" .. found
        else
            current = current .. "/" .. comp
        end
    end
    return current
end

local function expand_dirs(root, dirs)
    if dirs == nil then
        return nil
    end

    for key, dir in pairs(dirs) do
        if type(dir) == "string" then
            local candidate = nil

            if dir:find(root, 1, true) == 1 then
                -- dir already contains root; resolve the relative part to canonical case
                local rel = dir:sub(#root + 2)
                candidate = resolve_case_sensitive_path(root, rel)
                if vim.fn.isdirectory(candidate) == 0 then
                    -- fallback: use the unexpanded concatenation
                    candidate = vim.fn.expand(dir)
                end
            else
                -- Always resolve to canonical filesystem case (handles case-insensitive macOS)
                candidate = resolve_case_sensitive_path(root, dir)
                if vim.fn.isdirectory(candidate) == 0 then
                    -- fallback to expanded path (even if non-existent)
                    candidate = vim.fn.expand(root .. "/" .. dir)
                end
            end

            dirs[key] = candidate
        elseif type(dir) == "table" then
            dirs[key] = expand_dirs(root, dir)
        end
    end

    return dirs
end

--- Safely access a nested directory config value.
--- @param key string Dot-separated key path (e.g. "journal.daily", "docs", "inbox")
--- @return string|nil The directory path, or nil if not configured
function Config.dir(key)
    local dirs = Config.options.dirs
    if not dirs then
        return nil
    end
    for part in key:gmatch("[^%.]+") do
        if type(dirs) ~= "table" then
            return nil
        end
        dirs = dirs[part]
        if not dirs then
            return nil
        end
    end
    if type(dirs) ~= "string" then
        return nil
    end
    return dirs
end

--- Check each dir for existence and replace with root if not found.
function Config.check_dirs()
    local root = Config.options.root
    local dirs = Config.options.dirs
    if not dirs then
        return
    end
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
        require("vault.log").scope("config").info("No root directory specified. Attempting to use demo vault")
        local demo_vault_root = get_demo_vault_root()
        if demo_vault_root then
            options.root = demo_vault_root
        else
            return false, "root directory must be specified"
        end
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
        require("vault.log").scope("config").info("Reinitializing vault.nvim configuration")
    end

    local defaults = Config.get_defaults()
    local user_options = options or {}
    local merged = vim.tbl_deep_extend("force", defaults, user_options)

    -- Ensure default ignore patterns are always present (user patterns are additive)
    if user_options.ignore then
      local seen = {}
      local combined = {}
      for _, pat in ipairs(defaults.ignore) do
        if not seen[pat] then seen[pat] = true; table.insert(combined, pat) end
      end
      for _, pat in ipairs(user_options.ignore) do
        if not seen[pat] then seen[pat] = true; table.insert(combined, pat) end
      end
      merged.ignore = combined
    end

    local is_valid, err = validate_config(merged)
    if not is_valid then
        error("Invalid configuration: " .. err)
    end

    -- Only expand the root if user provided a custom root explicitly
    if user_options.root ~= nil then
        merged.root = expand_root(merged.root)
    end

    merged.dirs = expand_dirs(merged.root, merged.dirs)

    --- @cast merged vault.Config.options
    Config.options = merged
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
