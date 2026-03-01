--- lines picker
return function(opts)
    local vault_state = require("vault.core.state")
    local entry_display = require("telescope.pickers.entry_display")
    local finders = require("telescope.finders")
    local pickers = require("telescope.pickers")
    local sorters = require("telescope.sorters")
    local Log = require("plenary.log")
    local vault_mappings = require("telescope._extensions.vault.mappings")
    local vault_hl = require("telescope._extensions.vault.highlights")
    local make_filter = require("telescope._extensions.vault.on_input_filter")

    opts = opts or {}
    opts.lines = opts.lines or require("vault.lines")()
    local lines_list = opts.lines:list()
    if next(lines_list) == nil then
        Log.info("No lines found in vault")
        return
    end

    local steps = math.min(64, vim.tbl_count(lines_list))
    local hl_name = "VaultLine"
    local colors = vault_hl.setup(hl_name, steps, { "Comment", "Normal", "String" })

    local screen_width = vim.api.nvim_list_uis()[1].width
    local max_widths = {
        content = math.min(60, math.floor((screen_width - 13) * 0.5)),
        tags = math.min(20, math.floor((screen_width - 13) * 0.15)),
        wikilinks = math.min(20, math.floor((screen_width - 13) * 0.15)),
        metadata = math.min(30, math.floor((screen_width - 13) * 0.2)),
        count = 5,
    }

    local function format_metadata(metadata)
        if not metadata or vim.tbl_isempty(metadata) then return "" end
        local parts = {}
        for k, v in pairs(metadata) do
            table.insert(parts, string.format("%s:%s", k, v))
        end
        return table.concat(parts, " ")
    end

    local function format_list(items)
        if not items or vim.tbl_isempty(items) then return "" end
        return table.concat(items, " ")
    end

    local function truncate(str, max)
        if #str > max then return str:sub(1, max - 3) .. "..." end
        return str
    end

    local make_display = function(entry)
        local line = entry.value
        local sources_count = line.data.count

        local content_hl = "TelescopeResultsNormal"
        if colors then
            local i = math.min(math.floor(sources_count / 2), steps)
            if i == 0 then i = 1 end
            content_hl = hl_name .. tostring(i)
        end

        local displayer = entry_display.create({
            separator = " │ ",
            items = {
                { width = max_widths.content },
                { width = max_widths.metadata },
                { width = max_widths.tags },
                { width = max_widths.wikilinks },
                { width = max_widths.count },
            },
        })

        return displayer({
            { truncate(line.data.content, max_widths.content), content_hl },
            { truncate(format_metadata(line.data.metadata), max_widths.metadata), "Comment" },
            { truncate(format_list(line.data.tags), max_widths.tags), "Special" },
            { truncate(format_list(line.data.wikilinks), max_widths.wikilinks), "Type" },
            { tostring(sources_count), "Number" },
        })
    end

    local entry_maker = function(line)
        local ordinal = table.concat({
            line.data.content,
            format_metadata(line.data.metadata),
            format_list(line.data.tags),
            format_list(line.data.wikilinks),
        }, " ")

        return {
            value = line,
            ordinal = ordinal,
            display = make_display,
        }
    end

    local finder = finders.new_table({
        results = lines_list,
        entry_maker = entry_maker,
    })

    local picker = pickers.new(opts, {
        prompt_title = "Lines",
        finder = finder,
        sorter = sorters.get_fzy_sorter(),
        attach_mappings = vault_hl.make_attach_mappings(vault_mappings.lines, hl_name, colors),
        on_input_filter_cb = make_filter(lines_list, entry_maker),
        layout_config = { width = screen_width },
    })
    vault_state.set_global_key("picker", picker)
    return picker
end
