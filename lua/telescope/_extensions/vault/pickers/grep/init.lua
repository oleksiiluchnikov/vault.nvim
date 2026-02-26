-- Live Grep across all notes
--- @param opts table
--- @return Picker
return function(opts)
    opts = opts or {}
    local config = require("vault.config")
    local root_dir = vim.fn.expand(config.options.root)
    local screen_width = vim.api.nvim_list_uis()[1].width
    local screen_height = vim.api.nvim_list_uis()[1].height
    local default_opts = {
        prompt_title = "Search in notes",
        -- layout_strategy = "vertical",
        layout_config = {
            width = screen_width - 4,
            height = screen_height - 4,
            prompt_position = "top",
            preview_cutoff = 120,
        },
        cwd = root_dir,
        glob_pattern = "**/*.md",
        search = opts.query or "",
    }

    -- merge opts with default opts
    opts = vim.tbl_deep_extend("force", default_opts, opts or {})
    -- require("telescope.builtin").live_grep(opts)
    local picker = require("telescope.builtin").live_grep(opts)
    return picker
end
