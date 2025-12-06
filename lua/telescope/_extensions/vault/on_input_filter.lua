local finders = require("telescope.finders")
local vault_state = require("vault.core.state")
return function(prompt)
    local picker = vault_state.get_global_key("picker")
    local is_negative = false

    local function default_finder()
        local new_results = {}
        for _, entry in ipairs(picker.finder.results) do
            table.insert(new_results, entry.value)
        end
        local new_finder = finders.new_table({
            results = new_results,
            entry_maker = picker.finder.entry_maker,
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
        local note = entry.value
        local slug = note.data.slug
        if slug == nil then
            goto continue
        end
        local is_valid_regex = pcall(vim.fn.match, slug, pattern)
        if is_valid_regex == false then
            goto continue
        end
        if vim.fn.match(slug, pattern) ~= -1 then
            table.insert(new_results, note)
            if is_negative == true then
                table.insert(results_without_excluded, note)
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
        entry_maker = picker.finder.entry_maker,
    })
    picker.finder:close()
    picker.finder = new_finder

    vault_state.set_global_key("prompt", prompt)

    return {
        prompt = "",
    }
end
