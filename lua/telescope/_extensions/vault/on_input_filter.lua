--- Factory that builds an on_input_filter_cb for any vault picker.
--- Supports trailing `/` as regex filter and `-` prefix for negative filter.
---
--- @param results table The original results list (domain objects, NOT telescope entries)
--- @param entry_maker function The picker's entry_maker function
--- @param opts? { search_text?: fun(item: any): string }
--- @return function on_input_filter_cb
return function(results, entry_maker, opts)
    opts = opts or {}
    local finders = require("telescope.finders")
    local vault_match = require("vault.utils").match
    local vault_state = require("vault.core.state")

    return function(prompt)
        local picker = vault_state.get_global_key("picker")
        if not picker then
            return { prompt = prompt or "" }
        end

        local function default_finder()
            local new_finder = finders.new_table({
                results = results,
                entry_maker = entry_maker,
            })
            picker.finder:close()
            picker.finder = new_finder
            vault_state.set_global_key("prompt", prompt)
            return { prompt = prompt or "" }
        end

        if not prompt or #prompt == 0 or prompt:sub(-1) ~= "/" then
            return default_finder()
        end

        local is_negative = prompt:sub(1, 1) == "-"
        local pattern = prompt:sub(1, -2)
        if is_negative then
            pattern = pattern:sub(2)
        end

        local new_results = {}
        local excluded = {}

        for _, entry in ipairs(picker.finder.results) do
            local item = entry.value or entry
            local searchable = type(opts.search_text) == "function" and opts.search_text(item)
                or entry.ordinal
                or (item.data and (item.data.slug or item.data.name or item.data.relpath or item.data.content))
                or ""
            searchable = tostring(searchable)
            if searchable == "" then
                goto continue
            end
            local ok, matched = pcall(vault_match, searchable, pattern, "regex", false)
            if not ok then
                goto continue
            end
            if matched then
                table.insert(new_results, item)
                if is_negative then
                    table.insert(excluded, item)
                end
            end
            ::continue::
        end

        if next(new_results) == nil then
            return default_finder()
        elseif is_negative then
            new_results = {}
            for _, entry in ipairs(picker.finder.results) do
                local item = entry.value or entry
                if not vim.tbl_contains(excluded, item) then
                    table.insert(new_results, item)
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
        return { prompt = "" }
    end
end
