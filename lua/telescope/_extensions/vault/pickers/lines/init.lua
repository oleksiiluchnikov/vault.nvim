--- lines picker
return function(opts)
    local vault_state = require("vault.core.state")
    local entry_display = require("telescope.pickers.entry_display")
    local finders = require("telescope.finders")
    local pickers = require("telescope.pickers")
    local sorters = require("telescope.sorters")
    local Log = require("plenary.log")
    local Error = require("vault.utils.error")
    local utils = require("vault.utils")
    local vault_previewers = require("telescope._extensions.vault.previewers")
    local vault_mappings = require("telescope._extensions.vault.mappings")
    local vault_layouts = require("telescope._extensions.vault.layouts")
    opts = opts or {}
    opts.lines = opts.lines or require("vault.lines")()
    local lines_list = opts.lines:list()
    if next(lines_list) == nil then
        Log.info("No lines found in vault")
        return
    end

    local steps = math.min(64, vim.tbl_count(lines_list))
    local hl_name = "VaultLine"
    --- @type table|nil
    local colors = nil
    do
        local ok, maybe_colors = pcall(function()
            local Gradient = require("gradient")
            return Gradient.from_stops(steps, "Comment", "Normal", "String")
        end)
        if ok and type(maybe_colors) == "table" then
            colors = maybe_colors
            for i, color in ipairs(colors) do
                pcall(vim.api.nvim_set_hl, 0, hl_name .. tostring(i), { fg = color })
            end
        end
    end

    -- Calculate max widths for various columns
    local max_widths = {
        content = 60,
        tags = 20,
        wikilinks = 20,
        metadata = 30,
        count = 5,
    }

    local screen_width = vim.api.nvim_list_uis()[1].width
    local remaining_width = screen_width - max_widths.count - 8 -- 8 for separators and padding

    -- Adjust content width based on available space
    max_widths.content = math.min(max_widths.content, math.floor(remaining_width * 0.5))
    max_widths.tags = math.min(max_widths.tags, math.floor(remaining_width * 0.15))
    max_widths.wikilinks = math.min(max_widths.wikilinks, math.floor(remaining_width * 0.15))
    max_widths.metadata = math.min(max_widths.metadata, math.floor(remaining_width * 0.2))

    --- Format metadata as key-value string
    --- @param metadata table
    --- @return string
    local function format_metadata(metadata)
        if not metadata or vim.tbl_isempty(metadata) then
            return ""
        end
        local parts = {}
        for k, v in pairs(metadata) do
            table.insert(parts, string.format("%s:%s", k, v))
        end
        return table.concat(parts, " ")
    end

    --- Format tags list
    --- @param tags string[]
    --- @return string
    local function format_tags(tags)
        if not tags or vim.tbl_isempty(tags) then
            return ""
        end
        return table.concat(tags, " ")
    end

    --- Format wikilinks list
    --- @param wikilinks string[]
    --- @return string
    local function format_wikilinks(wikilinks)
        if not wikilinks or vim.tbl_isempty(wikilinks) then
            return ""
        end
        return table.concat(wikilinks, " ")
    end

    --- Truncate string with ellipsis
    --- @param str string
    --- @param max number
    --- @return string
    local function truncate(str, max)
        if #str > max then
            return str:sub(1, max - 3) .. "..."
        end
        return str
    end

    --- @param entry vault.TelescopeEntry
    local make_display = function(entry)
        --- @type vault.Line
        local line = entry.value
        local sources_count = line.data.count

        -- Calculate gradient index based on source count
        local content_hl = "TelescopeResultsNormal"
        if colors then
            local i = math.min(math.floor(sources_count / 2), steps)
            if i == 0 then
                i = 1
            end
            content_hl = hl_name .. tostring(i)
        end

        -- Prepare display columns
        local content = truncate(line.data.content, max_widths.content)
        local metadata = truncate(format_metadata(line.data.metadata), max_widths.metadata)
        local tags = truncate(format_tags(line.data.tags), max_widths.tags)
        local wikilinks = truncate(format_wikilinks(line.data.wikilinks), max_widths.wikilinks)
        local count = tostring(sources_count)

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
            { content, content_hl },
            { metadata, "Comment" },
            { tags, "Special" },
            { wikilinks, "Type" },
            { count, "Number" },
        })
    end

    --- @param line vault.Line
    --- @return vault.TelescopeEntry
    local entry_maker = function(line)
        -- Create searchable ordinal combining all fields
        local ordinal = table.concat({
            line.data.content,
            format_metadata(line.data.metadata),
            format_tags(line.data.tags),
            format_wikilinks(line.data.wikilinks),
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

    local on_input_filter_cb = function(prompt)
        local picker = vault_state.get_global_key("picker")
        local is_negative = false

        local function default_finder()
            local new_finder = finders.new_table({
                results = lines_list,
                entry_maker = entry_maker,
            })

            picker.finder:close()
            picker.finder = new_finder

            vault_state.set_global_key("prompt", prompt)
            return {
                prompt = prompt or "",
            }
        end

        if prompt:sub(-1) ~= "/" then
            return default_finder()
        end

        if prompt:sub(1, 1) == "-" then
            is_negative = true
        end

        local pattern = prompt:sub(1, -2)
        pattern = pattern:sub(2)
        if is_negative == true then
            pattern = pattern:sub(2)
        end
        local new_results = {}
        local results_without_excluded = {}

        for _, entry in ipairs(picker.finder.results) do
            local line = entry.value
            local search_text = line.data.content
            if search_text == nil then
                goto continue
            end
            local is_valid_regex = pcall(vim.fn.match, search_text, pattern)
            if is_valid_regex == false then
                goto continue
            end
            if vim.fn.match(search_text, pattern) ~= -1 then
                table.insert(new_results, line)
                if is_negative == true then
                    table.insert(results_without_excluded, line)
                end
            end
            ::continue::
        end
        if next(new_results) == nil then
            return default_finder()
        elseif is_negative == true then
            new_results = {}
            for _, entry in ipairs(picker.finder.results) do
                if not vim.tbl_contains(results_without_excluded, entry.value) then
                    table.insert(new_results, entry.value)
                end
            end
        end

        local new_finder = finders.new_table({
            results = new_results,
            entry_maker = entry_maker,
        })
        picker.finder:close()
        picker.finder = new_finder

        vault_state.set_global_key("prompt", prompt)

        return {
            prompt = "",
        }
    end

    local picker = pickers.new(opts, {
        prompt_title = "Lines",
        finder = finder,
        sorter = sorters.get_fzy_sorter(),
        attach_mappings = require("telescope._extensions.vault.mappings").lines,
        on_input_filter_cb = on_input_filter_cb,
        layout_config = {
            width = screen_width,
        },
    })
    vault_state.set_global_key("picker", picker)
    return picker
end
