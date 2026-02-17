return function(opts)
    local finders = require("telescope.finders")
    local pickers = require("telescope.pickers")
    local sorters = require("telescope.sorters")
    local entry_display = require("telescope.pickers.entry_display")
    local vault_state = require("vault.core.state")
    local Log = require("plenary.log")
    local available_pickers = {
        { name = "notes", description = "Browse and search through all notes" },
        { name = "tasks", description = "Search and manage tasks across notes" },
        { name = "properties", description = "Search for properties and values" },
        { name = "dirs", description = "Browse notes by directory structure" },
        { name = "orphans", description = "Find notes without internal links" },
        { name = "tags", description = "Search and navigate through tags" },
        { name = "links", description = "Find and navigate between linked notes" },
        { name = "wikilinks", description = "Find notes linking to current note" },
        { name = "bases", description = "Browse Obsidian base database views" },
    }
    -- extend available pickers with vault pickers
    local vault_pickers = require("telescope._extensions.vault.pickers")
    for name, _ in pairs(vault_pickers) do
        table.insert(available_pickers, { name = name, description = "" })
    end

    -- -- get pickers from the plugin's data
    -- local plugin_dir = vim.fn.stdpath("data")
    --     .. "/lazy/vault.nvim/telescope/_extensions/vault/pickers"
    -- if not vim.uv.fs_stat(plugin_dir) then
    --     Log:error("vault.nvim is not installed")
    --     return
    -- end
    --
    -- for _, picker in ipairs(vim.fn.glob(plugin_dir .. "/*", false, true)) do
    --     local name = vim.fn.fnamemodify(picker, ":t")
    --     if name ~= "init.lua" then
    --         table.insert(available_pickers, { name = name, description = "" })
    --     end
    -- end
    --
    local vault_layouts = require("telescope._extensions.vault.layouts")
    local vault_actions = require("telescope._extensions.vault.actions")
    opts = opts or {}

    -- Calculate optimal widths based on content
    local widths = {
        name = 0,
        description = 0,
    }

    -- Find maximum widths
    for _, picker in ipairs(available_pickers) do
        widths.name = math.max(widths.name, vim.fn.strdisplaywidth(picker.name))
        widths.description =
            math.max(widths.description, vim.fn.strdisplaywidth(picker.description))
    end

    -- Add some padding
    widths.name = widths.name + 2

    local results = available_pickers

    local make_display = function(entry)
        local displayer = entry_display.create({
            separator = " ",
            items = {
                { width = widths.name },
                { remaining = true },
            },
        })

        return displayer({
            { entry.value.name, "TelescopeResultsNormal" },
            { entry.value.description, "Comment" },
        })
    end

    local entry_maker = function(entry)
        return {
            value = entry,
            ordinal = entry.name,
            display = make_display,
        }
    end

    local finder = finders.new_table({
        results = results,
        entry_maker = entry_maker,
    })
    local number_of_pickers = vim.tbl_count(available_pickers) + 5

    opts = vim.tbl_deep_extend("force", opts, vault_layouts.mini())
    -- Calculate total width needed for the layout
    local total_width = widths.name + widths.description + 5 -- 5 for padding and separator

    opts = vim.tbl_deep_extend("force", opts, {
        layout_config = {
            height = number_of_pickers,
            width = math.min(total_width, math.floor(vim.o.columns * 0.8)), -- Cap at 80% of screen width
        },
        sorting_strategy = "ascending",
        results_title = false,
        border = true,
        borderchars = {
            prompt = { "─", "│", " ", "│", "╭", "╮", "│", "│" },
            results = { "─", "│", "─", "│", "├", "┤", "╯", "╰" },
        },
    })

    local picker = pickers.new(opts, {
        prompt_title = "",
        finder = finder,
        sorter = sorters.get_fzy_sorter(),
        attach_mappings = function(_, map)
            local vault_picker_actions =
                require("telescope._extensions.vault.pickers.vault.actions")
            local actions = require("telescope.actions")
            map("i", "<C-c>", vault_actions.close)
            map("n", "<C-c>", vault_actions.close)

            map("i", "<CR>", vault_picker_actions.find)
            map("n", "<CR>", vault_picker_actions.find)

            map("i", "<C-s>", vault_actions.resort)
            map("n", "<C-s>", vault_actions.resort)

            -- select all entries in the picker
            map("i", "<C-a>", actions.select_all)
            map("n", "<C-a>", actions.select_all)

            map("i", "<C-d>", actions.drop_all)
            map("n", "<C-d>", actions.drop_all)

            return true
        end,
    })
    vault_state.set_global_key("picker", picker)
    return picker
end
