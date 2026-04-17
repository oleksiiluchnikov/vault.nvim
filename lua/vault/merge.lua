--- vault.merge — Merge two notes into one.
--- Absorbs note B into note A: merges frontmatter, appends body,
--- rewrites all [[B]] wikilinks to [[A]], and trashes B.
--- Works standalone or from the process buffer (J keymap).

---@class vault.merge.Module
---@field plan fun(target_path: string, source_path: string, opts?: vault.merge.Options): vault.merge.Plan|nil, string|nil
---@field absorb fun(path_a: string, path_b: string, resolved?: table<string, vault.merge.ConflictChoice>, opts?: vault.merge.AbsorbOptions): nil
---@field merge fun(target_path: string, source_path: string, opts?: vault.merge.MergeOptions): nil
---@field safe_absorb_many fun(specs: vault.merge.BatchSafeAbsorbSpec[], opts?: vault.merge.SafeAbsorbManyOptions): vault.merge.BatchSafeAbsorbResult
---@field absorb_many fun(specs: vault.merge.BatchAbsorbSpec[], opts?: vault.merge.AbsorbManyOptions): vault.merge.BatchSafeAbsorbResult
---@field resolve_conflicts_with_biases fun(conflicts: vault.merge.FieldConflict[]): table<string, vault.merge.ConflictChoice>, vault.merge.FieldConflict[]
---@field open_conflict_picker fun(target_slug: string, source_slug: string, conflicts: vault.merge.FieldConflict[], on_done: fun(resolved: table<string, vault.merge.ConflictChoice>)): nil

---@type vault.merge.Module
local M = {}

local config = require("vault.config")
local log = require("vault.log").scope("merge")

---@return table<string, boolean>
local function ignored_conflict_fields()
    ---@type string[]
    local configured = config.options.merge and config.options.merge.ignored_conflict_fields or {}
    ---@type table<string, boolean>
    local result = {}
    for _, key in ipairs(configured) do
        result[key] = true
    end
    return result
end

---@class vault.merge.FieldConflict
---@field field string
---@field val_a any
---@field val_b any

---@class vault.merge.Options
---@field resolved? table<string, vault.merge.ConflictChoice>
---@field body_strategy? string
---@field paths? table<string, table>
---@field on_done? fun()
---@field silent? boolean

---@class vault.merge.AbsorbOptions
---@field bufnr? integer
---@field on_done? fun()
---@field body_strategy? string
---@field paths? table<string, table>

---@class vault.merge.MergeOptions : vault.merge.AbsorbOptions

---@class vault.merge.SafeAbsorbManyOptions
---@field silent? boolean

---@alias vault.merge.ConflictChoice "a"|"b"
---@alias vault.merge.ConflictBiasPreset "a"|"b"|"earliest"|"latest"
---@alias vault.merge.ConflictBias fun(conflict: vault.merge.FieldConflict, key:string): vault.merge.ConflictChoice|nil
---@alias vault.merge.ConflictBiasBehavior "preselect"|"auto_apply"
---@alias vault.merge.ConflictBiasSource "configured"|"learned"

---@class vault.merge.ResolvedBias
---@field choice vault.merge.ConflictChoice
---@field source vault.merge.ConflictBiasSource

---@class vault.merge.FieldPlan
---@field merged_fields table
---@field added_fields string[]
---@field extended_fields string[]
---@field conflicts vault.merge.FieldConflict[]
---@field ignored_fields string[]

---@class vault.merge.Plan
---@field target_path string
---@field source_path string
---@field target_slug string
---@field source_slug string
---@field fields_a table
---@field fields_b table
---@field body_a string[]
---@field body_b string[]
---@field raw_a string[]
---@field raw_b string[]
---@field merged_fields table
---@field merged_lines string[]
---@field added_fields string[]
---@field extended_fields string[]
---@field conflicts vault.merge.FieldConflict[]
---@field ignored_fields string[]
---@field body_strategy string

---@class vault.merge.BatchSafeAbsorbSpec
---@field target_path string
---@field source_path string
---@field merged_fields? table

---@class vault.merge.BatchAbsorbSpec
---@field target_path string
---@field source_path string
---@field merged_lines string[]

---@class vault.merge.AbsorbManyOptions
---@field silent? boolean
---@field paths? table<string, table>

---@class vault.merge.BatchSafeAbsorbResult
---@field applied integer
---@field patched integer
---@field trashed integer
---@field skipped integer

--- Frontmatter fields parsed from a note file.
---@alias vault.merge.FrontmatterFields table<string, string|string[]>

--- Read the full content of a file, split into frontmatter fields, body lines.
---@param path vault.path
---@return vault.merge.FrontmatterFields|nil fields, string[]|nil body_lines, string[]|nil raw_lines
local function parse_note(path)
    local ok, lines = pcall(vim.fn.readfile, path)
    if not ok or #lines == 0 then
        return nil, nil, nil
    end

    ---@type vault.merge.FrontmatterFields
    local fields = {}
    local body_start = 1

    if lines[1] and lines[1]:match("^%-%-%-$") then
        ---@type integer|nil
        local fm_end = nil
        for i = 2, math.min(#lines, 200) do
            if lines[i]:match("^%-%-%-$") then
                fm_end = i
                break
            end
        end
        if fm_end then
            body_start = fm_end + 1
            -- Parse frontmatter
            ---@type string|nil
            local current_key
            ---@type string[]|nil
            local current_list
            for i = 2, fm_end - 1 do
                local l = lines[i]
                local list_item = l:match("^%s+%-%s+(.+)")
                if list_item and current_key and current_list then
                    list_item = list_item:gsub('^"(.*)"$', "%1"):gsub("^'(.*)'$", "%1")
                    table.insert(current_list, list_item)
                else
                    local key, value = l:match("^([%w_%-]+):%s*(.*)")
                    if key then
                        if current_key and current_list and #current_list > 0 then
                            fields[current_key] = current_list
                        end
                        current_key = key
                        current_list = nil
                        value = vim.trim(value or "")
                        if value == "" then
                            current_list = {}
                        else
                            value = value:gsub('^"(.*)"$', "%1"):gsub("^'(.*)'$", "%1")
                            fields[key] = value
                            current_key = nil
                        end
                    end
                end
            end
            if current_key and current_list and #current_list > 0 then
                fields[current_key] = current_list
            end
        end
    end

    ---@type string[]
    local body = {}
    for i = body_start, #lines do
        table.insert(body, lines[i])
    end

    return fields, body, lines
end

---@param key string  frontmatter field key
---@return boolean
local function is_noisy_field(key)
    return ignored_conflict_fields()[key] == true
end

---@param key string
---@param value any
---@return any
local function normalize_field_value(key, value)
    local normalizers = config.options.merge and config.options.merge.field_normalizers or {}
    local normalizer = normalizers[key]
    if type(normalizer) == "function" then
        local ok, normalized = pcall(normalizer, value, key)
        if ok then
            return normalized
        end
        log.warn("merge field_normalizers.%s failed: %s", key, tostring(normalized))
    end
    return value
end

---@param value any
---@return string
local function normalize_value_for_compare(value)
    if type(value) == "table" then
        ---@type string[]
        local items = {}
        for _, item in ipairs(value) do
            items[#items + 1] = tostring(item)
        end
        table.sort(items)
        return table.concat(items, "\0")
    end
    return tostring(value)
end

---@param value any
---@return any
local function clone_value(value)
    if type(value) == "table" then
        return vim.deepcopy(value)
    end
    return value
end

---@return table<string, vault.merge.ConflictBiasPreset|vault.merge.ConflictBias>
local function conflict_biases()
    local configured = config.options.merge and config.options.merge.conflict_biases or {}
    if type(configured) ~= "table" then
        return {}
    end
    return configured
end

---@return vault.merge.ConflictBiasBehavior
local function configured_conflict_bias_behavior()
    local behavior = config.options.merge and config.options.merge.conflict_bias_behavior
    if behavior == "preselect" then
        return "preselect"
    end
    return "auto_apply"
end

---@param value any
---@return string|nil
local created_sort_key

---@param bias any
---@param conflict vault.merge.FieldConflict
---@param source string
---@return vault.merge.ConflictChoice|nil
local function apply_conflict_bias(bias, conflict, source)
    if bias == nil then
        return nil
    end

    if type(bias) == "function" then
        local ok, choice = pcall(bias, conflict, conflict.field)
        if ok and (choice == "a" or choice == "b") then
            return choice
        end
        if not ok then
            log.warn("merge %s.%s failed: %s", source, conflict.field, tostring(choice))
        else
            log.warn(
                "merge %s.%s returned invalid choice: %s",
                source,
                conflict.field,
                tostring(choice)
            )
        end
        return nil
    end

    if bias == "a" or bias == "b" then
        return bias
    end

    if bias == "earliest" or bias == "latest" then
        local a_key = created_sort_key(normalize_field_value(conflict.field, conflict.val_a))
        local b_key = created_sort_key(normalize_field_value(conflict.field, conflict.val_b))
        if not a_key or not b_key then
            return nil
        end

        if bias == "earliest" then
            return a_key <= b_key and "a" or "b"
        end

        return a_key >= b_key and "a" or "b"
    end

    log.warn("merge %s.%s has invalid preset: %s", source, conflict.field, tostring(bias))
    return nil
end

---@param value any
---@return string|nil
created_sort_key = function(value)
    if value == nil then
        return nil
    end

    local digits = tostring(value):gsub("%D", "")
    if digits == "" then
        return nil
    end

    if #digits < 14 then
        digits = digits .. string.rep("0", 14 - #digits)
    end

    return digits
end

---@param conflict vault.merge.FieldConflict
---@return vault.merge.ConflictChoice|nil
local function resolve_conflict_bias(conflict)
    local configured_choice =
        apply_conflict_bias(conflict_biases()[conflict.field], conflict, "conflict_biases")
    if configured_choice ~= nil then
        return configured_choice
    end

    local learned_choice = apply_conflict_bias(
        require("vault.merge_biases").get(conflict.field),
        conflict,
        "learned_conflict_biases"
    )
    if learned_choice ~= nil then
        return learned_choice
    end

    return nil
end

---@param conflict vault.merge.FieldConflict
---@return vault.merge.ResolvedBias|nil
local function resolve_conflict_bias_info(conflict)
    local configured_choice =
        apply_conflict_bias(conflict_biases()[conflict.field], conflict, "conflict_biases")
    if configured_choice ~= nil then
        return {
            choice = configured_choice,
            source = "configured",
        }
    end

    local learned_choice = apply_conflict_bias(
        require("vault.merge_biases").get(conflict.field),
        conflict,
        "learned_conflict_biases"
    )
    if learned_choice ~= nil then
        return {
            choice = learned_choice,
            source = "learned",
        }
    end

    return nil
end

---@param source vault.merge.ConflictBiasSource
---@return vault.merge.ConflictBiasBehavior
local function conflict_bias_behavior_for(source)
    if source == "configured" then
        return configured_conflict_bias_behavior()
    end
    return require("vault.merge_biases").behavior()
end

---@param conflict vault.merge.FieldConflict
---@param choice vault.merge.ConflictChoice
---@return vault.merge.ConflictBiasPreset
local function infer_conflict_bias(conflict, choice)
    local a_key = created_sort_key(normalize_field_value(conflict.field, conflict.val_a))
    local b_key = created_sort_key(normalize_field_value(conflict.field, conflict.val_b))
    if a_key and b_key then
        local earliest = a_key <= b_key and "a" or "b"
        if choice == earliest then
            return "earliest"
        end
        return "latest"
    end

    return choice
end

---@param conflicts vault.merge.FieldConflict[]
---@param choices vault.merge.ConflictChoice[]
local function remember_conflict_choices(conflicts, choices)
    local configured = conflict_biases()
    local store = require("vault.merge_biases")
    if not store.enabled() then
        return
    end

    for index, conflict in ipairs(conflicts) do
        if configured[conflict.field] == nil then
            store.remember(conflict.field, infer_conflict_bias(conflict, choices[index]))
        end
    end
end

---@param conflicts vault.merge.FieldConflict[]
---@return table<string, any>, vault.merge.FieldConflict[]
local function resolve_conflicts_with_biases(conflicts)
    ---@type table<string, any>
    local resolved = {}
    ---@type vault.merge.FieldConflict[]
    local unresolved = {}

    for _, conflict in ipairs(conflicts or {}) do
        local info = resolve_conflict_bias_info(conflict)
        local choice = info and info.choice or nil
        local behavior = info and conflict_bias_behavior_for(info.source) or nil
        if choice == "a" and behavior == "auto_apply" then
            resolved[conflict.field] = clone_value(conflict.val_a)
        elseif choice == "b" and behavior == "auto_apply" then
            resolved[conflict.field] = clone_value(conflict.val_b)
        else
            unresolved[#unresolved + 1] = conflict
        end
    end

    return resolved, unresolved
end

---@param conflict vault.merge.FieldConflict
---@return vault.merge.ConflictChoice
local function default_conflict_choice(conflict)
    return resolve_conflict_bias(conflict) or "a"
end

---@param fields_a vault.merge.FrontmatterFields
---@param fields_b vault.merge.FrontmatterFields
---@param resolved? table<string, any>
---@return vault.merge.FieldPlan
local function plan_field_merge(fields_a, fields_b, resolved)
    resolved = resolved or {}
    ---@type vault.merge.FrontmatterFields
    local merged = vim.deepcopy(fields_a)
    ---@type string[]
    local added_fields = {}
    ---@type string[]
    local extended_fields = {}
    ---@type vault.merge.FieldConflict[]
    local conflicts = {}
    ---@type string[]
    local ignored_fields = {}

    for key, val_b in pairs(fields_b) do
        local val_a = merged[key]
        if resolved[key] ~= nil then
            merged[key] = clone_value(resolved[key])
        elseif is_noisy_field(key) then
            if
                val_a == nil
                or normalize_value_for_compare(normalize_field_value(key, val_a))
                    ~= normalize_value_for_compare(normalize_field_value(key, val_b))
            then
                ignored_fields[#ignored_fields + 1] = key
            end
        elseif val_a == nil or val_a == "" then
            merged[key] = clone_value(val_b)
            added_fields[#added_fields + 1] = key
        elseif type(val_a) == "table" and type(val_b) == "table" then
            ---@type table<string, boolean>
            local seen = {}
            for _, v in ipairs(val_a) do
                seen[tostring(v)] = true
            end
            local extended = false
            for _, v in ipairs(val_b) do
                local token = tostring(v)
                if not seen[token] then
                    table.insert(merged[key], v)
                    seen[token] = true
                    extended = true
                end
            end
            if extended then
                extended_fields[#extended_fields + 1] = key
            end
        elseif
            normalize_value_for_compare(normalize_field_value(key, val_a))
            ~= normalize_value_for_compare(normalize_field_value(key, val_b))
        then
            conflicts[#conflicts + 1] = { field = key, val_a = val_a, val_b = val_b }
        end
    end

    table.sort(added_fields)
    table.sort(extended_fields)
    table.sort(ignored_fields)
    table.sort(conflicts, function(a, b)
        return a.field < b.field
    end)

    return {
        merged_fields = merged,
        added_fields = added_fields,
        extended_fields = extended_fields,
        conflicts = conflicts,
        ignored_fields = ignored_fields,
    }
end

--- Detect field conflicts between two notes.
---@param fields_a vault.merge.FrontmatterFields
---@param fields_b vault.merge.FrontmatterFields
---@return vault.merge.FieldConflict[]
local function detect_conflicts(fields_a, fields_b)
    return plan_field_merge(fields_a, fields_b, {}).conflicts
end

--- Merge fields: A wins by default, resolved overrides apply, arrays are unioned.
---@param fields_a vault.merge.FrontmatterFields
---@param fields_b vault.merge.FrontmatterFields
---@param resolved? table<string, any>  field → chosen value (from picker)
---@return vault.merge.FrontmatterFields merged
local function merge_fields(fields_a, fields_b, resolved)
    return plan_field_merge(fields_a, fields_b, resolved).merged_fields
end

--- Build frontmatter YAML lines from a fields table.
---@param fields vault.merge.FrontmatterFields
---@return string[]
local function build_frontmatter(fields)
    ---@type string[]
    local lines = { "---" }
    -- Sort keys for deterministic output
    ---@type string[]
    local keys = vim.tbl_keys(fields)
    table.sort(keys)
    for _, key in ipairs(keys) do
        local val = fields[key]
        if type(val) == "table" then
            table.insert(lines, key .. ":")
            for _, v in ipairs(val) do
                local s = tostring(v)
                if s:match("[:%[%]{}#&*!|>%%@`,?]") or s:match("^%s") or s:match("%s$") then
                    table.insert(lines, '  - "' .. s:gsub('"', '\\"') .. '"')
                else
                    table.insert(lines, "  - " .. s)
                end
            end
        elseif val ~= nil then
            local s = tostring(val)
            if s:match("[:%[%]{}#&*!|>%%@`,?]") or s:match("^%s") or s:match("%s$") or s == "" then
                table.insert(lines, key .. ': "' .. s:gsub('"', '\\"') .. '"')
            else
                table.insert(lines, key .. ": " .. s)
            end
        end
    end
    table.insert(lines, "---")
    return lines
end

---@param path string
---@param fields table
---@param body_lines string[]|nil
local function write_note(path, fields, body_lines)
    local lines = build_frontmatter(fields)
    if body_lines then
        for _, line in ipairs(body_lines) do
            table.insert(lines, line)
        end
    end
    vim.fn.writefile(lines, path)
end

---@param merged_fields table
---@param body_a string[]|nil
---@param body_b string[]|nil
---@param source_slug string
---@param body_strategy? string
---@return string[]
local function build_merged_note_lines(merged_fields, body_a, body_b, source_slug, body_strategy)
    ---@type string[]
    local merged_lines = build_frontmatter(merged_fields)

    if body_a then
        for _, line in ipairs(body_a) do
            table.insert(merged_lines, line)
        end
    end

    if body_strategy == "keep_target" then
        return merged_lines
    end

    if body_b and #body_b > 0 then
        local first_content = 1
        for i, line in ipairs(body_b) do
            if line:match("%S") then
                first_content = i
                break
            end
        end
        table.insert(merged_lines, "")
        table.insert(merged_lines, string.format("<!-- merged from: %s -->", source_slug))
        table.insert(merged_lines, "")
        for i = first_content, #body_b do
            table.insert(merged_lines, body_b[i])
        end
    end

    return merged_lines
end

---@param path string
---@param body_lines string[]|nil
---@return string
local function normalize_body_for_compare(path, body_lines)
    ---@type string[]
    local normalized_lines = {}
    for _, line in ipairs(body_lines or {}) do
        local normalized_line = (line or ""):gsub("\r$", "")
        table.insert(normalized_lines, normalized_line)
    end

    for index, line in ipairs(normalized_lines) do
        if line:match("%S") then
            if line:match("^# ") then
                local stem = vim.fn.fnamemodify(path, ":t:r")
                local base = stem:match("^(.-) %d+$") or stem
                normalized_lines[index] = "# " .. base
            end
            break
        end
    end

    return vim.trim(table.concat(normalized_lines, "\n"))
end

--- Open a floating picker for resolving field conflicts.
---@param slug_a string
---@param slug_b string
---@param conflicts { field: string, val_a: any, val_b: any }[]
---@param on_resolve fun(resolved: table<string, any>)
function M.open_conflict_picker(slug_a, slug_b, conflicts, on_resolve)
    ---@type vault.merge.ConflictChoice[]
    local choices = {} -- index → "a" or "b"
    for i, conflict in ipairs(conflicts) do
        choices[i] = default_conflict_choice(conflict)
    end

    -- Pre-compute column widths for alignment
    local MAX_VAL = 38 -- max display width for each value column
    ---@param v any
    ---@return string
    local function val_str(v)
        return type(v) == "table" and table.concat(v, ", ") or tostring(v)
    end
    ---@param s string
    ---@param max integer
    ---@return string
    local function truncate(s, max)
        if #s <= max then
            return s
        end
        return s:sub(1, max - 1) .. "…"
    end

    -- Field-name column width: longest "fieldname:" + 1 space
    local field_w = 0
    for _, c in ipairs(conflicts) do
        field_w = math.max(field_w, #c.field + 1) -- +1 for ":"
    end
    field_w = field_w + 1 -- trailing space after colon

    -- Value column width: capped at MAX_VAL
    local val_a_w = 0
    local val_b_w = 0
    for _, c in ipairs(conflicts) do
        val_a_w = math.max(val_a_w, math.min(#val_str(c.val_a), MAX_VAL))
        val_b_w = math.max(val_b_w, math.min(#val_str(c.val_b), MAX_VAL))
    end

    -- marker (●/○) is 1 display cell + 1 space = 2 before value
    -- layout: " " + field_col + "  " + marker + " " + val_a_col + "  |  " + marker + " " + val_b_col
    local total_w = 1 + field_w + 2 + 2 + val_a_w + 5 + 2 + val_b_w
    local width = math.max(total_w, 60)

    ---@return string[]
    local function render_lines()
        local header = string.format(" Merge: %s ← %s", slug_a, slug_b)
        local sep_line = " " .. string.rep("─", width - 2)
        ---@type string[]
        local lines = { header, sep_line }
        for i, c in ipairs(conflicts) do
            local a_str = truncate(val_str(c.val_a), MAX_VAL)
            local b_str = truncate(val_str(c.val_b), MAX_VAL)
            local marker_a = choices[i] == "a" and "●" or "○"
            local marker_b = choices[i] == "b" and "●" or "○"
            -- Pad field name and value columns for alignment
            local field_col = string.format("%-" .. field_w .. "s", c.field .. ":")
            local val_a_col = string.format("%-" .. val_a_w .. "s", a_str)
            table.insert(
                lines,
                string.format(
                    " %s  %s %s  |  %s %s",
                    field_col,
                    marker_a,
                    val_a_col,
                    marker_b,
                    b_str
                )
            )
        end
        table.insert(lines, "")
        table.insert(
            lines,
            " [a] pick A  [b] pick B  [<CR>] apply  [r] apply + remember  [q] cancel"
        )
        table.insert(lines, " remember/edit learned rules: :Vault merge biases")
        return lines
    end

    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, render_lines())
    vim.bo[buf].modifiable = false
    vim.bo[buf].bufhidden = "wipe"

    local height = #conflicts + 6
    local win = vim.api.nvim_open_win(buf, true, {
        relative = "editor",
        width = width,
        height = height,
        col = math.floor((vim.o.columns - width) / 2),
        row = math.floor((vim.o.lines - height) / 2),
        style = "minimal",
        border = "rounded",
        title = " Resolve Conflicts ",
        title_pos = "center",
    })

    local cursor_idx = 1

    local function update()
        vim.bo[buf].modifiable = true
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, render_lines())
        vim.bo[buf].modifiable = false
        vim.api.nvim_win_set_cursor(win, { cursor_idx + 2, 0 }) -- +2 for header lines
    end

    local function close()
        if vim.api.nvim_win_is_valid(win) then
            vim.api.nvim_win_close(win, true)
        end
    end

    ---@type { buffer: integer, nowait: boolean, silent: boolean }
    local kopts = { buffer = buf, nowait = true, silent = true }

    ---@param remember boolean
    local function confirm_choices(remember)
        close()
        ---@type table<string, any>
        local resolved = {}
        for i, c in ipairs(conflicts) do
            resolved[c.field] = choices[i] == "a" and c.val_a or c.val_b
        end
        if remember then
            remember_conflict_choices(conflicts, choices)
        end
        on_resolve(resolved)
    end

    vim.keymap.set("n", "j", function()
        cursor_idx = math.min(cursor_idx + 1, #conflicts)
        update()
    end, kopts)

    vim.keymap.set("n", "k", function()
        cursor_idx = math.max(cursor_idx - 1, 1)
        update()
    end, kopts)

    vim.keymap.set("n", "a", function()
        choices[cursor_idx] = "a"
        update()
    end, kopts)

    vim.keymap.set("n", "b", function()
        choices[cursor_idx] = "b"
        update()
    end, kopts)

    vim.keymap.set("n", "<CR>", function()
        confirm_choices(false)
    end, kopts)

    vim.keymap.set("n", "r", function()
        confirm_choices(true)
    end, kopts)

    vim.keymap.set("n", "q", function()
        close()
        log.info("Merge cancelled")
    end, kopts)

    vim.keymap.set("n", "<Esc>", function()
        close()
        log.info("Merge cancelled")
    end, kopts)

    update()
end

---@param path_a string
---@param path_b string
---@param opts? vault.merge.Options
---@return vault.merge.Plan|nil, string|nil
function M.plan(path_a, path_b, opts)
    opts = opts or {}
    local utils = require("vault.utils")

    local slug_a = utils.path_to_slug(path_a)
    local slug_b = utils.path_to_slug(path_b)
    local fields_a, body_a, raw_a = parse_note(path_a)
    local fields_b, body_b, raw_b = parse_note(path_b)
    if not fields_a or not fields_b or not raw_a or not raw_b then
        ---@type string[]
        local missing = {}
        if not fields_a then
            table.insert(missing, slug_a .. " (" .. path_a .. ")")
        end
        if not fields_b then
            table.insert(missing, slug_b .. " (" .. path_b .. ")")
        end
        return nil, "Failed to parse: " .. table.concat(missing, ", ")
    end

    local field_plan = plan_field_merge(fields_a, fields_b, opts.resolved)
    local body_strategy = opts.body_strategy or "append_source"
    local merged_lines =
        build_merged_note_lines(field_plan.merged_fields, body_a, body_b, slug_b, body_strategy)

    return {
        target_path = path_a,
        source_path = path_b,
        target_slug = slug_a,
        source_slug = slug_b,
        fields_a = fields_a,
        fields_b = fields_b,
        body_a = body_a or {},
        body_b = body_b or {},
        raw_a = raw_a,
        raw_b = raw_b,
        merged_fields = field_plan.merged_fields,
        merged_lines = merged_lines,
        added_fields = field_plan.added_fields,
        extended_fields = field_plan.extended_fields,
        conflicts = field_plan.conflicts,
        ignored_fields = field_plan.ignored_fields,
        body_strategy = body_strategy,
    },
        nil
end

--- Absorb note B into note A.
---@param path_a string
---@param path_b string
---@param resolved? table<string, vault.merge.ConflictChoice>  resolved conflict fields
---@param opts? vault.merge.AbsorbOptions
function M.absorb(path_a, path_b, resolved, opts)
    opts = opts or {}
    local utils = require("vault.utils")

    local slug_a = utils.path_to_slug(path_a)
    local slug_b = utils.path_to_slug(path_b)

    local plan, err = M.plan(path_a, path_b, {
        resolved = resolved,
        body_strategy = opts.body_strategy,
    })
    if not plan then
        log.error("%s", tostring(err))
        return
    end

    ---@type table<string, string[]>
    local snapshot_files = {}
    snapshot_files[path_a] = plan.raw_a
    snapshot_files[path_b] = plan.raw_b

    local paths = opts.paths
    local wikilinks_map = opts.wikilinks_map
    if opts.bufnr or not paths or not wikilinks_map then
        local scanner = require("vault.scanner")
        if not paths and not wikilinks_map then
            paths, wikilinks_map = scanner.paths_and_wikilinks_cached()
        else
            paths = paths or scanner.paths()
            wikilinks_map = wikilinks_map or scanner.wikilinks_no_suggest()
        end
    end

    if opts.bufnr then
        local escaped_slug = vim.pesc(slug_b)
        local escaped_stem = vim.pesc(vim.fn.fnamemodify(path_b, ":t:r"))
        for _, entry in pairs(paths or {}) do
            local note_path = entry.path
            if not snapshot_files[note_path] and vim.fn.filereadable(note_path) == 1 then
                local f = io.open(note_path, "r")
                if f then
                    local content = f:read("*all")
                    f:close()
                    if
                        content:match("%[%[" .. escaped_slug)
                        or content:match("%[%[" .. escaped_stem)
                    then
                        snapshot_files[note_path] = vim.split(content, "\n", { plain = true })
                    end
                end
            end
        end
    end

    -- Store undo snapshot if we have a process buffer
    if opts.bufnr then
        local vt_undo = require("vimtable.undo")
        vt_undo.snapshot(opts.bufnr, {
            files = snapshot_files,
            created_paths = {},
            renames = {},
            timestamp = os.time(),
            description = string.format("merge %s ← %s", slug_a, slug_b),
        })
    end

    -- Write merged content to A
    local write_ok, write_err = pcall(function()
        local f = io.open(path_a, "w")
        if not f then
            error("Cannot open " .. path_a)
        end
        f:write(table.concat(plan.merged_lines, "\n") .. "\n")
        f:close()
    end)
    if not write_ok then
        log.error("Failed to write merged note: %s", tostring(write_err))
        return
    end

    -- Rewrite [[B]] wikilinks to [[A]] across vault
    local Watcher = require("vault.watcher")
    local watcher = Watcher()
    watcher:disable_oil_guard()
    local patched = watcher:handle_rename(path_b, path_a, nil, paths, wikilinks_map) or 0

    -- Trash B
    local Note = require("vault.notes.note")
    local ok_note, note_b = pcall(Note, path_b)
    if ok_note and note_b then
        local ok_del, del_err = pcall(note_b.delete, note_b, false, false)
        if not ok_del then
            log.warn("Failed to delete absorbed note %s: %s", path_b, tostring(del_err))
        end
    else
        log.warn("Failed to create Note object for deletion: %s — %s", path_b, tostring(note_b))
    end

    log.info("Merged %s ← %s (%d wikilinks patched)", slug_a, slug_b, patched)

    if opts.on_done then
        opts.on_done()
    end
end

--- Merge two notes, detecting conflicts automatically.
--- If conflicts exist, opens a picker. Otherwise absorbs silently.
---@param path_a string  path of the surviving note
---@param path_b string  path of the absorbed note
---@param opts? vault.merge.MergeOptions
function M.merge(path_a, path_b, opts)
    opts = opts or {}
    local plan, err = M.plan(path_a, path_b, {
        body_strategy = opts.body_strategy,
    })
    if not plan then
        log.error("%s", tostring(err))
        return
    end

    local conflicts = plan.conflicts
    local biased_resolved, unresolved = resolve_conflicts_with_biases(conflicts)

    if #conflicts == 0 then
        M.absorb(path_a, path_b, nil, opts)
    elseif #unresolved == 0 then
        M.absorb(path_a, path_b, biased_resolved, opts)
    else
        M.open_conflict_picker(plan.target_slug, plan.source_slug, unresolved, function(resolved)
            M.absorb(path_a, path_b, vim.tbl_extend("force", biased_resolved, resolved), opts)
        end)
    end
end

--- Batch-apply safe absorbs without rescanning the vault for each pair.
--- This is for cases where target body should stay as-is and source is only
--- used for metadata enrichment plus link rewrite + trash.
---@param specs vault.merge.BatchSafeAbsorbSpec[]
---@param opts? vault.merge.SafeAbsorbManyOptions
---@return vault.merge.BatchSafeAbsorbResult
function M.safe_absorb_many(specs, opts)
    opts = opts or {}
    if type(specs) ~= "table" or vim.tbl_isempty(specs) then
        return { applied = 0, patched = 0, trashed = 0, skipped = 0 }
    end

    local Watcher = require("vault.watcher")
    local Note = require("vault.notes.note")
    local watcher = Watcher()
    watcher:disable_oil_guard()

    ---@type { old_path: string, new_path: string }[]
    local renames = {}
    local applied = 0
    local trashed = 0
    local skipped = 0

    for _, spec in ipairs(specs) do
        local target_path = spec.target_path
        local source_path = spec.source_path

        if vim.fn.filereadable(target_path) == 0 or vim.fn.filereadable(source_path) == 0 then
            skipped = skipped + 1
            goto continue
        end

        local fields_target, body_target = parse_note(target_path)
        local fields_source, body_source = parse_note(source_path)
        if not fields_target or not fields_source then
            skipped = skipped + 1
            goto continue
        end

        local target_body = normalize_body_for_compare(target_path, body_target)
        local source_body = normalize_body_for_compare(source_path, body_source)
        if target_body ~= source_body then
            skipped = skipped + 1
            goto continue
        end

        local merged_fields = spec.merged_fields or merge_fields(fields_target, fields_source, {})
        write_note(target_path, merged_fields, body_target or {})

        table.insert(renames, {
            old_path = source_path,
            new_path = target_path,
        })
        applied = applied + 1

        ::continue::
    end

    local patched = watcher:handle_renames(renames, opts.silent == true) or 0

    for _, rename in ipairs(renames) do
        local ok_note, source_note = pcall(Note, rename.old_path)
        if ok_note and source_note then
            local ok_del = pcall(source_note.delete, source_note, false, false)
            if ok_del then
                trashed = trashed + 1
            end
        end
    end

    log.info(
        "Safe batch absorb: %d applied • %d files patched • %d trashed • %d skipped",
        applied,
        patched,
        trashed,
        skipped
    )

    return {
        applied = applied,
        patched = patched,
        trashed = trashed,
        skipped = skipped,
    }
end

--- Batch-apply arbitrary absorbs with a single rename rewrite pass.
---@param specs vault.merge.BatchAbsorbSpec[]
---@param opts? vault.merge.AbsorbManyOptions
---@return vault.merge.BatchSafeAbsorbResult
function M.absorb_many(specs, opts)
    opts = opts or {}
    if type(specs) ~= "table" or vim.tbl_isempty(specs) then
        return { applied = 0, patched = 0, trashed = 0, skipped = 0 }
    end

    local Watcher = require("vault.watcher")
    local Note = require("vault.notes.note")
    local watcher = Watcher()
    watcher:disable_oil_guard()

    ---@type { old_path: string, new_path: string }[]
    local renames = {}
    local applied = 0
    local trashed = 0
    local skipped = 0

    for _, spec in ipairs(specs) do
        local target_path = spec.target_path
        local source_path = spec.source_path
        if vim.fn.filereadable(target_path) == 0 or vim.fn.filereadable(source_path) == 0 then
            skipped = skipped + 1
            goto continue
        end
        if type(spec.merged_lines) ~= "table" or vim.tbl_isempty(spec.merged_lines) then
            skipped = skipped + 1
            goto continue
        end

        local ok_write, write_err = pcall(vim.fn.writefile, spec.merged_lines, target_path)
        if not ok_write then
            log.warn("Failed batch write for %s: %s", target_path, tostring(write_err))
            skipped = skipped + 1
            goto continue
        end

        renames[#renames + 1] = {
            old_path = source_path,
            new_path = target_path,
        }
        applied = applied + 1

        ::continue::
    end

    local patched = watcher:handle_renames(renames, opts.silent == true, opts.paths) or 0

    for _, rename in ipairs(renames) do
        local ok_note, source_note = pcall(Note, rename.old_path)
        if ok_note and source_note then
            local ok_del = pcall(source_note.delete, source_note, false, false)
            if ok_del then
                trashed = trashed + 1
            end
        end
    end

    log.info(
        "Batch absorb: %d applied • %d files patched • %d trashed • %d skipped",
        applied,
        patched,
        trashed,
        skipped
    )

    return {
        applied = applied,
        patched = patched,
        trashed = trashed,
        skipped = skipped,
    }
end

-- Expose internals for testing
M._parse_note = parse_note
M._plan_field_merge = plan_field_merge
M._detect_conflicts = detect_conflicts
M._merge_fields = merge_fields
M._build_frontmatter = build_frontmatter
M._build_merged_note_lines = build_merged_note_lines
M._normalize_body_for_compare = normalize_body_for_compare
M._default_conflict_choice = default_conflict_choice
M._remember_conflict_choices = remember_conflict_choices
M._infer_conflict_bias = infer_conflict_bias
M.resolve_conflicts_with_biases = resolve_conflicts_with_biases
M._resolve_conflict_bias_info = resolve_conflict_bias_info

return M
