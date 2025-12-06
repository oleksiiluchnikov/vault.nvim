--- @class telescope_popup_options.vault.properties: telescope_popup_options
--- @field properties? vault.Properties - The properties to display in the picker.
----- @field query? string[] List of property names to show. If not provided, all properties will be shown.

--- @param opts? telescope_popup_options.vault.properties
--- @return Picker
return function(opts)
    local finders = require("telescope.finders")
    local pickers = require("telescope.pickers")
    local sorters = require("telescope.sorters")
    local entry_display = require("telescope.pickers.entry_display")
    local vault_state = require("vault.core.state")
    local Log = require("plenary.log")
    local Gradient = require("gradient")

    opts = opts or {}
    opts.query = opts.query or {}
    --- @type vault.Properties
    opts.properties = opts.properties or require("vault.properties")()

    local properties_list = opts.properties:list()
    if next(properties_list) == nil then
        Log.info("No properties found in vault")
    end

    -- sort tags by notes count
    table.sort(properties_list, function(a, b)
        return a.data.count > b.data.count
    end)

    local steps = math.min(vim.api.nvim_list_uis()[1].height, vim.tbl_count(properties_list))
    --- @type Gradient|nil
    local colors = Gradient.from_stops(steps, "Comment", "Normal", "String")
    if type(colors) ~= "table" then
        -- error(
        --     error_msg.COMMAND_EXECUTION_ERROR("Gradient.from_stops", "table", vim.inspect(colors))
        -- )
        -- error("Gradient.from_stops", "table", vim.inspect(colors))
        error("Gradient.from_stops")
    end
    local hl_name = "VaultProperty"
    for i, color in ipairs(colors) do
        vim.api.nvim_set_hl(0, hl_name .. tostring(i), { fg = color })
    end

    --- @param entry vault.TelescopeEntry
    local make_display = function(entry)
        --- @type vault.Property
        local property = entry.value
        local sources_count = property.data.count

        --- --
        local col_1 = property.data.name
        local col_1_width = 29
        local i = math.min(math.floor(sources_count / 2), steps)
        if i == 0 then
            i = 1
        end
        local col_1_hl_name = hl_name .. tostring(i)
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

    --- @param property vault.Property
    --- @return vault.TelescopeEntry
    local entry_maker = function(property)
        return {
            value = property,
            ordinal = property.data.name .. " " .. tostring(property.data.count),
            display = make_display,
        }
    end

    local finder = finders.new_table({
        results = properties_list,
        entry_maker = entry_maker,
    })

    local on_input_filter_cb = function(prompt)
        local picker = vault_state.get_global_key("picker")
        local is_negative = false

        local function default_finder()
            local new_finder = finders.new_table({
                results = properties_list,
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
            local property = entry.value
            local slug = property.data.name
            if slug == nil then
                goto continue
            end
            local is_valid_regex = pcall(vim.fn.match, slug, pattern)
            if is_valid_regex == false then
                goto continue
            end
            if vim.fn.match(slug, pattern) ~= -1 then
                table.insert(new_results, property)
                if is_negative == true then
                    table.insert(results_without_excluded, property)
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

    -- Filter properties by query
    if next(opts.query) ~= nil then
        local filtered_properties = {}
        for _, property in ipairs(opts.query) do
            if opts.properties.map[property] ~= nil then
                filtered_properties[property] = opts.properties.map[property]
            end
        end
        if next(filtered_properties) == nil then
            vim.notify("No properties found")
        end
        opts.properties.map = filtered_properties
    end

    if vim.tbl_count(opts.properties.map) == 1 then
        local property_name = vim.tbl_keys(opts.properties.map)[1]
        require("vault.api").open_picker_property_values(property_name)
    else
        local picker = pickers.new(opts, {
            prompt_title = "Properties",
            finder = finder,
            sorter = sorters.get_fzy_sorter(),
            attach_mappings = require("telescope._extensions.vault.mappings").properties,
            on_input_filter_cb = on_input_filter_cb,
        })
        vault_state.set_global_key("picker", picker)
        return picker
    end

    return picker
end
