--- @class telescope_popup_options.vault.Tags: telescope_popup_options
--- @field tags? vault.Tags

--- Search for tags
--- @param opts? telescope_popup_options.vault.Tags
--- @return Picker
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
    opts.tags = opts.tags or require("vault.tags")()

    --- @type vault.Tags.list
    local tags_list = opts.tags:list()
    if next(tags_list) == nil then
        Log.info("No tags found in vault")
        return
    end

    -- sort tags by notes count
    table.sort(tags_list, function(a, b)
        return a.data.count > b.data.count
    end)

    -- Determine UI height safely
    local ui_height = vim.o.lines
    if #vim.api.nvim_list_uis() > 0 then
        ui_height = vim.api.nvim_list_uis()[1].height
    end

    local steps = math.min(ui_height, vim.tbl_count(tags_list))

    -- Gradient setup with safe fallback
    local hl_name = "VaultTag"
    local colors = nil
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

    --- @param entry vault.TelescopeEntry
    local make_display = function(entry)
        --- @type vault.Tag
        local tag = entry.value
        local sources_count = tag.data.count or 0

        --- --
        local col_1 = tag.data.name
        local col_1_width = 29

        local col_1_hl_name = "TelescopeResultsNormal"
        if colors then
            local i = math.min(math.floor(sources_count / 2), steps)
            if i == 0 then
                i = 1
            end
            col_1_hl_name = hl_name .. tostring(i)
        end
        --- --

        local col_2 = tostring(sources_count)
        local col_2_width = col_2:len()
        local col_2_hl_name = "TelescopeResultsNumber"
        --- --

        local displayer = entry_display.create({
            separator = " ",
            items = {
                { width = col_1_width },
                { remaining = true },
                { width = col_2_width },
                { remaining = true },
            },
        })

        return displayer({
            { col_1, col_1_hl_name },
            { col_2, col_2_hl_name },
        })
    end

    --- @param tag vault.Tag
    --- @return vault.TelescopeEntry
    local entry_maker = function(tag)
        return {
            value = tag,
            ordinal = tag.data.name .. " " .. tostring(tag.data.count),
            display = make_display,
        }
    end

    local finder = finders.new_table({
        results = tags_list,
        entry_maker = entry_maker,
    })

    local on_input_filter_cb = function(prompt)
        local picker = vault_state.get_global_key("picker")
        local is_negative = false

        local function default_finder()
            local new_finder = finders.new_table({
                results = tags_list,
                entry_maker = entry_maker,
            })

            picker.finder:close() -- TODO: Find a way to close picker without closing previewer
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
            local tag = entry.value
            local slug = tag.data.name
            if slug == nil then
                goto continue
            end
            local is_valid_regex = pcall(vim.fn.match, slug, pattern)
            if is_valid_regex == false then
                goto continue
            end
            if vim.fn.match(slug, pattern) ~= -1 then
                table.insert(new_results, tag)
                if is_negative == true then
                    table.insert(results_without_excluded, tag)
                end
            end
            ::continue::
        end
        if next(new_results) == nil then
            return default_finder()
        elseif is_negative == true then
            new_results = {}
            for _, entry in ipairs(picker.finder.results) do -- TODO: Use results_without_excluded
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

    -- Attach mappings with highlight cleanup
    local attach_mappings = function(prompt_bufnr, map)
        -- Ensure original mappings are preserved if provided
        if type(vault_mappings.tags) == "function" then
            local ok, res = pcall(vault_mappings.tags, prompt_bufnr, map)
            if not ok then
                -- ignore mapping errors
            end
        end

        local function cleanup()
            if colors then
                for i = 1, #colors do
                    pcall(vim.api.nvim_set_hl, 0, hl_name .. tostring(i), {})
                end
            end
        end

        pcall(vim.api.nvim_create_autocmd, "BufWipeout", {
            buffer = prompt_bufnr,
            once = true,
            callback = cleanup,
        })

        return true
    end

    local picker_opts = {
        prompt_title = "tags",
        finder = finder,
        sorter = sorters.get_fzy_sorter(),
        previewer = vault_previewers.tags,
        attach_mappings = attach_mappings,
        on_input_filter_cb = on_input_filter_cb,
    }
    local picker = pickers.new(vault_layouts.tags(), picker_opts)
    vault_state.set_global_key("picker", picker)
    return picker
end
