local previewers = require("telescope.previewers")
local M = {}

local PROPERTY_PREVIEW_NS = vim.api.nvim_create_namespace("vault_property_preview")

---@param value any
---@return string
local function preview_cell(value)
    return tostring(value):gsub("\r\n", " <NL> "):gsub("\n", " <NL> "):gsub("\t", "  ")
end

---@param lines string[]
---@return string[]
local function normalize_preview_lines(lines)
    local normalized = {}
    for _, line in ipairs(lines or {}) do
        local text = tostring(line or "")
        local split = vim.split(text, "\n", { plain = true })
        if #split == 0 then
            normalized[#normalized + 1] = ""
        else
            for _, part in ipairs(split) do
                normalized[#normalized + 1] = part
            end
        end
    end
    return normalized
end

---@param bufnr integer
---@param message string
local function render_preview_error(bufnr, message)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "Property preview failed.",
        "",
        tostring(message),
    })
    vim.api.nvim_set_option_value("filetype", "text", {
        buf = bufnr,
        scope = "local",
    })
end

---@param property vault.Property
---@return string[], table<integer, { col: integer, end_col: integer, hl: string }[]>
local function property_preview_lines(property)
    --- @type string[]
    local lines = {}
    --- @type table<integer, { col: integer, end_col: integer, hl: string }[]>
    local highlights = {}
    local values = vim.tbl_values(property.data.values or {})

    table.sort(values, function(a, b)
        if a.data.count ~= b.data.count then
            return a.data.count > b.data.count
        end
        return tostring(a.data.name) < tostring(b.data.name)
    end)

    local function add(line, spans)
        lines[#lines + 1] = line
        if spans then
            highlights[#lines] = spans
        end
    end

    local property_name = preview_cell(property.data.name)
    add(property_name, {
        { col = 0, end_col = #property_name, hl = "Title" },
    })
    add(string.format("sources %d   values %d", property.data.count or 0, #values), {
        { col = 0, end_col = #lines[#lines], hl = "Comment" },
    })
    add("")

    if #values == 0 then
        add("No values found.", {
            { col = 0, end_col = 15, hl = "Comment" },
        })
    else
        local type_width = 12
        local value_width = 0
        for _, value in ipairs(values) do
            value_width =
                math.max(value_width, vim.fn.strdisplaywidth(preview_cell(value.data.name)))
        end
        value_width = math.min(math.max(value_width, 16), 48)

        local header =
            string.format("%-12s  %-" .. tostring(value_width) .. "s  %s", "type", "value", "count")
        add(header, {
            { col = 0, end_col = #header, hl = "Comment" },
        })
        add(string.rep("-", #header), {
            { col = 0, end_col = #header, hl = "Comment" },
        })
        for _, value in ipairs(values) do
            local type_text = preview_cell(value.data.type)
            local value_text = preview_cell(value.data.name)
            local count_text = tostring(value.data.count or 0)
            local line = string.format(
                "%-12s  %-" .. tostring(value_width) .. "s  %s",
                type_text,
                value_text,
                count_text
            )
            add(line, {
                { col = 0, end_col = #type_text, hl = "TelescopeResultsNormal" },
                {
                    col = type_width + 2,
                    end_col = type_width + 2 + #value_text,
                    hl = "TelescopeResultsIdentifier",
                },
                {
                    col = type_width + 2 + value_width + 2,
                    end_col = #line,
                    hl = "TelescopeResultsNumber",
                },
            })
        end
    end

    return lines, highlights
end

M.notes = previewers.vim_buffer_vimgrep.new({
    get_buffer_by_name = function(_, entry)
        local bufnr = vim.api.nvim_create_buf(false, true)
        if type(bufnr) ~= "number" then
            error("bufnr is not a number")
        end

        local lines = vim.fn.readfile(entry.filename)

        vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
        vim.api.nvim_set_option_value("filetype", "markdown", {
            win = vim.api.nvim_get_current_win(),
            scope = "local",
        })

        return bufnr
    end,
})

-- TODO: Optimize this previewer
M.tags = previewers.new_buffer_previewer({
    --- @param self table
    --- @param entry { value: vault.Tag }
    define_preview = function(self, entry)
        local utils = require("vault.utils")
        --- @type vault.Tag
        local tag = entry.value
        local sources = tag.data.sources
        --- @type string[]
        local lines = {}
        --- @type vault.Tag.Documentation
        local documentation = tag.data.documentation:content()

        --- TODO: Implement documentation to previewer
        if documentation and documentation ~= "" then
            local doc_lines = vim.split(documentation, "\n")
            for _, doc_line in ipairs(doc_lines) do
                table.insert(lines, doc_line)
            end
            local separator = string.rep("-", 80)
            table.insert(lines, separator)
        end

        local seen_notes_paths = {}
        for slug, _ in pairs(sources) do
            local relpath = utils.slug_to_relpath(slug)
            if not seen_notes_paths[relpath] then
                seen_notes_paths[relpath] = true
                table.insert(lines, relpath)
            end
        end
        --- @type integer
        local bufnr = self.state.bufnr
        vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
        vim.api.nvim_set_option_value("filetype", "markdown", {
            buf = bufnr,
            scope = "local",
        })
        return vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    end,
})

M.properties = previewers.new_buffer_previewer({
    --- @param self table
    --- @param entry { value: vault.Property }
    define_preview = function(self, entry)
        --- @type integer
        local bufnr = self.state.bufnr
        local ok, lines, highlights = pcall(function()
            --- @type vault.Property
            local property = entry.value
            local preview_lines, preview_highlights = property_preview_lines(property)
            return normalize_preview_lines(preview_lines), preview_highlights
        end)
        if not ok then
            vim.api.nvim_buf_clear_namespace(bufnr, PROPERTY_PREVIEW_NS, 0, -1)
            render_preview_error(bufnr, lines)
            return
        end

        vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
        vim.api.nvim_buf_clear_namespace(bufnr, PROPERTY_PREVIEW_NS, 0, -1)
        for lnum, spans in pairs(highlights) do
            for _, span in ipairs(spans) do
                vim.api.nvim_buf_add_highlight(
                    bufnr,
                    PROPERTY_PREVIEW_NS,
                    span.hl,
                    lnum - 1,
                    span.col,
                    span.end_col
                )
            end
        end
        vim.api.nvim_set_option_value("filetype", "text", {
            buf = bufnr,
            scope = "local",
        })
    end,
})

-- Previewer for bases: show filter tree, formulas, views, and properties
M.bases = previewers.new_buffer_previewer({
    --- @param self table
    --- @param entry { value: vault.Base }
    define_preview = function(self, entry)
        --- @type vault.Base
        local base = entry.value
        --- @type string[]
        local lines = {}

        -- Header
        table.insert(lines, "# " .. base.data.name)
        table.insert(lines, "")

        -- Filters
        if base:has_filters() then
            table.insert(lines, "## Filters")
            table.insert(lines, "```yaml")
            local filter_str = vim.inspect(base.data.filters)
            for _, line in ipairs(vim.split(filter_str, "\n")) do
                table.insert(lines, line)
            end
            table.insert(lines, "```")
            table.insert(lines, "")
        else
            table.insert(lines, "## Filters")
            table.insert(lines, "_No filters defined_")
            table.insert(lines, "")
        end

        -- Formulas
        if base:has_formulas() then
            table.insert(lines, "## Formulas")
            for name, expr in pairs(base.data.formulas) do
                table.insert(lines, string.format("- **%s**: `%s`", name, expr))
            end
            table.insert(lines, "")
        end

        -- Views
        local view_count = base:view_count()
        if view_count > 0 and type(base.data.views) == "table" then
            table.insert(lines, "## Views (" .. tostring(view_count) .. ")")
            for i, view in ipairs(base.data.views) do
                local view_name = view.name or view.type or ("view " .. tostring(i))
                local view_type = view.type or "table"
                table.insert(lines, string.format("- **%s** (%s)", view_name, view_type))
            end
            table.insert(lines, "")
        end

        -- Properties
        if type(base.data.properties) == "table" and next(base.data.properties) then
            table.insert(lines, "## Properties")
            for key, prop in pairs(base.data.properties) do
                if type(prop) == "table" and prop.displayName then
                    table.insert(lines, string.format("- **%s** → %s", key, prop.displayName))
                else
                    table.insert(lines, string.format("- %s", key))
                end
            end
            table.insert(lines, "")
        end

        -- File info
        table.insert(lines, "---")
        table.insert(lines, "Path: " .. (base.data.relpath or ""))

        --- @type integer
        local bufnr = self.state.bufnr
        vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
        vim.api.nvim_set_option_value("filetype", "markdown", {
            buf = bufnr,
            scope = "local",
        })
    end,
})

-- Previewer for wikilinks: resolved shows target file, unresolved lists sources
M.wikilinks = previewers.new_buffer_previewer({
    --- @param self table
    --- @param entry { value: vault.Wikilink }
    define_preview = function(self, entry)
        local utils = require("vault.utils")
        --- @type vault.Wikilink
        local wikilink = entry.value
        local data = wikilink.data
        --- @type string[]
        local lines = {}

        local target_slug = data and data.target
        local abs_path = target_slug and utils.slug_to_path(target_slug) or nil
        local resolved = abs_path and vim.fn.filereadable(abs_path) == 1

        if resolved then
            -- Show the target note content (like the notes previewer)
            local ok, file_lines = pcall(vim.fn.readfile, abs_path)
            if ok and file_lines then
                lines = file_lines
            else
                lines = { "(could not read " .. abs_path .. ")" }
            end
        else
            -- Unresolved: show a synthesized summary of all sources
            local slug = data and data.slug or "<unknown>"
            table.insert(lines, "# [[" .. slug .. "]]")
            table.insert(lines, "")
            table.insert(lines, "_Unresolved wikilink — note does not exist yet._")
            table.insert(lines, "")

            local sources = data and data.sources
            if type(sources) == "table" and next(sources) then
                local source_count = vim.tbl_count(sources)
                table.insert(lines, "## Referenced in " .. tostring(source_count) .. " note(s)")
                table.insert(lines, "")

                for source_slug, lnum_map in pairs(sources) do
                    local relpath = utils.slug_to_relpath(source_slug)
                    if type(lnum_map) == "table" then
                        -- Collect line numbers from the sources map
                        local lnums = {}
                        for lnum, _ in pairs(lnum_map) do
                            if type(lnum) == "number" then
                                table.insert(lnums, lnum)
                            end
                        end
                        table.sort(lnums)
                        if #lnums > 0 then
                            local lnum_strs = {}
                            for _, n in ipairs(lnums) do
                                table.insert(lnum_strs, tostring(n))
                            end
                            table.insert(
                                lines,
                                "- " .. relpath .. " (line " .. table.concat(lnum_strs, ", ") .. ")"
                            )
                        else
                            table.insert(lines, "- " .. relpath)
                        end
                    else
                        table.insert(lines, "- " .. relpath)
                    end
                end
            else
                table.insert(lines, "_No source references found._")
            end

            -- Suggestions grouped by strategy from Rust scanner
            local suggestions = data and data.suggestions
            if type(suggestions) == "table" and next(suggestions) then
                -- Strategy display names (ordered)
                local strategy_order = { "jaro_winkler", "levenshtein", "contains", "prefix" }
                local strategy_labels = {
                    jaro_winkler = "Fuzzy (Jaro-Winkler)",
                    levenshtein = "Edit distance (Levenshtein)",
                    contains = "Substring match",
                    prefix = "Prefix match",
                }
                -- Collect all unique slugs already shown to avoid duplicates across strategies
                local seen = {}
                for _, strategy in ipairs(strategy_order) do
                    local candidates = suggestions[strategy]
                    if type(candidates) == "table" and #candidates > 0 then
                        -- Filter out already-shown slugs
                        local unique = {}
                        for _, c in ipairs(candidates) do
                            local s = c.slug or c[1] or "?"
                            if not seen[s] then
                                seen[s] = true
                                unique[#unique + 1] = c
                            end
                        end
                        if #unique > 0 then
                            table.insert(lines, "")
                            local label = strategy_labels[strategy] or strategy
                            table.insert(lines, "### " .. label)
                            for _, candidate in ipairs(unique) do
                                local candidate_slug = candidate.slug or candidate[1] or "?"
                                local score = candidate.score or candidate[2] or 0
                                local pct = math.floor(score * 100 + 0.5)
                                table.insert(lines, "- [[" .. candidate_slug .. "]] (" .. pct .. "%)")
                            end
                        end
                    end
                end
            end

            -- Aliases / variants
            if data and type(data.aliases) == "table" and next(data.aliases) then
                table.insert(lines, "")
                table.insert(lines, "## Aliases")
                for alias, _ in pairs(data.aliases) do
                    table.insert(lines, "- " .. tostring(alias))
                end
            end
        end

        -- Flatten any lines containing embedded newlines — nvim_buf_set_lines
        -- requires each element to be a single line (no \n characters).
        local flat = {}
        for _, line in ipairs(lines) do
            if type(line) == "string" and line:find("\n") then
                for _, sub in ipairs(vim.split(line, "\n", { plain = true })) do
                    flat[#flat + 1] = sub
                end
            else
                flat[#flat + 1] = type(line) == "string" and line or tostring(line)
            end
        end

        --- @type integer
        local bufnr = self.state.bufnr
        vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, flat)
        vim.api.nvim_set_option_value("filetype", "markdown", {
            buf = bufnr,
            scope = "local",
        })
    end,
})

M._property_preview_lines = property_preview_lines
M._normalize_preview_lines = normalize_preview_lines

return M
